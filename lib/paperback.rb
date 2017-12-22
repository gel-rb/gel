module Paperback
  module Support
  end
end

require_relative "paperback/support/gem_version"
require_relative "paperback/support/gem_requirement"

require_relative "paperback/environment"
require_relative "paperback/store"
require_relative "paperback/store_gem"
require_relative "paperback/direct_gem"
require_relative "paperback/locked_store"
require_relative "paperback/multi_store"

require_relative "paperback/gemspec_parser"
require_relative "paperback/gemfile_parser"
require_relative "paperback/lock_parser"
require_relative "paperback/lock_loader"
