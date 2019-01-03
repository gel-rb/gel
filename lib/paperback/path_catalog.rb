# frozen_string_literal: true

require_relative "gemspec_parser"

class Paperback::PathCatalog
  attr_reader :path

  def initialize(path)
    @path = path
    @cache = {}
  end

  def gem_info(name)
    @cache.fetch(name) { @cache[name] = _info(name) }
  end

  def _info(name)
    gemspec = gemspec_from("#{name}.gemspec") ||
      gemspec_from("#{name}/#{name}.gemspec")
    return unless gemspec

    info = {}
    info[gemspec.version] = {
      dependencies: gemspec.runtime_dependencies,
      ruby: gemspec.required_ruby_version,
    }

    info
  end

  def gemspec_from(filename)
    filename = File.expand_path("#{path}/#{filename}")
    if File.exist?(filename)
      Paperback::GemspecParser.parse(File.read(filename), filename)
    end
  end

  def prepare
  end
end
