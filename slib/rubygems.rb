# frozen_string_literal: true

# The goal here is not to be a full drop-in replacement of RubyGems'
# API.
#
# The threshold is basically "things that already-popular/established
# gems assume are there without checking".

require_relative "../lib/gel/runtime"

module Gem
  Version = Gel::Support::GemVersion
  Requirement = Gel::Support::GemRequirement
  Platform = Gel::Support::GemPlatform

  VERSION = "3.compat"

  autoload :Deprecate, "rubygems/deprecate"

  class Dependency
    attr_reader :name
    attr_reader :requirement
    attr_reader :type

    def initialize(name, requirement, type = :runtime)
      @name = name
      @requirement = requirement
      @type = type
    end
  end

  LoadError = Class.new(::LoadError)

  class Specification
    class << self
      include Enumerable
    end

    def self.load(filename)
      new(Gel::DirectGem.new(File.dirname(filename), File.basename(filename, ".gemspec")))
    end

    def self.find_by_name(name, *requirements)
      if g = Gel::Environment.find_gem(name, *requirements)
        new(g)
      else
        # TODO: Should probably be a Gel exception instead?
        raise Gem::LoadError, "Unable to find gem #{name.inspect}" + (requirements.empty? ? "" : " (#{requirements.join(", ")})")
      end
    end

    def self.find_by_path(path)
      if g = Gel::Environment.gem_for_path(path)
        new(g)
      end
    end

    def self.each(&block)
      Gel::Environment.store.each.map { |g| new(g) }.each(&block)
    end

    def initialize(*args, &definition)
      if definition
        # Someone's trying to manually execute a gemspec definition
        # block. That's not something we particularly want to support
        # (nor need to, for normal use), but it's something that people
        # do, so...

        @store_gem = Gel::DirectGem.from_block(*args, &definition)
      elsif store_gem = args.size == 1 && args.first
        @store_gem = store_gem
      else
        raise ArgumentError, "Expected a store_gem"
      end
    end

    def name
      @store_gem.name
    end

    def version
      Gem::Version.new(@store_gem.version)
    end

    def dependencies
      @store_gem.dependencies.map do |name, pairs|
        Gem::Dependency.new(name, Gem::Requirement.new(pairs.map { |op, ver| "#{op} #{ver}" }), :runtime)
      end
    end
    alias runtime_dependencies dependencies

    def gem_dir
      @store_gem.root
    end
    alias full_gem_path gem_dir

    def require_paths
      @store_gem.relative_require_paths.map(&:dup)
    end

    def full_require_paths
      @store_gem.require_paths.map(&:dup)
    end

    def platform
      nil
    end

    def files
      []
    end
  end

  def self.try_activate(file)
    Gel::Environment.resolve_gem_path(file) != file
  rescue LoadError
    false
  end

  def self.ruby
    RbConfig.ruby
  end

  def self.platforms
    Gel::Support::GemPlatform.platforms
  end

  def self.win_platform?
    false
  end

  def self.loaded_specs
    result = {}
    Gel::Environment.activated_gems.each do |name, store_gem|
      result[name] = Gem::Specification.new(store_gem)
    end
    result
  end

  def self.find_files(pattern)
    Gel::Environment.store.each.
      flat_map(&:require_paths).
      flat_map { |dir| Dir[File.join(dir, pattern)] }
  end

  def self.refresh
    # no-op
  end

  def self.dir
    Gel::Environment.store.root
  end

  def self.path
    Gel::Environment.store.paths
  end

  def self.default_dir
    dir
  end

  def self.activate_bin_path(gem_name, bin_name, version = nil)
    if gem_name == "bundler" && bin_name == "bundle"
      # Extra-special case: this is the bundler binstub, we need to
      # re-exec to hand over.

      ENV["RUBYLIB"] = Gel::Environment.original_rubylib
      exec RbConfig.ruby, "--", $0, *ARGV
    end

    if gem_name == "gel" && bin_name == "gel"
      # Another extra-special case: gel is already activated, but it's
      # being invoked via a rubygems-installed binstub. We can't
      # activate gel inside gel, but we also don't need to: we know
      # exactly which file they need.

      return File.expand_path("../exe/gel", __dir__)
    end

    if g = Gel::Environment.activated_gems[gem_name]
      Gel::Environment.gem g.name, version if version
    elsif g = Gel::Environment.find_gem(gem_name, *version) do |gg|
        gg.executables.include?(bin_name)
      end

      Gel::Environment.gem g.name, g.version
    elsif g = Gel::Environment.find_gem(gem_name, *version)
      raise "#{g.name} (#{g.version}) doesn't contain executable #{bin_name.inspect}"
    elsif version && Gel::Environment.find_gem(gem_name)
      raise "#{gem_name} (#{version}) not available"
    else
      raise "Unknown gem #{gem_name.inspect}"
    end

    Gel::Environment.find_executable(bin_name, g.name, g.version)
  rescue => ex
    # This method may be our entry-point, if we're being invoked by a
    # rubygems binstub. Detect that situation, and provide nicer error
    # reporting.

    raise unless locations = caller_locations(2, 2)
    raise unless locations.size == 1
    raise unless path = locations.first.absolute_path
    raise unless File.exist?(path) && File.readable?(path)
    raise unless File.open(path, "rb") { |f| f.read(1024).include?("\n# This file was generated by RubyGems.\n") }

    require_relative "../lib/gel/command"
    Gel::Command.handle_error(ex)
  end

  def self.bin_path(gem_name, bin_name, version = nil)
    if g = Gel::Environment.activated_gems[gem_name]
      Gel::Environment.gem g.name, version if version

      Gel::Environment.find_executable(bin_name, g.name, g.version)
    elsif Gel::Environment.find_gem(gem_name)
      raise "Gem #{gem_name.inspect} is not active"
    else
      raise "Unknown gem #{gem_name.inspect}"
    end
  end
end

def gem(*args)
  Gel::Environment.gem(*args)
end
private :gem

module Kernel
  module_function

  alias_method :require_without_gel, :require
  singleton_class.undef_method :require

  def require(path)
    require_without_gel Gel::Environment.resolve_gem_path(path)
  end
  private :require
end
