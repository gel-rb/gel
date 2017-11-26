require "fileutils"

class Paperback::Package::Installer
  def initialize(store)
    @store = store
  end

  def gem(spec)
    @spec = spec
    @files = []

    yield self

    @store.add_gem(spec.name, spec.version, spec.bindir, spec.require_paths) do
      @store.add_lib(spec.name, spec.version, @files.map { |s| s.sub(/\.(?:so|bundle|rb)\z/, "") })
    end
  end

  def file(filename, io)
    root = File.expand_path("#{@store.root}/gems/#{@spec.name}-#{@spec.version}")
    target = File.expand_path("#{root}/#{filename}")
    raise "invalid filename" unless target.start_with?("#{root}/")
    @spec.require_paths.each do |reqp|
      prefix = "#{root}/#{reqp}/"
      if target.start_with?(prefix)
        @files << target[prefix.size..-1]
      end
    end
    raise "won't overwrite #{target}" if File.exist?(target)
    FileUtils.mkdir_p(File.dirname(target))
    File.open(target, "wb") do |f|
      f.write io.read
    end
  end
end
