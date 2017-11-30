require "fileutils"

class Paperback::Package::Installer
  def initialize(store)
    @store = store
  end

  def gem(spec)
    @spec = spec
    @files = {}
    @installed_files = []
    spec.require_paths.each { |reqp| @files[reqp] = [] }
    @root = @store.gem_root(@spec.name, @spec.version)

    yield self

    @store.add_gem(spec.name, spec.version, spec.bindir, spec.require_paths, spec.runtime_dependencies) do
      is_first = true
      spec.require_paths.each do |reqp|
        location = is_first ? spec.version : [spec.version, reqp]
        @store.add_lib(spec.name, location, @files[reqp].map { |s| s.sub(/\.(?:so|bundle|rb)\z/, "") })
        is_first = false
      end
    end
  end

  def file(filename, io)
    target = File.expand_path("#{@root}/#{filename}")
    raise "invalid filename #{target.inspect} outside #{(@root + "/").inspect}" unless target.start_with?("#{@root}/")
    return if @installed_files.include?(target)
    @installed_files << target
    @spec.require_paths.each do |reqp|
      prefix = "#{@root}/#{reqp}/"
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
