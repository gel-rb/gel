# frozen_string_literal: true

require "zlib"

require_relative "../set"
require_relative "../support/cgi_escape"

require_relative "common"
require_relative "marshal_hacks"

class Gel::Catalog::DependencyIndex
  include Gel::Catalog::Common
  include Gel::Support::CGIEscape

  CACHE_TYPE = "quick"

  LIST_MAX = 40

  def initialize(catalog, *args, **kwargs)
    super(*args, **kwargs)

    @catalog = catalog

    @active_gems = Gel::Set.new
    @pending_gems = Gel::Set.new
  end

  def prepare(gems)
    @monitor.synchronize do
      @pending_gems.merge(gems)
    end
    force_refresh_including(gems.first)
    @monitor.synchronize do
      @refresh_cond.wait_until { gems.all? { |g| _info(g) } }
    end
  end

  def force_refresh_including(gem_name)
    gems_to_refresh = []

    @monitor.synchronize do
      return if _info(gem_name) || @active_gems.include?(gem_name)

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
    gem_list = gems.map { |g| cgi_escape(g) }.sort.join(",")
    @work_pool.queue(gem_list) do
      response =
        begin
          @catalog.send(:http_get, "api/v1/dependencies?gems=#{gem_list}")
        rescue Exception => ex
          @monitor.synchronize do
            @error = ex
            @refresh_cond.broadcast
          end
          next
        end

      new_info = {}
      gems.each { |g| new_info[g] = {} }

      new_dependencies = Gel::Set.new

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
        latest = versions.keys.max_by { |v| Gel::Support::GemVersion.new(v) }
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

  def refresh_gem(gem_name, immediate = false)
    @monitor.synchronize do
      @pending_gems << gem_name unless _info(gem_name) || @active_gems.include?(gem_name)
    end

    force_refresh_including gem_name if immediate
  end
end
