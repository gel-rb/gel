# frozen_string_literal: true

module Gel
  module Support
  end

  module Vendor
  end

  def self.stub(name)
    require_relative "gel/command"
    Gel::Command.run(["stub", name, *ARGV])
  end

  # This can be used to e.g. identify $LOADED_FEATURES or source_locations
  # entries that belong to the running Gel instance
  def self.self_location
    File.expand_path("..", __dir__)
  end
end

require_relative "gel/support/gem_version"
require_relative "gel/support/gem_requirement"

require_relative "gel/config"
require_relative "gel/environment"
require_relative "gel/store"
require_relative "gel/store_gem"
require_relative "gel/direct_gem"
require_relative "gel/locked_store"
require_relative "gel/multi_store"
require_relative "gel/error"

require_relative "gel/gemspec_parser"
require_relative "gel/gemfile_parser"
require_relative "gel/lock_parser"
require_relative "gel/lock_loader"
require_relative "gel/version"
