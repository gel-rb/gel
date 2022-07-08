# frozen_string_literal: true

require "uri"

require_relative "httpool"
require_relative "util"
require_relative "support/gem_platform"
require_relative "vendor/ruby_digest"

class Gel::Catalog
  UPDATE_CONCURRENCY = 8

  autoload :Common, File.expand_path("catalog/common", __dir__)
  autoload :CompactIndex, File.expand_path("catalog/compact_index", __dir__)
  autoload :DependencyIndex, File.expand_path("catalog/dependency_index", __dir__)
  autoload :LegacyIndex, File.expand_path("catalog/legacy_index", __dir__)

  def initialize(uri, httpool: Gel::Httpool.new, work_pool:, cache: Gel::Config.cache_dir, initial_gems: [])
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

  def attempting_each_index
    yield send(@indexes.first)
  rescue => ex
    if recoverable?(ex) && @indexes.size > 1
      @indexes.shift
      retry
    else
      raise
    end
  end

  def recoverable?(exception)
    defined?(Net::HTTPExceptions) && Net::HTTPExceptions === exception
  end

  def prepare
    attempting_each_index { |index| index.prepare(@initial_gems) }
  end

  def gem_info(name)
    attempting_each_index { |index| index.gem_info(name) }
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

  def download_gem(name, version)
    path = cache_path(name, version)
    return path if File.exist?(path)

    if gem_info(name)
      response = http_get("/gems/#{name}-#{version}.gem")
      Gel::Util.mkdir_p(cache_dir)
      File.open(path, "wb") do |f|
        f.write(response.body)
      end
      path
    end
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
    @uri.host + "-" + Gel::Vendor::RubyDigest::SHA256.hexdigest(@uri.to_s)[0..10]
  end

  def cache_dir
    File.expand_path("#{@cache}/gems/#{uri_identifier}")
  end

  def cache_path(name, version)
    File.join(cache_dir, "#{name}-#{version}.gem")
  end

  def http_get(path)
    require "net/http"

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
