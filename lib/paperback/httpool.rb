# frozen_string_literal: true

require "monitor"
require "net/http"

class Paperback::Httpool
  include MonitorMixin

  require "logger"
  Logger = ::Logger.new($stderr)
  Logger.level = $DEBUG ? ::Logger::DEBUG : ::Logger::WARN

  def initialize
    super()

    @pool = {}
    @cond = new_cond

    if block_given?
      begin
        yield
      ensure
        close
      end
    end
  end

  def request(uri, request = Net::HTTP::Get.new(uri))
    with_connection(uri) do |http|
      logger.debug { "GET #{uri}" }

      if uri.user
        request.basic_auth(uri.user, uri.password || "")
      end

      t = Time.now
      response = http.request(request)
      logger.debug { "HTTP #{response.code} (#{response.message}) #{uri} [#{Time.now - t}s]" }
      response
    end
  end

  def close
    https = nil

    synchronize do
      https = @pool.values.flatten
      @pool = nil
    end

    https.each(&:finish)
  end

  private

  def ident_for(uri)
    "#{uri.scheme}://#{uri.host}:#{uri.port}"
  end

  def logger
    Logger
  end

  def connect(ident, uri)
    logger.debug { "Connect #{ident}" }
    t = Time.now
    http = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https")
    logger.debug { "  Connected #{ident} [#{Time.now - t}s]" }

    http
  end

  def queue_new_connection(ident, uri)
    Thread.new do
      http = connect(ident, uri)
      checkin ident, http
    end
  end

  def checkin(ident, http)
    synchronize do
      if @pool
        @pool[ident].push http
        http = nil
        @cond.broadcast
      end
    end

    if http
      http.finish
    end
  end

  def checkout(ident, uri)
    synchronize do
      @pool[ident] ||= []

      if @pool[ident].empty?
        queue_new_connection ident, uri
        @cond.wait_while { @pool[ident].empty? }
      end

      @pool[ident].pop
    end
  end

  def with_connection(uri)
    ident = ident_for(uri)
    http = checkout(ident, uri)

    yield http

  ensure
    if http
      checkin ident, http
    end
  end
end
