# frozen_string_literal: true

require_relative "path_catalog"

class Gel::GitCatalog
  attr_reader :git_depot, :remote, :ref_type, :ref

  def initialize(git_depot, remote, ref_type, ref, revision = nil)
    @git_depot = git_depot
    @remote = remote
    @ref_type = ref_type
    @ref = ref
    @revision = revision

    @monitor = Monitor.new
    @result = nil
  end

  def checkout_result
    @result ||
      @monitor.synchronize { @result ||= git_depot.resolve_and_checkout(remote, ref) }
  end

  def revision
    @revision || checkout_result[0]
  end

  def gem_info(name)
    path_catalog.gem_info(name)
  end

  def path_catalog
    @path_catalog ||= Gel::PathCatalog.new(checkout_result[1])
  end

  def prepare
    checkout_result
  end

  def path
    git_depot.git_path(remote, revision)
  end
end
