require "fileutils"
require "pathname"
require "rbconfig"

class Paperback::Package::Installer
  def initialize(store)
    @store = store
  end

  def gem(spec)
    g = GemInstaller.new(spec, @store)
    yield g
    g
  end

  class GemInstaller
    attr_reader :spec, :store, :root, :build_path

    def initialize(spec, store)
      @spec = spec
      @store = store

      @root = store.gem_root(spec.name, spec.version)
      if spec.extensions.any?
        @build_path = store.extension_path(spec.name, spec.version)
      end

      @files = {}
      @installed_files = []
      spec.require_paths.each { |reqp| @files[reqp] = [] }
    end

    def compile_extension(ext, install_dir)
      raise "Don't know how to build #{ext.inspect} yet" unless ext =~ /extconf/

      work_dir = File.expand_path(File.dirname(ext), root)

      FileUtils.mkdir_p(install_dir)
      short_install_dir = Pathname.new(install_dir).relative_path_from(Pathname.new(work_dir)).to_s

      local_config = Tempfile.new(["config", ".rb"])
      local_config.write(<<-RUBY)
        require "rbconfig"

        RbConfig::MAKEFILE_CONFIG["sitearchdir"] =
          RbConfig::MAKEFILE_CONFIG["sitelibdir"] =
          RbConfig::CONFIG["sitearchdir"] =
          RbConfig::CONFIG["sitelibdir"] = #{short_install_dir.dump}.freeze
      RUBY
      local_config.close

      File.open("#{install_dir}/build.log", "w") do |log|
        pid = spawn(
          { "RUBYOPT" => nil },
          RbConfig.ruby, "--disable=gems",
          #"-I", __dir__.chomp!("paperback/package"), "-r", "paperback/runtime",
          "-r", local_config.path,
          File.basename(ext),
          chdir: work_dir,
          in: IO::NULL,
          [:out, :err] => log,
        )

        _, status = Process.waitpid2(pid)
        raise "extconf exited with #{status.exitstatus}" unless status.success?

        pid = spawn(
          "make", "clean",
          "DESTDIR=",
          chdir: work_dir,
          in: IO::NULL,
          [:out, :err] => log,
        )

        _, status = Process.waitpid2(pid)
        # Ignore exit status

        pid = spawn(
          "make",
          "DESTDIR=",
          chdir: work_dir,
          in: IO::NULL,
          [:out, :err] => log,
        )

        _, status = Process.waitpid2(pid)
        raise "make exited with #{status.exitstatus}" unless status.success?

        pid = spawn(
          "make", "install",
          "DESTDIR=",
          chdir: work_dir,
          in: IO::NULL,
          [:out, :err] => log,
        )

        _, status = Process.waitpid2(pid)
        raise "make install exited with #{status.exitstatus}" unless status.success?
      end
    ensure
      local_config.unlink if local_config
    end

    def compile
      if spec.extensions.any?
        spec.extensions.each do |ext|
          compile_extension ext, build_path
        end
      end
    end

    def install
      loadable_file_types = ["rb", RbConfig::CONFIG["DLEXT"], RbConfig::CONFIG["DLEXT2"]].reject(&:empty?)
      loadable_file_types_re = /\.#{Regexp.union loadable_file_types}\z/
      loadable_file_types_pattern = "*.{#{loadable_file_types.join(",")}}"

      store.add_gem(spec.name, spec.version, spec.bindir, spec.require_paths, spec.runtime_dependencies, spec.extensions.any?) do
        is_first = true
        spec.require_paths.each do |reqp|
          location = is_first ? spec.version : [spec.version, reqp]
          store.add_lib(spec.name, location, @files[reqp].map { |s| s.sub(loadable_file_types_re, "") })
          is_first = false
        end

        if build_path
          files = Dir["#{build_path}/**/#{loadable_file_types_pattern}"].map do |file|
            file[build_path.size + 1..-1]
          end.map do |file|
            file.sub(loadable_file_types_re, "")
          end

          store.add_lib(spec.name, [spec.version, Paperback::StoreGem::EXTENSION_SUBDIR_TOKEN], files)
        end
      end
    end

    def file(filename, io)
      target = File.expand_path(filename, root)
      raise "invalid filename #{target.inspect} outside #{(root + "/").inspect}" unless target.start_with?("#{root}/")
      return if @installed_files.include?(target)
      @installed_files << target
      spec.require_paths.each do |reqp|
        prefix = "#{root}/#{reqp}/"
        if target.start_with?(prefix)
          @files[reqp] << target[prefix.size..-1]
        end
      end
      raise "won't overwrite #{target}" if File.exist?(target)
      FileUtils.mkdir_p(File.dirname(target))
      File.open(target, "wb") do |f|
        f.write io.read
      end
    end
  end
end
