# frozen_string_literal: true

require "test_helper"

require "gel/tail_file"
require "gel/pinboard"

class TailFileTest < Minitest::Test
  # Long enough to exceed PARTIAL_MINIMUM
  INITIAL_CONTENT = "abcdefghij" * 10_000

  def setup
    super

    @pin_root = Dir.mktmpdir("pins")
    @pinboard = Gel::Pinboard.new(@pin_root)
    @uri = URI("https://example.org/content")

    @stubbed_requests = []
  end

  def stubbed_request
    @stubbed_requests << yield
  end

  def teardown
    @pinboard.instance_variable_get(:@work_pool).stop
    reset_webmock

    super
  end

  def reset_webmock
    @stubbed_requests.each { |stub| assert_requested(stub) }
    @stubbed_requests.clear
    WebMock.reset!
  end

  def test_new_uri
    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: INITIAL_CONTENT,
          headers: { "ETag" => "\"initial\"" },
        )
    }

    @pinboard.file(@uri) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 100_000, f.size
      assert_equal INITIAL_CONTENT, f.read
    end

    assert_equal({
      etag: "\"initial\"",
      token: nil,
      stale: false,
    }, @pinboard.read(@uri))
  end

  def test_unchanged_uri
    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: INITIAL_CONTENT,
          headers: { "ETag" => "\"initial\"" },
        )
    }

    @pinboard.file(@uri) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 100_000, f.size
      assert_equal INITIAL_CONTENT, f.read
    end

    reset_webmock

    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "If-None-Match" => "\"initial\"",
                        "Accept-Encoding" => "identity",
                        "Range" => "bytes=99900-" }).
        to_return(
          status: 304,
          headers: { "ETag" => "\"initial\"" },
        )
    }

    @pinboard.file(@uri) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 100_000, f.size
      assert_equal INITIAL_CONTENT, f.read
    end

    assert_equal({
      etag: "\"initial\"",
      token: nil,
      stale: false,
    }, @pinboard.read(@uri))
  end

  def test_appended_uri
    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: INITIAL_CONTENT,
          headers: { "ETag" => "\"initial\"" },
        )
    }

    @pinboard.file(@uri) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 100_000, f.size
      assert_equal INITIAL_CONTENT, f.read
    end

    reset_webmock

    new_content = INITIAL_CONTENT + INITIAL_CONTENT.tr("a-z", "n-za-m")

    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "If-None-Match" => "\"initial\"",
                        "Accept-Encoding" => "identity",
                        "Range" => "bytes=99900-" }).
        to_return(
          status: 206,
          body: new_content[99900..199999],
          headers: { "Content-Range" => "bytes 99900-199999/200000",
                     "ETag": "\"appended\"" },
        )
    }

    @pinboard.file(@uri) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 200_000, f.size
      assert_equal new_content, f.read
    end

    assert_equal({
      etag: "\"appended\"",
      token: nil,
      stale: false,
    }, @pinboard.read(@uri))
  end

  # Caching effects can make the server travel backwards in time,
  # claiming to have less content than we do
  def test_truncated_uri
    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: INITIAL_CONTENT,
          headers: { "ETag" => "\"initial\"" },
        )
    }

    @pinboard.file(@uri) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 100_000, f.size
      assert_equal INITIAL_CONTENT, f.read
    end

    reset_webmock

    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "If-None-Match" => "\"initial\"",
                        "Accept-Encoding" => "identity",
                        "Range" => "bytes=99900-" }).
        to_return(
          status: 416,
          headers: { "Content-Range" => "bytes */99000" },
        )
    }

    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "If-None-Match" => "\"initial\"",
                        "Accept-Encoding" => "identity",
                        "Range" => "bytes=98900-" }).
        to_return(
          status: 206,
          body: INITIAL_CONTENT[98900..98999],
          headers: { "Content-Range" => "bytes 98900-98999/99000",
                     "ETag": "\"truncated\"" },
        )
    }

    @pinboard.file(@uri) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 100_000, f.size
      assert_equal INITIAL_CONTENT, f.read
    end

    assert_equal({
      etag: "\"initial\"",
      token: nil,
      stale: false,
    }, @pinboard.read(@uri))
  end

  def test_longer_reset_uri
    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: INITIAL_CONTENT,
          headers: { "ETag" => "\"initial\"" },
        )
    }

    @pinboard.file(@uri) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 100_000, f.size
      assert_equal INITIAL_CONTENT, f.read
    end

    reset_webmock

    new_content = INITIAL_CONTENT.tr("a-z", "n-za-m") * 2

    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "If-None-Match" => "\"initial\"",
                        "Accept-Encoding" => "identity",
                        "Range" => "bytes=99900-" }).
        to_return(
          status: 206,
          body: new_content[99900..199999],
          headers: { "Content-Range" => "bytes 99900-199999/200000",
                     "ETag": "\"reset\"" },
        )
    }

    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          status: 200,
          body: new_content,
          headers: { "ETag": "\"reset\"" },
        )
    }

    @pinboard.file(@uri) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 200_000, f.size
      assert_equal new_content, f.read
    end

    assert_equal({
      etag: "\"reset\"",
      token: nil,
      stale: false,
    }, @pinboard.read(@uri))
  end

  def test_shorter_reset_uri
    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: INITIAL_CONTENT,
          headers: { "ETag" => "\"initial\"" },
        )
    }

    @pinboard.file(@uri) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 100_000, f.size
      assert_equal INITIAL_CONTENT, f.read
    end

    reset_webmock

    new_content = INITIAL_CONTENT[0..79999].tr("a-z", "n-za-m")

    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "If-None-Match" => "\"initial\"",
                        "Accept-Encoding" => "identity",
                        "Range" => "bytes=99900-" }).
        to_return(
          status: 416,
          headers: { "Content-Range" => "bytes */80000" },
        )
    }

    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "If-None-Match" => "\"initial\"",
                        "Accept-Encoding" => "identity",
                        "Range" => "bytes=79900-" }).
        to_return(
          status: 206,
          body: new_content[79900..79999],
          headers: { "Content-Range" => "bytes 79900-79999/80000",
                     "ETag": "\"reset\"" },
        )
    }

    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          status: 200,
          body: new_content,
          headers: { "ETag": "\"reset\"" },
        )
    }

    @pinboard.file(@uri) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 80_000, f.size
      assert_equal new_content, f.read
    end

    assert_equal({
      etag: "\"reset\"",
      token: nil,
      stale: false,
    }, @pinboard.read(@uri))
  end

  class Barrier
    def initialize(counter)
      @counter = counter
      @seen = []
      @monitor = Monitor.new
      @cond = @monitor.new_cond
    end

    def meet(source = nil)
      @monitor.synchronize do
        release(source)
        wait
      end
    end

    def wait
      @monitor.synchronize do
        t = Time.now + 10
        while @counter > 0
          raise "Timed out waiting for barrier: seen #{@seen.inspect}; expected #{@counter} more" if Time.now >= t
          @cond.wait(t - Time.now)
        end
      end
    end

    def release(source = nil)
      @monitor.synchronize do
        @counter -= 1
        @seen << source
        @cond.broadcast
      end
    end
  end

  def test_async_requests_occur_simultaneously
    lock = Mutex.new

    requested_files = []
    received_files = []

    barrier = Barrier.new(3)

    stubbed_request {
      stub_request(:get, "https://example.org/x/a").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: proc { lock.synchronize { requested_files << "a" }; barrier.meet(:A); "A" },
        )
    }

    stubbed_request {
      stub_request(:get, "https://example.org/x/b").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: proc { lock.synchronize { requested_files << "b" }; barrier.meet(:B); "B" },
        )
    }

    stubbed_request {
      stub_request(:get, "https://example.org/x/c").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: proc { lock.synchronize { requested_files << "c" }; barrier.meet(:C); "C" },
        )
    }

    @pinboard.async_file(URI("https://example.org/x/a")) do |f|
      lock.synchronize { received_files << "a1#{f.read}" }
    end

    @pinboard.async_file(URI("https://example.org/x/a")) do |f|
      lock.synchronize { received_files << "a2#{f.read}" }
    end

    @pinboard.async_file(URI("https://example.org/x/b")) do |f|
      lock.synchronize { received_files << "b1#{f.read}" }
    end

    @pinboard.async_file(URI("https://example.org/x/b")) do |f|
      lock.synchronize { received_files << "b2#{f.read}" }
    end

    @pinboard.async_file(URI("https://example.org/x/c")) do |f|
      lock.synchronize { received_files << "c1#{f.read}" }
    end

    @pinboard.async_file(URI("https://example.org/x/c")) do |f|
      lock.synchronize { received_files << "c2#{f.read}" }
    end

    @pinboard.instance_variable_get(:@work_pool).join

    lock.synchronize do
      # We got back all the responses we expected
      assert_equal %w(a1A a2A b1B b2B c1C c2C), received_files.sort

      # .. and only made the requests we expected
      assert_equal %w(a b c), requested_files.sort
    end

    # The real assertion of this test is hidden: the requests occurred
    # in parallel because otherwise the barrier wouldn't've released.
  end

  def test_interleaved_async_requests
    lock = Mutex.new

    requested_files = []
    received_files = []

    first = Barrier.new(2)
    second = Barrier.new(2)

    stubbed_request {
      stub_request(:get, "https://example.org/y/a").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: proc { lock.synchronize { requested_files << "a" }; first.wait; "A" },
        )
    }

    stubbed_request {
      stub_request(:get, "https://example.org/y/b").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: proc { lock.synchronize { requested_files << "b" }; "B" },
        )
    }

    stubbed_request {
      stub_request(:get, "https://example.org/y/c").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: proc { lock.synchronize { requested_files << "c" }; second.wait; "C" },
        )
    }

    @pinboard.async_file(URI("https://example.org/y/a")) do |f|
      lock.synchronize do
        received_files << "a1"
        second.release :a1
      end
    end

    @pinboard.async_file(URI("https://example.org/y/a")) do |f|
      lock.synchronize do
        received_files << "a2"
        second.release :a2
      end
    end

    @pinboard.async_file(URI("https://example.org/y/b")) do |f|
      lock.synchronize do
        received_files << "b1"
        first.release :b1
      end
    end

    @pinboard.async_file(URI("https://example.org/y/b")) do |f|
      lock.synchronize do
        received_files << "b2"
        first.release :b2
      end
    end

    @pinboard.async_file(URI("https://example.org/y/c")) do |f|
      lock.synchronize do
        received_files << "c1"
      end
    end

    @pinboard.async_file(URI("https://example.org/y/c")) do |f|
      lock.synchronize do
        received_files << "c2"
      end
    end

    @pinboard.instance_variable_get(:@work_pool).join

    lock.synchronize do
      # The "server" only responds after we've received the earlier
      # responses, so responses arrive in a fixed order based on the
      # order dictated by the server logic (b then a then c). There's no
      # guarantee that our identical requests' blocks will be invoked in
      # a particular order, though, so we do have to account for that.
      #
      # This order check is important because it shows we're receiving
      # and handling the responses in the order the server provides
      # them, not queueing them all together.
      assert_equal %w(b b a a c c), received_files.map { |x| x[0] }

      # Each block got invoked exactly once
      assert_equal %w(a1 a2 b1 b2 c1 c2), received_files.sort

      # The order the server first saw the requests is still arbitrary --
      # but it only gets one each
      assert_equal %w(a b c), requested_files.sort
    end

    already_received = received_files.dup

    @pinboard.async_file(URI("https://example.org/y/a")) do |f|
      lock.synchronize do
        received_files << "a3"
      end
    end

    @pinboard.async_file(URI("https://example.org/y/b")) do |f|
      lock.synchronize do
        received_files << "b3"
      end
    end

    @pinboard.async_file(URI("https://example.org/y/c")) do |f|
      lock.synchronize do
        received_files << "c3"
      end
    end

    @pinboard.instance_variable_get(:@work_pool).join

    lock.synchronize do
      # The extra requests are served by the already-loaded files, so the
      # "3" blocks are called, but no more requests occur.
      assert_equal already_received + %w(a3 b3 c3), received_files
      assert_equal %w(a b c), requested_files.sort
    end
  end
end

class NoPartialTailFileTest < Minitest::Test
  # Long enough to exceed PARTIAL_MINIMUM
  INITIAL_CONTENT = "abcdefghij" * 10_000

  def setup
    super

    @pin_root = Dir.mktmpdir("pins")
    @pinboard = Gel::Pinboard.new(@pin_root)
    @uri = URI("https://example.org/content")

    @stubbed_requests = []
  end

  def stubbed_request
    @stubbed_requests << yield
  end

  def teardown
    @pinboard.instance_variable_get(:@work_pool).stop
    reset_webmock

    super
  end

  def reset_webmock
    @stubbed_requests.each { |stub| assert_requested(stub) }
    @stubbed_requests.clear
    WebMock.reset!
  end

  def test_new_uri
    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: INITIAL_CONTENT,
          headers: { "ETag" => "\"initial\"" },
        )
    }

    @pinboard.file(@uri, tail: false) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 100_000, f.size
      assert_equal INITIAL_CONTENT, f.read
    end

    assert_equal({
      etag: "\"initial\"",
      token: nil,
      stale: false,
    }, @pinboard.read(@uri))
  end

  def test_unchanged_uri
    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: INITIAL_CONTENT,
          headers: { "ETag" => "\"initial\"" },
        )
    }

    @pinboard.file(@uri, tail: false) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 100_000, f.size
      assert_equal INITIAL_CONTENT, f.read
    end

    reset_webmock

    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "Accept-Encoding" => /gzip/,
                        "If-None-Match" => "\"initial\"" }).
        to_return(
          status: 304,
          headers: { "ETag" => "\"initial\"" },
        )
    }

    @pinboard.file(@uri, tail: false) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 100_000, f.size
      assert_equal INITIAL_CONTENT, f.read
    end

    assert_equal({
      etag: "\"initial\"",
      token: nil,
      stale: false,
    }, @pinboard.read(@uri))
  end

  def test_appended_uri
    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: INITIAL_CONTENT,
          headers: { "ETag" => "\"initial\"" },
        )
    }

    @pinboard.file(@uri, tail: false) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 100_000, f.size
      assert_equal INITIAL_CONTENT, f.read
    end

    reset_webmock

    new_content = INITIAL_CONTENT + INITIAL_CONTENT.tr("a-z", "n-za-m")

    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "Accept-Encoding" => /gzip/,
                        "If-None-Match" => "\"initial\"" }).
        to_return(
          status: 200,
          body: new_content,
          headers: { "ETag": "\"appended\"" },
        )
    }

    @pinboard.file(@uri, tail: false) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 200_000, f.size
      assert_equal new_content, f.read
    end

    assert_equal({
      etag: "\"appended\"",
      token: nil,
      stale: false,
    }, @pinboard.read(@uri))
  end

  def test_reset_uri
    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: INITIAL_CONTENT,
          headers: { "ETag" => "\"initial\"" },
        )
    }

    @pinboard.file(@uri, tail: false) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 100_000, f.size
      assert_equal INITIAL_CONTENT, f.read
    end

    reset_webmock

    new_content = INITIAL_CONTENT.tr("a-z", "n-za-m") * 2

    stubbed_request {
      stub_request(:get, "https://example.org/content").
        with(headers: { "Accept-Encoding" => /gzip/,
                        "If-None-Match" => "\"initial\"" }).
        to_return(
          status: 200,
          body: new_content,
          headers: { "ETag": "\"reset\"" },
        )
    }

    @pinboard.file(@uri, tail: false) do |f|
      assert_equal "#{@pin_root}/example.org---content--ee76ec642069", f.path
      assert_equal 200_000, f.size
      assert_equal new_content, f.read
    end

    assert_equal({
      etag: "\"reset\"",
      token: nil,
      stale: false,
    }, @pinboard.read(@uri))
  end
end
