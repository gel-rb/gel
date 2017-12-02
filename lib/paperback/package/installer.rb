require "fileutils"

class Paperback::Package::Installer
  def initialize(store)
    @store = store
  end

  def gem(spec)
    root = @store.gem_root(spec.name, spec.version)

    g = GemInstaller.new(spec, root)
    yield g
    g.install(@store)
  end

  class GemInstaller
    attr_reader :spec, :root

    def initialize(spec, root)
      @spec = spec
      @root = root

      @files = {}
      @installed_files = []
      spec.require_paths.each { |reqp| @files[reqp] = [] }
    end

    def install(store)
      extensions = Regexp.union(["rb", RbConfig::CONFIG["DLEXT"], RbConfig::CONFIG["DLEXT2"]].reject(&:empty?))
      extensions = /\.#{extensions}\z/

      store.add_gem(spec.name, spec.version, spec.bindir, spec.require_paths, spec.runtime_dependencies) do
        is_first = true
        spec.require_paths.each do |reqp|
          location = is_first ? spec.version : [spec.version, reqp]
          store.add_lib(spec.name, location, @files[reqp].map { |s| s.sub(extensions, "") })
          is_first = false
        end
      end
    end

    def file(filename, io)
      target = File.expand_path("#{root}/#{filename}")
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
