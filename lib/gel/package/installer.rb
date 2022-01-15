# frozen_string_literal: true

require "rbconfig"
require "tempfile"
require "shellwords"

require_relative "../util"

class Gel::Package::Installer
  def initialize(store)
    @store = store
  end

  def gem(spec)
    g = GemInstaller.new(spec, @store)
    begin
      yield g
    rescue Exception
      g.abort!
      raise
    end
    g
  end

  class GemCompiler
    attr_reader :spec, :store, :root, :build_path

    def initialize(spec, store)
      @spec = spec
      @root_store = store

      if store.is_a?(Gel::MultiStore)
        platform_parts = []
        platform_parts << spec.platform if spec.platform && spec.platform != "ruby"
        platform_parts << spec.architecture if spec.architecture

        platform_dir = platform_parts.join("-") unless platform_parts.empty?

        store = store[platform_dir, spec.extensions.any?]
      end
      @store = store

      raise "gem already installed" if store.gem?(spec.name, spec.version)

      @config = Gel::Environment.config

      @root = store.gem_root(spec.name, spec.version)
      Gel::Util.rm_rf(@root) if @root && Dir.exist?(@root)

      if spec.extensions.any?
        @build_path = store.extension_path(spec.name, spec.version)
        Gel::Util.rm_rf(@build_path) if @build_path && Dir.exist?(@build_path)
      else
        @build_path = nil
      end
    end

    def abort!
      $stderr.puts "Gel::Util.rm_rf(#{root.inspect})" if root
      $stderr.puts "Gel::Util.rm_rf(#{build_path.inspect})" if build_path
      #Gel::Util.rm_rf(root) if root
      #Gel::Util.rm_rf(build_path) if build_path
    end

    def needs_compile?
      !!@build_path
    end

    def compile_ready?
      true
    end

    def with_build_environment(ext, install_dir)
      work_dir = File.expand_path(File.dirname(ext), root)

      Gel::Util.mkdir_p(install_dir)
      short_install_dir = Gel::Util.relative_path(work_dir, install_dir)

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
        yield work_dir, short_install_dir, local_config.path, log
      end
    ensure
      local_config.unlink if local_config
    end

    def gemfile_and_lockfile(rake: false)
      @gemfile ||=
        begin
          gemfile = Tempfile.new(["#{spec.name}.gemfile", ".rb"])
          gemfile.puts "source :local"
          spec.runtime_dependencies.each do |(name, operator_pairs)|
            arguments = [name, *operator_pairs.map { |op, ver| "#{op} #{ver}" }]
            gemfile.puts "gem #{arguments.map(&:inspect).join(", ")}"
          end
          if rake
            gemfile.puts "gem 'rake'" unless spec.runtime_dependencies.any? { |name, *| name == "rake" }
          end
          gemfile.close

          gemfile
        end

      @lockfile ||=
        begin
          lockfile = Tempfile.new(["#{spec.name}.lockfile", ".lock"])
          lockfile.close

          Gel::Environment.write_lock(store: @root_store, output: nil, gemfile: Gel::GemfileParser.parse(File.read(gemfile.path), gemfile.path, 1), lockfile: lockfile.path)

          lockfile
        end

      [@gemfile.path, @lockfile.path]
    end

    def build_environment(rake: false)
      gemfile, lockfile = gemfile_and_lockfile(rake: rake)

      {
        "RUBYLIB" => Gel::Environment.modified_rubylib,
        "GEL_STORE" => File.expand_path(@root_store.root),
        "GEL_GEMFILE" => gemfile,
        "GEL_LOCKFILE" => lockfile,
      }
    end

    def build_command(work_dir, log, *command, rake: false, **options)
      env = build_environment(rake: rake)
      env.merge!(command.shift) if command.first.is_a?(Hash)

      pid = spawn(
        env,
        *command,
        chdir: work_dir,
        in: IO::NULL,
        [:out, :err] => log,
        **options,
      )

      _, status = Process.waitpid2(pid)
      status
    end

    def compile_extconf(ext, install_dir)
      with_build_environment(ext, install_dir) do |work_dir, short_install_dir, local_config_path, log|
        status = build_command(
          work_dir, log,
          { "MAKEFLAGS" => "-j3" },
          RbConfig.ruby,
          "-r", local_config_path,
          File.basename(ext),
          *Shellwords.shellsplit(@config[:build, @spec.name] || ""),
        )
        raise "extconf exited with #{status.exitstatus}" unless status.success?

        _status = build_command(work_dir, log, "make", "clean", "DESTDIR=")
        # Ignore exit status

        status = build_command(work_dir, log, "make", "-j3", "DESTDIR=")
        raise "make exited with #{status.exitstatus}" unless status.success?

        status = build_command(work_dir, log, "make", "install", "DESTDIR=")
        raise "make install exited with #{status.exitstatus}" unless status.success?
      end
    end

    def compile_rakefile(ext, install_dir)
      with_build_environment(ext, install_dir) do |work_dir, short_install_dir, local_config_path, log|
        if File.basename(ext) =~ /mkrf_conf/i
          status = build_command(
            work_dir, log,
            RbConfig.ruby,
            "-r", local_config_path,
            File.basename(ext),
            rake: true,
          )
          raise Gel::Error::ExtensionBuildError.new(program_name: "mkrf_conf", exitstatus: status.exitstatus) unless status.success?
        end

        status = build_command(
          work_dir, log,
          { "RUBYARCHDIR" => short_install_dir, "RUBYLIBDIR" => short_install_dir },
          RbConfig.ruby,
          "-r", File.expand_path("../command", __dir__),
          "-e", "Gel::Command.run(ARGV)",
          "--",
          "exec",
          "rake",
          rake: true,
        )
        raise Gel::Error::ExtensionBuildError.new(program_name: "rake", exitstatus: status.exitstatus) unless status.success?
      end
    end

    def compile
      if spec.extensions.any?
        spec.extensions.each do |ext|
          case File.basename(ext)
          when /extconf/i
            compile_extconf ext, build_path
          when /mkrf_conf/i, /rakefile/i
            compile_rakefile ext, build_path
          else
            raise "Don't know how to build #{ext.inspect} yet"
          end
        end
      end
    end
  end

  class GitCompiler < GemCompiler
    def initialize(spec, store, path)
      super(spec, store)

      @root = @build_path = path
    end
  end

  class GemInstaller < GemCompiler
    def initialize(spec, store)
      super

      @files = {}
      @installed_files = []
      spec.require_paths&.each { |reqp| @files[reqp] = [] }
    end

    def install
      loadable_file_types = ["rb", RbConfig::CONFIG["DLEXT"], RbConfig::CONFIG["DLEXT2"]].compact.reject(&:empty?)
      loadable_file_types_re = /\.#{Regexp.union loadable_file_types}\z/
      loadable_file_types_pattern = "*.{#{loadable_file_types.join(",")}}"

      store.add_gem(spec.name, spec.version, spec.bindir, spec.executables, spec.require_paths, spec.runtime_dependencies, spec.extensions.any?) do
        is_first = true
        spec.require_paths.each do |reqp|
          location = is_first ? spec.version : [spec.version, reqp]
          files = @files[reqp].map { |s| s.sub(loadable_file_types_re, "") if s.match(loadable_file_types_re) }.compact
          store.add_lib(spec.name, location, files)
          is_first = false
        end

        if build_path
          files = Dir["#{build_path}/**/#{loadable_file_types_pattern}"].map do |file|
            file[build_path.size + 1..-1]
          end.map do |file|
            file.sub(loadable_file_types_re, "")
          end

          store.add_lib(spec.name, [spec.version, Gel::StoreGem::EXTENSION_SUBDIR_TOKEN], files)
        end
      end
    end

    def file(filename, io, source_mode)
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
      Gel::Util.mkdir_p(File.dirname(target))
      mode = 0444
      mode |= source_mode & 0200
      mode |= 0111 if source_mode & 0111 != 0
      if exe = spec.executables.find { |e| filename == "#{spec.bindir}/#{e}" }
        mode |= 0111
        @root_store.stub_set.add(File.basename(@store.root), [exe])
      end
      File.open(target, "wb", mode) do |f|
        f.write io.read
      end
    end
  end
end
