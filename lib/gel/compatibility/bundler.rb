# frozen_string_literal: true

module Bundler
  ORIGINAL_ENV = ::ENV.to_h

  VERSION = "3.compat"

  def self.setup
    Gel::Environment.activate(output: $stderr)
  end

  def self.original_env
    ORIGINAL_ENV.dup
  end

  def self.require(*groups)
    Gel::Environment.require_groups(*groups)
  end

  def self.default_lockfile
    Pathname.new(Gel::Environment.lockfile_name)
  end

  def self.bundle_path
    base_store = Gel::Environment.store
    base_store = base_store.inner if base_store.is_a?(Gel::LockedStore)

    Pathname.new(base_store.root)
  end

  def self.root
    Pathname.new(Gel::Environment.gemfile.filename).dirname
  end

  module RubygemsIntegration
    def self.loaded_specs(gem_name)
      Gem::Specification.new(Gel::Environment.activated_gems[gem_name])
    end
  end

  # This is only emulated for bin/spring: we really don't want to try to
  # actually reproduce Bundler's API
  class LockfileParser
    def initialize(content)
    end

    def specs
      []
    end
  end

  def self.rubygems
    RubygemsIntegration
  end

  def self.with_original_env
    # TODO
    yield
  end

  def self.with_clean_env
    # TODO
    yield
  end

  def self.with_unbundled_env
    # TODO
    yield
  end

  def self.settings
    if gemfile = Gel::Environment.gemfile
      { "gemfile" => gemfile.filename }
    else
      {}
    end
  end
end
