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
      filename: "example.org---content--ee76ec642069",
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
      filename: "example.org---content--ee76ec642069",
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
      filename: "example.org---content--ee76ec642069",
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
      filename: "example.org---content--ee76ec642069",
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
      filename: "example.org---content--ee76ec642069",
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
      filename: "example.org---content--ee76ec642069",
      etag: "\"reset\"",
      token: nil,
      stale: false,
    }, @pinboard.read(@uri))
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
      filename: "example.org---content--ee76ec642069",
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
      filename: "example.org---content--ee76ec642069",
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
      filename: "example.org---content--ee76ec642069",
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
      filename: "example.org---content--ee76ec642069",
      etag: "\"reset\"",
      token: nil,
      stale: false,
    }, @pinboard.read(@uri))
  end
end
