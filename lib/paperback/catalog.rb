require "net/http"
require "tempfile"

class Paperback::Catalog
  def initialize(uri)
    @uri = uri
  end

  def download_gem(name, version)
    response = http_get("/gems/#{name}-#{version}.gem")
    f = Tempfile.new("gem", encoding: "ascii-8bit")
    f.write(response.body)
    f.rewind
    f
  end

  def to_s
    uri.to_s
  end

  private

  def http_get(path)
    original_uri = uri = URI(File.join(@uri.to_s, path))

    5.times do
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        get = Net::HTTP::Get.new(uri)
        response = http.request(get)

        case response
        when Net::HTTPRedirection
          uri = URI(response["Location"])
          next
        else
          response.value
          return response
        end
      end
    end

    raise "Too many redirects for #{original_uri}"
  end
end
