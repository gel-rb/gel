# frozen_string_literal: true

require "fileutils"
require "monitor"

module Paperback::Catalog::Common
  def initialize(uri, uri_identifier, httpool:, work_pool:, cache:)
    @uri = uri
    @uri_identifier = uri_identifier
    @httpool = httpool
    @work_pool = work_pool
    @cache = cache

    @pinboard = nil

    @monitor = Monitor.new
    @refresh_cond = @monitor.new_cond

    @done_refresh = {}

    @gem_info = {}
    @error = nil
  end

  def gem_info(gem_name)
    gems_to_refresh = []

    @monitor.synchronize do
      if info = _info(gem_name)
        gems_to_refresh = walk_gem_dependencies(gem_name, info)
        return info
      end
    end

    refresh_gem gem_name, true

    @monitor.synchronize do
      info = nil
      @refresh_cond.wait_until { info = _info(gem_name) }
      gems_to_refresh = walk_gem_dependencies(gem_name, info)
      info
    end
  ensure
    gems_to_refresh.each do |dep_name|
      refresh_gem dep_name
    end
  end

  private

  def walk_gem_dependencies(gem_name, info)
    unless @done_refresh[gem_name]
      gems_to_refresh = info.values.flat_map { |v| v[:dependencies] }.map(&:first).uniq
      @done_refresh[gem_name] = true
    end

    gems_to_refresh || []
  end

  def _info(name)
    raise @error if @error
    if i = @gem_info[name]
      raise i if i.is_a?(Exception)
      i
    end
  end

  def pinboard
    @pinboard || @monitor.synchronize do
      @pinboard ||=
        begin
          pinboard_dir = File.expand_path("#{@cache}/#{self.class::CACHE_TYPE}/#{@uri_identifier}")
          FileUtils.mkdir_p(pinboard_dir) unless Dir.exist?(pinboard_dir)
          Paperback::Pinboard.new(pinboard_dir, httpool: @httpool, work_pool: @work_pool)
        end
    end
  end

  def uri(*parts)
    URI(File.join(@uri.to_s, *parts))
  end
end
