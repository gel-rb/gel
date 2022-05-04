# frozen_string_literal: true

require "fileutils"
require "net/http"
require "uri"

require_relative "httpool"
require_relative "support/gem_platform"

class Gel::Catalog
  UPDATE_CONCURRENCY = 8

  def initialize(uri, httpool: Gel::Httpool.new, work_pool:, cache: ENV["GEL_CACHE"] || "~/.cache/gel", initial_gems: [])
    @uri = normalize_uri(uri)
    @httpool = httpool
    @work_pool = work_pool
    @cache = cache
    @initial_gems = initial_gems

    @indexes = [
      :compact_index,
      :dependency_index,
      :legacy_index,
    ]
  end

  def prepare
    index.prepare(@initial_gems)
  rescue Net::HTTPExceptions
    if @indexes.size > 1
      @indexes.shift
      retry
    else
      raise
    end
  end

  def compact_index
    @compact_index ||= Gel::Catalog::CompactIndex.new(@uri, uri_identifier, httpool: @httpool, work_pool: @work_pool, cache: @cache)
  end

  def dependency_index
    @dependency_index ||= Gel::Catalog::DependencyIndex.new(self, @uri, uri_identifier, httpool: @httpool, work_pool: @work_pool, cache: @cache)
  end

  def legacy_index
    @legacy_index ||= Gel::Catalog::LegacyIndex.new(@uri, uri_identifier, httpool: @httpool, work_pool: @work_pool, cache: @cache)
  end

  def index
    send(@indexes.first)
  end

  def gem_info(name)
    index.gem_info(name)
  rescue Net::HTTPExceptions
    if @indexes.size > 1
      @indexes.shift
      retry
    else
      raise
    end
  end

  def cached_gem(name, version)
    path = cache_path(name, version)
    return path if File.exist?(path)
  end

  def download_gem(name, version)
    path = cache_path(name, version)
    return path if File.exist?(path)

    name, version = guess_version(name, version)

    response = http_get("/gems/#{name}-#{version}.gem")
    FileUtils.mkdir_p(cache_dir) unless Dir.exist?(cache_dir)
    File.open(path, "wb") do |f|
      f.write(response.body)
    end
    path
  end

  VARIANT_GEMS = %w(libv8)
  def guess_version(name, version)
    if VARIANT_GEMS.include?(name)
      [name, "#{version}-#{platform_specific_version}"]
    else
      [name, version]
    end
  end

  def platform_specific_version
    Gel::Support::GemPlatform.new(RbConfig::CONFIG["arch"])
  end

  def inspect
    "#<#{self.class} #{to_s.inspect}>"
  end

  def to_s
    @uri.to_s
  end

  private

  def normalize_uri(uri)
    uri = URI(uri).dup
    uri.scheme = uri.scheme.downcase
    uri.host = uri.host.downcase
    if auth = Gel::Environment.config[uri.host]
      uri.userinfo = auth
    end
    uri.path = "/" if uri.path == ""
    uri
  end

  def uri_identifier
    require "digest"
    @uri.host + "-" + Digest(:SHA256).hexdigest(@uri.to_s)[0..10]
  end

  def cache_dir
    File.expand_path("#{@cache}/gems/#{uri_identifier}")
  end

  def cache_path(name, version)
    File.join(cache_dir, "#{name}-#{version}.gem")
  end

  def http_get(path)
    original_uri = uri = URI(File.join(@uri.to_s, path))

    5.times do
      response = @httpool.request(uri)

      case response
      when Net::HTTPRedirection
        uri = URI(response["Location"])
        next
      else
        response.value
        return response
      end
    end

    raise Gel::Error::TooManyRedirectsError.new(original_uri: original_uri)
  end
end

require_relative "catalog/compact_index"
require_relative "catalog/dependency_index"
require_relative "catalog/legacy_index"
