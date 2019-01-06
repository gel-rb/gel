# frozen_string_literal: true

module Bundler
  def self.setup
    Paperback::Environment.activate(output: $stderr)
  end

  def self.require(*groups)
    Paperback::Environment.require_groups(*groups)
  end

  module Rubygems
    def self.loaded_specs(gem_name)
      Gem::Specification.new(Paperback::Environment.activated_gems[gem_name])
    end
  end

  def self.rubygems
    Rubygems
  end

  def self.with_original_env
    # TODO
    yield
  end

  def self.with_clean_env
    # TODO
    yield
  end

  def self.settings
    if gemfile = Paperback::Environment.gemfile
      { "gemfile" => gemfile.filename }
    else
      {}
    end
  end
end
