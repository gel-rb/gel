# frozen_string_literal: true

class Gel::DirectGem < Gel::StoreGem
  def load_gemspec(filename)
    Gel::GemspecParser.parse(File.read(filename), filename, isolate: false)
  end

  def self.from_block(*args, &block)
    filename, _lineno = block.source_location

    result = Gel::GemspecParser::Context::Gem::Specification.new(*args, &block)

    new(File.dirname(filename), result.name, loaded_gemspec: result)
  end

  def initialize(root, name, version = nil, loaded_gemspec: nil)
    root = File.expand_path(root)
    if loaded_gemspec
      gemspec = loaded_gemspec
    elsif File.exist?("#{root}/#{name}.gemspec")
      gemspec = load_gemspec("#{root}/#{name}.gemspec")
    elsif File.exist?("#{root}/#{name}/#{name}.gemspec")
      root = "#{root}/#{name}"
      gemspec = load_gemspec("#{root}/#{name}.gemspec")
    else
      super(root, name, version, [], bindir: "bin", executables: [], require_paths: ["lib"], dependencies: [])
      return
    end

    require_paths = gemspec.require_paths&.compact || [gemspec.require_path || "lib"]

    info = {
      bindir: gemspec.bindir || "bin",
      executables: gemspec.executables,
      require_paths: require_paths,
      dependencies: gemspec.runtime_dependencies,
    }

    super(root, name, version || Gel::Support::GemVersion.new(gemspec.version).to_s, ("#{root}/ext" if Array(gemspec.extensions).any?), info)
  end
end
