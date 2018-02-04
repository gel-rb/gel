# frozen_string_literal: true

require "set"
require "fileutils"
require "monitor"
require "cgi"
require "zlib"

require_relative "../pinboard"

require_relative "marshal_hacks"

class Paperback::Catalog::LegacyIndex
  UPDATE_CONCURRENCY = 8

  def initialize(catalog, uri, uri_identifier, httpool:, work_pool:)
    @catalog = catalog
    @uri = uri
    @uri_identifier = uri_identifier
    @httpool = httpool
    @work_pool = work_pool

    @needs_update = true
    @updating = false
    @active_gems = Set.new
    @pending_gems = Set.new

    @gem_versions = {}

    @monitor = Monitor.new
    @refresh_cond = @monitor.new_cond

    @done_refresh = {}

    @gem_info = {}
    @error = nil

    @work_pool ||= Paperback::WorkPool.new(UPDATE_CONCURRENCY, monitor: @monitor, name: "paperback-catalog")
  end

  def update
    @monitor.synchronize do
      return false unless @needs_update
      @needs_update = false
      @updating = true
    end

    specs = false
    prerelease_specs = false

    versions = {}

    error = lambda do |ex|
      @monitor.synchronize do
        @error = ex
        @updating = false
        @refresh_cond.broadcast
      end
    end

    pinboard.async_file(uri("specs.4.8.gz"), tail: false, error: error) do |f|
      data = Zlib::GzipReader.new(f).read
      data = Marshal.load(data)

      data.each do |name, version, platform|
        v = version.to_s
        v += "-#{platform}" unless platform == "ruby"
        (versions[name] ||= {})[v] = nil
      end

      done = false
      @monitor.synchronize do
        specs = true
        if specs && prerelease_specs
          done = true
          @gem_info.update versions
          @updating = false
          @refresh_cond.broadcast
        end
      end

      if done
        (@active_gems | @pending_gems).each do |name|
          refresh_gem(name)
        end
      end
    end

    pinboard.async_file(uri("prerelease_specs.4.8.gz"), tail: false, error: error) do |f|
      data = Zlib::GzipReader.new(f).read
      data = Marshal.load(data)

      data.each do |name, version, platform|
        v = version.to_s
        v += "-#{platform}" unless platform == "ruby"
        (versions[name] ||= {})[v] = nil
      end

      done = false
      @monitor.synchronize do
        prerelease_specs = true
        if specs && prerelease_specs
          done = true
          @gem_info.update versions
          @updating = false
          @refresh_cond.broadcast
        end
      end

      if done
        (@active_gems | @pending_gems).each do |name|
          refresh_gem(name)
        end
      end
    end

    true
  end

  def gem_info(gem_name)
    gems_to_refresh = []

    @monitor.synchronize do
      if (info = _info(gem_name)) && info.values.all? { |x| x.is_a?(Hash) }
        unless @done_refresh[gem_name]
          gems_to_refresh = info.values.flat_map { |v| v[:dependencies] }.map(&:first).uniq
          @done_refresh[gem_name] = true
        end
        return info
      end
    end

    refresh_gem gem_name

    @monitor.synchronize do
      info = nil
      @refresh_cond.wait_until { (info = _info(gem_name)) && info.values.all? { |x| x.is_a?(Hash) } }
      unless @done_refresh[gem_name]
        gems_to_refresh = info.values.flat_map { |v| v[:dependencies] }.map(&:first).uniq
        @done_refresh[gem_name] = true
      end
      info
    end
  ensure
    gems_to_refresh.each do |dep_name|
      refresh_gem dep_name
    end
  end

  def refresh_gem(gem_name)
    update

    versions = nil
    @monitor.synchronize do
      if @updating
        @pending_gems << gem_name
        return
      end

      unless info = @gem_info[gem_name]
        @gem_info[gem_name] = {}
        @refresh_cond.broadcast
        return
      end

      versions = info.keys.select { |v| info[v].nil? }
      versions.each do |v|
        info[v] = :pending
      end
    end

    loaded_data = {}
    versions.each do |v|
      loaded_data[v] = nil
    end

    versions.each do |v|
      error = lambda do |ex|
        @gem_info[gem_name][v] = ex
        @refresh_cond.broadcast
      end

      pinboard.async_file(uri("quick", "Marshal.4.8", "#{gem_name}-#{v}.gemspec.rz"), token: false, tail: false, error: error) do |f|
        data = Zlib::Inflate.inflate(f.read)
        # TODO: Extract the data we need without a full unmarshal
        spec = Marshal.load(data)

        @monitor.synchronize do
          loaded_data[v] = { dependencies: spec.dependencies, ruby: spec.required_ruby_version }
          if loaded_data.values.all?
            @gem_info[gem_name].update loaded_data
            @refresh_cond.broadcast
          end
        end
      end
    end
  end

  private

  def _info(gem_name)
    raise @error if @error
    if i = @gem_info[gem_name]
      raise i if i.is_a?(Exception)
      if i.values.all? { |v| v.is_a?(Hash) }
        i
      elsif e = i.values.grep(Exception).first
        raise e
      end
    end
  end

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
