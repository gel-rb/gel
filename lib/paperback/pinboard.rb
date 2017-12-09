# For each URI, this stores:
#   * the local filename
#   * the current etag
#   * an external freshness token
#   * a stale flag
class Paperback::Pinboard
  attr_reader :root
  def initialize(root, httpool: Paperback::Httpool.new)
    @root = root
    @httpool = httpool

    @pstore = PStore.new("#{root}/.pstore")
  end

  def file(uri, token: nil, tail: true, &block)
    unless @pstore.transaction(true) { @pstore[uri.to_s] }
      add uri, token: token
    end

    tail_file = Paperback::TailFile.new(uri, self, httpool: @httpool)
    tail_file.update(!tail) if stale(uri, token)

    File.open(filename(uri), "r", &block)
  end

  def add(uri, token: nil)
    filename = mangle_uri(uri)

    @pstore.transaction(false) do
      @pstore[uri.to_s] = {
        filename: filename,
        etag: nil,
        token: token,
        stale: true,
      }
    end
  end

  def filename(uri)
    File.expand_path(read(uri)[:filename], @root)
  end

  def etag(uri)
    read(uri)[:etag]
  end

  def stale(uri, token)
    @pstore.transaction(false) do
      h = @pstore[uri.to_s]
      return h[:stale] if token && h[:token] == token
      h = h.merge(token: token, stale: true)
      @pstore[uri.to_s] = h
    end

    true
  end

  def read(uri)
    @pstore.transaction(true) do
      @pstore[uri.to_s]
    end
  end

  def updated(uri, etag)
    @pstore.transaction(false) do
      @pstore[uri.to_s] = @pstore[uri.to_s].merge(etag: etag, stale: false)
    end
  end

  private

  def mangle_uri(uri)
    "#{uri.hostname}--#{uri.path.gsub(/[^A-Za-z0-9]+/, "-")}--#{Digest(:SHA256).hexdigest(uri.to_s)[0, 12]}"
  end
end
