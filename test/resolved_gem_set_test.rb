# frozen_string_literal: true

require "test_helper"

require "tempfile"
require "gel/resolved_gem_set"

class ResolvedGemSetTest < Minitest::Test
  EXAMPLE = <<LOCKFILE
GEM
  remote: https://rubygems.org/
  specs:
    gel (0.3.0)

PLATFORMS
  ruby

DEPENDENCIES
  gel

RUBY VERSION
   ruby 2.4.0p0

BUNDLED WITH
   1.17.3
LOCKFILE

  def test_load
    lockfile = Tempfile.new
    lockfile.write(EXAMPLE)
    lockfile.close

    result = Gel::ResolvedGemSet.load(lockfile.path)

    assert_equal 1, result.gems.count
    assert_equal ["ruby"], result.platforms
    assert_equal ["gel"], result.dependencies
    assert_equal "ruby 2.4.0p0", result.ruby_version
    assert_equal "1.17.3", result.bundler_version

    # Call it first, because Gel::Catalog might not be defined yet
    first_catalog = result.server_catalogs.first
    assert_kind_of Gel::Catalog, first_catalog
  end
end
