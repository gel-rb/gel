require "fileutils"

class Paperback::Package::Installer
  def initialize(store)
    @store = store
  end

  def gem(spec)
    @spec = spec

    yield self

    @store.add_gem(spec.name, spec.version, spec.bindir, spec.require_paths)
  end

  def file(filename, io)
    root = File.expand_path("#{@store.root}/gems/#{@spec.name}-#{@spec.version}")
    target = File.expand_path("#{root}/#{filename}")
    raise "invalid filename" unless target.start_with?("#{root}/")
    raise "won't overwrite" if File.exist?(target)
    FileUtils.mkdir_p(File.dirname(target))
    File.open(target, "wb") do |f|
      f.write io.read
    end
  end
end
