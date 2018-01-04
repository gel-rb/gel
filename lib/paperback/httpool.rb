# frozen_string_literal: true

require "monitor"
require "net/http"

class Paperback::Httpool
  include MonitorMixin

  def initialize
    super()

    @pool = {}

    if block_given?
      begin
        yield
      ensure
        close
      end
    end
  end

  def request(uri, request = Net::HTTP::Get.new(uri))
    ident = ident_for(uri)
    http = synchronize do
      (@pool[ident] ||= []).pop
    end

    actual_host = uri.host
    # https://github.com/rubygems/rubygems.org/issues/1698#issuecomment-348744676  ¯\_(ツ)_/¯
    actual_host = "index.rubygems.org" if actual_host.downcase == "rubygems.org"

    t = Time.now
    http ||= Net::HTTP.start(actual_host, uri.port, use_ssl: uri.scheme == "https")
    $stderr.puts "GET #{uri}" if $DEBUG

    if uri.user
      request.basic_auth(uri.user, uri.password || "")
    end

    response = http.request(request)
    $stderr.puts "HTTP #{response.code} (#{response.message}) #{uri} [#{Time.now - t}s]" if $DEBUG
    response

  ensure
    if http
      synchronize do
        if @pool
          @pool[ident].push http
          http = nil
        end
      end
    end

    if http
      http.finish
    end
  end

  def close
    synchronize do
      @pool.values.flatten.each(&:finish)
      @pool = nil
    end
  end

  private

  def ident_for(uri)
    "#{uri.scheme}://#{uri.host}:#{uri.port}"
  end
end
