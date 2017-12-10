class Paperback::DirectGem < Paperback::StoreGem
  def load_gemspec(filename)
    Paperback::GemspecParser.parse(File.read(filename), filename)
  end

  def initialize(root, name, version = nil)
    root = File.expand_path(root)
    if File.exist?("#{root}/#{name}.gemspec")
      gemspec = load_gemspec("#{root}/#{name}.gemspec")
    elsif File.exist?("#{root}/#{name}/#{name}.gemspec")
      root = "#{root}/#{name}"
      gemspec = load_gemspec("#{root}/#{name}.gemspec")
    else
      super(root, name, version, [], require_paths: ["lib"], dependencies: [])
      return
    end

    info = {
      require_paths: gemspec.require_paths || [gemspec.require_path].compact,
      dependencies: gemspec.runtime_dependencies,
    }

    super(root, name, version || gemspec.version, gemspec.extensions, info)
  end
end
