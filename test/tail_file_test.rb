# frozen_string_literal: true

require "test_helper"

require "paperback/tail_file"
require "paperback/pinboard"

class TailFileTest < Minitest::Test
  # Long enough to exceed PARTIAL_MINIMUM
  INITIAL_CONTENT = "abcdefghij" * 10_000

  def setup
    @pin_root = Dir.mktmpdir("pins")
    @pinboard = Paperback::Pinboard.new(@pin_root)
    @uri = URI("https://example.org/content")

    @stubbed_requests = []
  end

  def stubbed_request
    @stubbed_requests << yield
  end

  def teardown
    @pinboard.instance_variable_get(:@work_pool).stop
    reset_webmock
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

  def test_interleaved_async_requests
    start_time = Time.now

    requested_files = []

    stubbed_request {
      stub_request(:get, "https://example.org/a").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: proc { requested_files << "a"; sleep 1.0; "A" },
        )
    }

    stubbed_request {
      stub_request(:get, "https://example.org/b").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: proc { requested_files << "b"; sleep 0.5; "B" },
        )
    }

    stubbed_request {
      stub_request(:get, "https://example.org/c").
        with(headers: { "Accept-Encoding" => /gzip/ }).
        to_return(
          body: proc { requested_files << "c"; sleep 1.5; "C" },
        )
    }

    received_files = []

    @pinboard.async_file(URI("https://example.org/a")) do |f|
      received_files << "a1"
    end

    @pinboard.async_file(URI("https://example.org/a")) do |f|
      received_files << "a2"
    end

    @pinboard.async_file(URI("https://example.org/b")) do |f|
      received_files << "b1"
    end

    @pinboard.async_file(URI("https://example.org/b")) do |f|
      received_files << "b2"
    end

    @pinboard.async_file(URI("https://example.org/c")) do |f|
      received_files << "c1"
    end

    @pinboard.async_file(URI("https://example.org/c")) do |f|
      received_files << "c2"
    end

    @pinboard.instance_variable_get(:@work_pool).join

    assert_equal %w(b1 b2 a1 a2 c1 c2), received_files
    assert_equal %w(a b c), requested_files.sort

    # The requests occur in parallel, so they should all finish in
    # slightly longer than the slowest request duration
    assert_operator Time.now - start_time, :<, 1.9

    @pinboard.async_file(URI("https://example.org/a")) do |f|
      received_files << "a3"
    end

    @pinboard.async_file(URI("https://example.org/b")) do |f|
      received_files << "b3"
    end

    @pinboard.async_file(URI("https://example.org/c")) do |f|
      received_files << "c3"
    end

    @pinboard.instance_variable_get(:@work_pool).join

    # The extra requests are served by the already-loaded files, so the
    # "3" blocks are called, but no more requests occur.
    assert_equal %w(b1 b2 a1 a2 c1 c2 a3 b3 c3), received_files
    assert_equal %w(a b c), requested_files.sort
  end
end

class NoPartialTailFileTest < Minitest::Test
  # Long enough to exceed PARTIAL_MINIMUM
  INITIAL_CONTENT = "abcdefghij" * 10_000

  def setup
    @pin_root = Dir.mktmpdir("pins")
    @pinboard = Paperback::Pinboard.new(@pin_root)
    @uri = URI("https://example.org/content")

    @stubbed_requests = []
  end

  def stubbed_request
    @stubbed_requests << yield
  end

  def teardown
    @pinboard.instance_variable_get(:@work_pool).stop
    reset_webmock
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
