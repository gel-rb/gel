# frozen_string_literal: true

require_relative "package"
require_relative "package/extracter"

class Gel::VendorCatalog
  attr_reader :path

  def initialize(path)
    @path = path
    @cache = {}
  end

  def prepare
    Dir["#{@path}/*.gem"].each do |filename|
      @filename = filename
      Gel::Package::Extracter.extract(filename, self)
      @filename = nil
    end
  end

  # Gel::Package::Extracter.extract callback
  def gem(spec)
    @cache[spec.name] ||= {}
    @cache[spec.name][Gel::Support::GemVersion.new(spec.version).to_s] = {
      local_path: @filename,
      dependencies: spec.runtime_dependencies.to_a.map { |n, pairs| [n, pairs.to_a.map { |pr| pr.join(" ") }] },
      #ruby: spec.required_ruby_version,
    }
  end

  def download_gem(name, version)
    @cache.dig(name, version, :local_path)
  end

  def gem_info(name)
    @cache[name]
  end
end
