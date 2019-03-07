# frozen_string_literal: true

class Gel::DirectGem < Gel::StoreGem
  def load_gemspec(filename)
    Gel::GemspecParser.parse(File.read(filename), filename, isolate: false)
  end

  def initialize(root, name, version = nil)
    root = File.expand_path(root)
    if File.exist?("#{root}/#{name}.gemspec")
      gemspec = load_gemspec("#{root}/#{name}.gemspec")
    elsif File.exist?("#{root}/#{name}/#{name}.gemspec")
      root = "#{root}/#{name}"
      gemspec = load_gemspec("#{root}/#{name}.gemspec")
    else
      super(root, name, version, [], bindir: "bin", executables: [], require_paths: ["lib"], dependencies: [])
      return
    end

    info = {
      bindir: gemspec.bindir || "bin",
      executables: gemspec.executables,
      require_paths: gemspec.require_paths || [gemspec.require_path].compact,
      dependencies: gemspec.runtime_dependencies,
    }

    super(root, name, version || gemspec.version, gemspec.extensions, info)
  end
end
