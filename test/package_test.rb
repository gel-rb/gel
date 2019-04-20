# frozen_string_literal: true

require "test_helper"

require "gel/package/inspector"

class PackageTest < Minitest::Test
  def test_parse_specification
    result = Gel::Package::Inspector.new
    Gel::Package.extract(fixture_file("rack-2.0.3.gem"), result)

    assert_equal "rack", result.spec.name
    assert_equal "2.0.3", result.spec.version.to_s
  end

  def test_parse_files
    files_seen = []

    result = Gel::Package::Inspector.new { |filename, io|
      files_seen << filename
    }

    Gel::Package.extract(fixture_file("rack-2.0.3.gem"), result)

    assert_includes files_seen, "SPEC"
  end

  def test_parse_file_content
    spec_body = nil

    result = Gel::Package::Inspector.new { |filename, io|
      spec_body = io.read if filename == "SPEC"
    }

    Gel::Package.extract(fixture_file("rack-2.0.3.gem"), result)

    assert_includes spec_body, "Some parts of this specification are adopted from PEP333"
  end
end
