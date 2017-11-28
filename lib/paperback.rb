module Paperback
  module Support
  end
end

require "paperback/support/gem_version"
require "paperback/support/gem_requirement"

require "paperback/environment"
require "paperback/store"
require "paperback/locked_store"

require "paperback/package"
require "paperback/package/inspector"
require "paperback/package/installer"

require "paperback/support/tar"

require "paperback/version"
