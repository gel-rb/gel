# frozen_string_literal: true

require "set"
require "zlib"

require_relative "../pinboard"

require_relative "common"
require_relative "marshal_hacks"

class Gel::Catalog::LegacyIndex
  include Gel::Catalog::Common
  CACHE_TYPE = "quick"

  def initialize(*)
    super

    @needs_update = true
    @updating = false
    @active_gems = Set.new
    @pending_gems = Set.new

    @gem_versions = {}
  end

  def prepare(gems)
    @monitor.synchronize do
      @pending_gems.merge(gems)
    end
    update
    @monitor.synchronize do
      @refresh_cond.wait_until { gems.all? { |g| _info(g) } }
    end
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

    spec_file_handler = lambda do |for_prerelease|
      lambda do |f|
        data = Zlib::GzipReader.new(f).read
        data = Marshal.load(data)

        data.each do |name, version, platform|
          v = version.to_s
          v += "-#{platform}" unless platform == "ruby"
          (versions[name] ||= {})[v] = nil
        end

        done = false
        @monitor.synchronize do
          if for_prerelease
            prerelease_specs = true
          else
            specs = true
          end

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
    end

    pinboard.async_file(uri("specs.4.8.gz"), tail: false, error: error, &spec_file_handler.call(false))
    pinboard.async_file(uri("prerelease_specs.4.8.gz"), tail: false, error: error, &spec_file_handler.call(true))

    true
  end

  def refresh_gem(gem_name, immediate = true)
    update

    versions = nil
    @monitor.synchronize do
      if @updating
        @pending_gems << gem_name
        return
      end

      unless (info = @gem_info[gem_name])
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
          loaded_data[v] = {dependencies: spec.dependencies, ruby: spec.required_ruby_version}
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
    if (i = super)
      if i.values.all? { |v| v.is_a?(Hash) }
        i
      elsif (e = i.values.grep(Exception).first)
        raise e
      end
    end
  end
end
