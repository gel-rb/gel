# frozen_string_literal: true

require "sdbm"
require "monitor"

require_relative "httpool"
require_relative "tail_file"
require_relative "work_pool"

# For each URI, this stores:
#   * the current etag
#   * an external freshness token
#   * a stale flag
class Paperback::Pinboard
  UPDATE_CONCURRENCY = 8

  attr_reader :root
  def initialize(root, monitor: Monitor.new, httpool: Paperback::Httpool.new, work_pool: nil)
    @root = root
    @monitor = monitor
    @httpool = httpool

    @db = SDBM.new("#{root}/pins")
    @files = {}
    @waiting = Hash.new { |h, k| h[k] = [] }

    @update_pool = work_pool || Paperback::WorkPool.new(UPDATE_CONCURRENCY, monitor: @monitor, name: "paperback-pinboard")
  end

  def file(uri, token: nil, tail: true)
    add uri, token: token

    tail_file = Paperback::TailFile.new(uri, self, httpool: @httpool)
    tail_file.update(!tail) if stale(uri, token)

    if block_given?
      File.open(filename(uri), "r") do |f|
        yield f
      end
    end
  end

  def async_file(uri, token: nil, tail: true, only_updated: false)
    if stale(uri, token)
      add uri, token: token

      already_queued = @files.key?(uri)
      tail_file = @files[uri] ||= Paperback::TailFile.new(uri, self, httpool: @httpool)

      unless already_queued
        @update_pool.queue(uri.path) do
          tail_file.update(!tail)
        end
        @update_pool.start
      end

      block = Proc.new
      @waiting[uri] << lambda do |f, changed|
        block.call(f) if changed || !only_updated
      end
    elsif block_given? && !only_updated
      File.open(filename(uri), "r") do |f|
        yield f
      end
    end
  end

  def add(uri, token: nil)
    @db[uri.to_s] ||= Marshal.dump(
      etag: nil,
      token: token,
      stale: true,
    )
  end

  def filename(uri)
    File.expand_path(mangle_uri(uri), @root)
  end

  def etag(uri)
    read(uri)[:etag]
  end

  def stale(uri, token)
    if h = read(uri)
      if token && h[:token] == token || token == false
        return h[:stale]
      end

      @db[uri.to_s] = Marshal.dump(h.merge(token: token, stale: true))
    end

    true
  end

  def read(uri)
    if v = @db[uri.to_s]
      Marshal.load(v)
    end
  end

  def updated(uri, etag, changed = true)
    @db[uri.to_s] = Marshal.dump(read(uri).merge(etag: etag, stale: false))

    return if @waiting[uri].empty?
    File.open(filename(uri), "r") do |f|
      @waiting[uri].each do |block|
        f.rewind
        block.call(f, changed)
      end
    end
  end

  private

  def mangle_uri(uri)
    "#{uri.hostname}--#{uri.path.gsub(/[^A-Za-z0-9]+/, "-")}--#{Digest(:SHA256).hexdigest(uri.to_s)[0, 12]}"
  end
end
