# frozen_string_literal: true

require_relative "db"
require_relative "httpool"
require_relative "tail_file"
require_relative "work_pool"

# For each URI, this stores:
#   * the current etag
#   * an external freshness token
#   * a stale flag
class Gel::Pinboard
  UPDATE_CONCURRENCY = 8

  attr_reader :root
  def initialize(root, httpool: Gel::Httpool.new, work_pool: nil)
    @root = root
    @httpool = httpool

    @db = Gel::DB.new(root, "pins")
    @files = {}
    @waiting = Hash.new { |h, k| h[k] = [] }

    @work_pool = work_pool || Gel::WorkPool.new(UPDATE_CONCURRENCY, name: "gel-pinboard")
    @monitor = Monitor.new
  end

  def file(uri, token: nil, tail: true)
    @monitor.synchronize do
      add uri, token: token

      tail_file = Gel::TailFile.new(uri, self, httpool: @httpool)
      tail_file.update(force_reset: !tail) if stale(uri, token)
    end

    if block_given?
      File.open(filename(uri), "r") do |f|
        yield f
      end
    end
  end

  def async_file(uri, token: nil, tail: true, only_updated: false, error: nil)
    file_to_yield = nil

    @monitor.synchronize do
      already_done = @files.key?(uri) && @files[uri].done?

      if !already_done && stale(uri, token)
        add uri, token: token

        already_queued = @files.key?(uri)
        tail_file = @files[uri] ||= Gel::TailFile.new(uri, self, httpool: @httpool)

        unless already_queued
          @work_pool.queue(uri.path) do
            begin
              tail_file.update(force_reset: !tail)
            rescue Exception => ex
              if error
                error.call(ex)
              else
                raise
              end
            end
          end
          @work_pool.start
        end

        @waiting[uri] << lambda do |f, changed|
          yield f if changed || !only_updated
        end
      elsif !only_updated
        file_to_yield = filename(uri)
      end
    end

    if file_to_yield
      File.open(file_to_yield, "r") do |f|
        yield f
      end
    end
  end

  def add(uri, token: nil)
    @db[uri.to_s] ||= {
      etag: nil,
      token: token,
      stale: true,
    }
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

      @db[uri.to_s] = h.merge(token: token, stale: true)
    end

    true
  end

  def read(uri)
    @db[uri.to_s]
  end

  def updated(uri, etag, changed = true)
    blocks = nil
    @monitor.synchronize do
      h = read(uri) || {}
      @db[uri.to_s] = h.merge(etag: etag, stale: false)

      blocks = @waiting.delete(uri)
    end

    return unless blocks && blocks.any?

    File.open(filename(uri), "r") do |f|
      blocks.each do |block|
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
