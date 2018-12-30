# frozen_string_literal: true

require_relative "path_catalog"

class Paperback::GitCatalog
  attr_reader :git_depot, :remote, :ref

  def initialize(git_depot, remote, ref)
    @git_depot = git_depot
    @remote = remote
    @ref = ref
  end

  def checkout_result
    @result ||= git_depot.resolve_and_checkout(remote, ref)
  end

  def revision
    checkout_result[0]
  end

  def gem_info(name)
    path_catalog.gem_info(name)
  end

  def path_catalog
    @path_catalog ||= Paperback::PathCatalog.new(checkout_result[1])
  end
end
