# frozen_string_literal: true

require "fileutils"
require "net/http"
require "uri"
require "digest"

require_relative "httpool"

class Paperback::Catalog
  def initialize(uri, httpool: Paperback::Httpool.new)
    @uri = URI(uri)
    @httpool = httpool
  end

  def compact_index
    Paperback::Catalog::CompactIndex.new(@uri, uri_identifier, httpool: @httpool)
  end

  def cached_gem(name, version)
    path = cache_path(name, version)
    return path if File.exist?(path)
  end

  def download_gem(name, version)
    path = cache_path(name, version)
    return path if File.exist?(path)

    response = http_get("/gems/#{name}-#{version}.gem")
    FileUtils.mkdir_p(cache_dir)
    File.open(path, "wb") do |f|
      f.write(response.body)
    end
    path
  end

  def to_s
    uri.to_s
  end

  private

  def uri_identifier
    @uri.host + "-" + Digest(:SHA256).hexdigest(@uri.to_s)[0..10]
  end

  def cache_dir
    File.expand_path("~/.cache/paperback/gems/#{uri_identifier}")
  end

  def cache_path(name, version)
    File.join(cache_dir, "#{name}-#{version}.gem")
  end

  def http_get(path)
    original_uri = uri = URI(File.join(@uri.to_s, path))

    5.times do
      get = Net::HTTP::Get.new(uri)
      response = @httpool.request(uri, get)

      case response
      when Net::HTTPRedirection
        uri = URI(response["Location"])
        next
      else
        response.value
        return response
      end
    end

    raise "Too many redirects for #{original_uri}"
  end
end

require_relative "catalog/compact_index"
