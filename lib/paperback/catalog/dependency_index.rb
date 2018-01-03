# frozen_string_literal: true

require "set"
require "fileutils"
require "monitor"
require "cgi"
require "zlib"

require_relative "../pinboard"

class Gem::Dependency; end
class Gem::Specification
  attr_accessor :required_ruby_version

  def self._load(str)
    array = Marshal.load(str)
    o = new
    o.required_ruby_version = array[6].to_s.split(/,\s*/)
    o
  end
end

class Paperback::Catalog::DependencyIndex
  LIST_MAX = 40
  UPDATE_CONCURRENCY = 8

  def initialize(catalog, uri, uri_identifier, httpool:, work_pool:)
    @catalog = catalog
    @uri = uri
    @uri_identifier = uri_identifier
    @httpool = httpool
    @work_pool = work_pool

    @active_gems = Set.new
    @pending_gems = Set.new

    @monitor = Monitor.new
    @refresh_cond = @monitor.new_cond

    @done_refresh = {}

    @gem_info = {}

    @work_pool ||= Paperback::WorkPool.new(UPDATE_CONCURRENCY, monitor: @monitor, name: "paperback-catalog")
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
    force_refresh_including gem_name

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

  def force_refresh_including(gem_name)
    gems_to_refresh = []

    @monitor.synchronize do
      return if @gem_info.key?(gem_name) || @active_gems.include?(gem_name)

      gems_to_refresh << gem_name
      @pending_gems.delete gem_name

      while gems_to_refresh.size < LIST_MAX && @pending_gems.size > 0
        a_gem = @pending_gems.first
        @pending_gems.delete a_gem
        gems_to_refresh << a_gem
      end

      @active_gems.merge gems_to_refresh
    end

    refresh_some_gems gems_to_refresh
  end

  def refresh_some_gems(gems)
    gem_list = gems.map { |g| CGI.escape(g) }.join(",")
    @work_pool.queue(gem_list) do
      response = @catalog.send(:http_get, "api/v1/dependencies?gems=#{gem_list}")
      new_info = {}

      new_dependencies = Set.new

      hashes = Marshal.load(response.body)
      hashes.each do |hash|
        v = hash[:number].to_s
        v += "-#{hash[:platform]}" unless hash[:platform] == "ruby"

        (new_info[hash[:name]] ||= {})[v] = {
          dependencies: hash[:dependencies].map { |name, versions| [name, versions.split(/,\s*/)] },
          ruby: lambda do
            # The disadvantage of trying to avoid this per-version
            # request is that when we do discover we need it, we need it
            # immediately. :/
            pinboard.file(uri("quick", "Marshal.4.8", "#{hash[:name]}-#{v}.gemspec.rz"), token: false, tail: false) do |f|
              data = Zlib::Inflate.inflate(f.read)
              # TODO: Extract the data we need without a full unmarshal
              Marshal.load(data).required_ruby_version
            end
          end,
        }
      end

      hashes.group_by { |h| h[:name] }.each do |_, group|
        versions = group.group_by { |h| h[:number] }
        latest = versions.keys.max_by { |v| Paperback::Support::GemVersion.new(v) }
        new_dependencies.merge versions[latest].flat_map { |h| h[:dependencies].map(&:first) }.uniq
      end

      @monitor.synchronize do
        @gem_info.update new_info
        @active_gems.subtract new_info.keys

        @refresh_cond.broadcast

        new_dependencies.subtract @active_gems
        new_dependencies.subtract @gem_info.keys
        @pending_gems.merge new_dependencies
      end
    end

    @work_pool.start
  end

  def refresh_gem(gem_name)
    @monitor.synchronize do
      @pending_gems << gem_name unless @gem_info.key?(gem_name) || @active_gems.include?(gem_name)
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
    File.expand_path("~/.cache/paperback/quick/#{@uri_identifier}")
  end

  def uri(*parts)
    URI(File.join(@uri.to_s, *parts))
  end
end
