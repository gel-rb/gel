# frozen_string_literal: true

require_relative "gemspec_parser"

class Gel::PathCatalog
  attr_reader :path

  DEFAULT_GLOB = "{,*,*/*}.gemspec"

  def initialize(path)
    @path = path
    @cache = {}
    @gemspecs = nil
  end

  def gemspecs
    @gemspecs ||= Dir["#{@path}/#{DEFAULT_GLOB}"]
  end

  def gem_info(name)
    @cache.fetch(name) { @cache[name] = _info(name) }
  end

  def _info(name)
    gemspec = gemspecs.detect { |path| File.basename(path) == "#{name}.gemspec" }
    return unless gemspec
    gemspec = gemspec_from(gemspec)

    info = {}
    info[gemspec.version] = {
      dependencies: gemspec.runtime_dependencies,
      ruby: gemspec.required_ruby_version,
    }

    info
  end

  def gemspec_from(filename)
    Gel::GemspecParser.parse(File.read(filename), filename)
  end

  def prepare
  end
end
