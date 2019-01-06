# frozen_string_literal: true

# The goal here is not to be a full drop-in replacement of RubyGems'
# API.
#
# The threshold is basically "things that already-popular/established
# gems assume are there without checking".

module Gem
  Version = Paperback::Support::GemVersion
  Requirement = Paperback::Support::GemRequirement

  class Dependency
    attr_reader :name
    attr_reader :requirement
    attr_reader :type

    def initialize(name, requirement, type)
      @name = name
      @requirement = requirement
      @type = type
    end
  end

  LoadError = Class.new(::LoadError)

  class Specification
    def self.find_by_name(name, *requirements)
      if g = Paperback::Environment.find_gem(name, *requirements)
        new(g)
      end
    end

    def self.each(&block)
      Paperback::Environment.store.map { |g| new(g) }.each(&block)
    end

    def initialize(store_gem)
      @store_gem = store_gem
    end

    def name
      @store_gem.name
    end

    def version
      Gem::Version.new(@store_gem.version)
    end

    def dependencies
      @store_gem.dependencies.map do |name, pairs|
        Gem::Dependency.new(name, pairs.map { |op, ver| "#{op} #{ver}" }, :runtime)
      end
    end
    alias runtime_dependencies dependencies

    def gem_dir
      @store_gem.root
    end
    alias full_gem_path gem_dir

    def require_paths
      base = Pathname.new(gem_dir)

      @store_gem.require_paths.map do |path|
        Pathname.new(path).relative_path_from(base).to_s
      end
    end
  end

  class DependencyInstaller
    def install(name, requirement = nil)
      require_relative "../catalog"
      require_relative "../work_pool"

      Paperback::WorkPool.new(2) do |work_pool|
        catalog = Paperback::Catalog.new("https://rubygems.org", work_pool: work_pool)

        return Paperback::Environment.install_gem([catalog], name, requirement)
      end
    end
  end

  def self.try_activate(file)
    Paperback::Environment.resolve_gem_path(file) != file
  rescue LoadError
    false
  end

  def self.ruby
    RbConfig.ruby
  end

  def self.win_platform?
    false
  end

  def self.loaded_specs
    result = {}
    Paperback::Environment.activated_gems.each do |name, store_gem|
      result[name] = Gem::Specification.new(store_gem)
    end
    result
  end

  def self.find_files(pattern)
    Paperback::Environment.store.each.
      flat_map(&:require_paths).
      flat_map { |dir| Dir[File.join(dir, pattern)] }
  end

  def self.refresh
    # no-op
  end

  def self.path
    Paperback::Environment.store.paths
  end

  def self.default_dir
    path.first
  end

  def self.activate_bin_path(gem_name, bin_name, version = nil)
    if g = Paperback::Environment.activated_gems[gem_name]
      Paperback::Environment.gem g.name, version if version
    else
      g = Paperback::Environment.find_gem(name, *version) do |g|
        g.executables.include?(bin_name)
      end

      Paperback::Environment.gem g.name, g.version
    end

    Paperback::Environment.find_executable(bin_name, g.name, g.version)
  end

  def self.bin_path(gem_name, bin_name, version = nil)
    if g = Paperback::Environment.activated_gems[gem_name]
      Paperback::Environment.gem g.name, version if version

      Paperback::Environment.find_executable(bin_name, g.name, g.version)
    end
  end
end

def gem(*args)
  Paperback::Environment.gem(*args)
end
private :gem

def require(path)
  super Paperback::Environment.resolve_gem_path(path)
end
private :require

require "rubygems/deprecate"
