module Paperback
  module Support
  end
end

require_relative "paperback/support/gem_version"
require_relative "paperback/support/gem_requirement"

require_relative "paperback/environment"
require_relative "paperback/store"
require_relative "paperback/store_gem"
require_relative "paperback/locked_store"
require_relative "paperback/catalog"

require_relative "paperback/gemfile_parser"
require_relative "paperback/lock_parser"
require_relative "paperback/lock_loader"
require_relative "paperback/installer"

require_relative "paperback/package"
require_relative "paperback/package/inspector"
require_relative "paperback/package/installer"

require_relative "paperback/support/tar"

require_relative "paperback/version"
