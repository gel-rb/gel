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
    http ||= Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https")
    http.request(request)
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
