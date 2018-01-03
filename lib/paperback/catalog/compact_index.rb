# frozen_string_literal: true

require "set"
require "fileutils"
require "monitor"

require_relative "../pinboard"

class Paperback::Catalog::CompactIndex
  def initialize(uri, uri_identifier, httpool:, work_pool:)
    @uri = uri
    @uri_identifier = uri_identifier
    @httpool = httpool
    @work_pool = work_pool

    @gem_tokens = Hash.new("NONE")
    @needs_update = true
    @updating = false
    @active_gems = Set.new
    @pending_gems = Set.new

    @monitor = Monitor.new
    @refresh_cond = @monitor.new_cond

    @done_refresh = {}

    @gem_info = {}
  end

  def update
    @monitor.synchronize do
      return false unless @needs_update
      @needs_update = false
      @updating = true
    end

    pinboard.async_file(uri("versions"), tail: true) do |f|
      new_tokens = {}

      started = false
      f.each_line do |line|
        unless started
          started ||= line == "---\n"
          next
        end
        line.chop!

        name, _versions, token = line.split
        new_tokens[name] = token
      end

      @monitor.synchronize do
        @gem_tokens.update new_tokens
        @updating = false
      end

      (@active_gems | @pending_gems).each do |name|
        refresh_gem(name)
      end
    end

    true
  end

  def gem_info(gem_name)
    gems_to_refresh = []

    @monitor.synchronize do
      if @gem_info.key?(gem_name)
        unless @done_refresh[gem_name]
          gems_to_refresh = @gem_info[gem_name].values.flat_map { |v| v[:dependencies] }.map(&:first).uniq
          @done_refresh[gem_name] = true
        end
        return @gem_info[gem_name]
      end
    end

    refresh_gem gem_name

    @monitor.synchronize do
      @refresh_cond.wait_until { @gem_info.key?(gem_name) }
      unless @done_refresh[gem_name]
        gems_to_refresh = @gem_info[gem_name].values.flat_map { |v| v[:dependencies] }.map(&:first).uniq
        @done_refresh[gem_name] = true
      end
      @gem_info[gem_name]
    end
  ensure
    gems_to_refresh.each do |dep_name|
      refresh_gem dep_name
    end
  end

  def refresh_gem(gem_name)
    update

    already_active = nil
    @monitor.synchronize do
      if @updating && !@gem_tokens.key?(gem_name)
        @pending_gems << gem_name
        return
      end

      already_active = !@active_gems.add?(gem_name)
    end

    pinboard.async_file(uri("info", gem_name), token: @gem_tokens[gem_name], only_updated: already_active) do |f|
      dependency_names = Set.new
      info = {}

      started = false
      f.each_line do |line|
        unless started
          started ||= line == "---\n"
          next
        end
        line.chop!

        version, rest = line.split(" ", 2)
        deps, attrs = rest.split("|", 2)

        deps = deps.split(",").map do |entry|
          key, constraints = entry.split(":", 2)
          constraints = constraints.split("&")
          [key, constraints]
        end

        attributes = { dependencies: deps }
        attrs.scan(/(\w+):((?:[^,]+|,(?!\w+:))*)/) do |key, value|
          attributes[key.to_sym] = value
        end

        deps.each do |name, _|
          dependency_names << name
        end

        info[version] = attributes
      end

      @monitor.synchronize do
        @gem_info[gem_name] = info
        @refresh_cond.broadcast
      end
    end
  end

  private

  def pinboard
    @pinboard || @monitor.synchronize do
      @pinboard ||=
        begin
          FileUtils.mkdir_p(pinboard_dir)
          Paperback::Pinboard.new(pinboard_dir, monitor: @monitor, httpool: @httpool, work_pool: @work_pool)
        end
    end
  end

  def pinboard_dir
    File.expand_path("~/.cache/paperback/index/#{@uri_identifier}")
  end

  def uri(*parts)
    URI(File.join(@uri.to_s, *parts))
  end
end
