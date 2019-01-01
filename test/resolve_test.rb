# frozen_string_literal: true

require "test_helper"

class ResolveTest < Minitest::Test
  def test_trivial_gemfile
    gemfile = <<GEMFILE
source "https://rubygems.org"

gem "rack", "2.0.3"
GEMFILE

    stub_request(:get, "https://index.rubygems.org/versions").
      to_return(body: <<VERSIONS)
created_at: 2017-03-27T04:38:13+00:00
---
rack 2.0.3 xxx
VERSIONS

    stub_request(:get, "https://index.rubygems.org/info/rack").
      to_return(body: <<INFO)
---
2.0.3 |checksum:zzz
INFO

    assert_equal <<LOCKFILE, lockfile_for_gemfile(gemfile)
GEM
  remote: https://rubygems.org/
  specs:
    rack (2.0.3)

PLATFORMS
  ruby

DEPENDENCIES
  rack (2.0.3)

BUNDLED WITH
   1.999
LOCKFILE
  end

  def test_chooses_newest_version
    gemfile = <<GEMFILE
source "https://rubygems.org"

gem "rack"
GEMFILE

    stub_request(:get, "https://index.rubygems.org/versions").
      to_return(body: <<VERSIONS)
created_at: 2017-03-27T04:38:13+00:00
---
rack 0.1.0,2.0.3 xxx
rack 0.1.1 yyy
VERSIONS

    stub_request(:get, "https://index.rubygems.org/info/rack").
      to_return(body: <<INFO)
---
0.1.0 |checksum:zzz
2.0.3 |checksum:zzz
0.1.1 |checksum:zzz
INFO

    assert_equal <<LOCKFILE, lockfile_for_gemfile(gemfile)
GEM
  remote: https://rubygems.org/
  specs:
    rack (2.0.3)

PLATFORMS
  ruby

DEPENDENCIES
  rack

BUNDLED WITH
   1.999
LOCKFILE
  end

  def test_respects_range_specifier
    gemfile = <<GEMFILE
source "https://rubygems.org"

gem "rack", "< 2.0"
GEMFILE

    stub_request(:get, "https://index.rubygems.org/versions").
      to_return(body: <<VERSIONS)
created_at: 2017-03-27T04:38:13+00:00
---
rack 0.1.0,2.0.3 xxx
rack 0.1.1 yyy
VERSIONS

    stub_request(:get, "https://index.rubygems.org/info/rack").
      to_return(body: <<INFO)
---
0.1.0 |checksum:zzz
2.0.3 |checksum:zzz
0.1.1 |checksum:zzz
INFO

    assert_equal <<LOCKFILE, lockfile_for_gemfile(gemfile)
GEM
  remote: https://rubygems.org/
  specs:
    rack (0.1.1)

PLATFORMS
  ruby

DEPENDENCIES
  rack (< 2.0)

BUNDLED WITH
   1.999
LOCKFILE
  end

  def test_dependencies_are_followed_and_recorded
    gemfile = <<GEMFILE
source "https://gem-mimer.org"

gem "activerecord", "~> 4.0"
GEMFILE

    stub_gem_mimer

    assert_equal <<LOCKFILE, lockfile_for_gemfile(gemfile)
GEM
  remote: https://gem-mimer.org/
  specs:
    activemodel (4.2.11)
      activesupport (= 4.2.11)
      builder (~> 3.1)
    activerecord (4.2.11)
      activemodel (= 4.2.11)
      activesupport (= 4.2.11)
      arel (~> 6.0)
    activesupport (4.2.11)
      i18n (~> 0.7)
      minitest (~> 5.1)
      thread_safe (~> 0.3, >= 0.3.4)
      tzinfo (~> 1.1)
    arel (6.0.4)
    builder (3.2.3)
    concurrent-ruby (1.1.4)
    i18n (0.9.5)
      concurrent-ruby (~> 1.0)
    minitest (5.11.3)
    thread_safe (0.3.6)
    tzinfo (1.2.5)
      thread_safe (~> 0.1)

PLATFORMS
  ruby

DEPENDENCIES
  activerecord (~> 4.0)

BUNDLED WITH
   1.999
LOCKFILE
  end

  def test_dependencies_api_fallback
    gemfile = <<GEMFILE
source "https://rubygems.org"

gem "rack"
GEMFILE

    stub_request(:get, "https://index.rubygems.org/versions").
      to_return(status: 404)

    stub_request(:get, "https://index.rubygems.org/api/v1/dependencies?gems=rack").
      to_return(body: Marshal.dump([
        { name: "rack", number: "2.0.6", platform: "ruby", dependencies: [] },
        { name: "rack", number: "2.0.5", platform: "ruby", dependencies: [] },
        { name: "rack", number: "2.0.4", platform: "ruby", dependencies: [] },
        { name: "rack", number: "2.0.3", platform: "ruby", dependencies: [] },
        { name: "rack", number: "2.0.2", platform: "ruby", dependencies: [] },
        { name: "rack", number: "2.0.1", platform: "ruby", dependencies: [] },
        { name: "rack", number: "2.0.0", platform: "ruby", dependencies: [] },
      ]))

    stub_request(:get, "https://index.rubygems.org/quick/Marshal.4.8/rack-2.0.6.gemspec.rz").
      to_return(body: gemspec_rz(name: "rack", version: "2.0.6", dependencies: []))

    assert_equal <<LOCKFILE, lockfile_for_gemfile(gemfile)
GEM
  remote: https://rubygems.org/
  specs:
    rack (2.0.6)

PLATFORMS
  ruby

DEPENDENCIES
  rack

BUNDLED WITH
   1.999
LOCKFILE
  end

  def test_legacy_api_fallback
    gemfile = <<GEMFILE
source "https://rubygems.org"

gem "rack"
GEMFILE

    stub_request(:get, "https://index.rubygems.org/versions").
      to_return(status: 404)

    stub_request(:get, "https://index.rubygems.org/api/v1/dependencies?gems=rack").
      to_return(status: 404)

    stub_request(:get, "https://index.rubygems.org/specs.4.8.gz").
      to_return(body: specs_gz([
        ["rack", "2.0.6", "ruby"],
        ["rack", "2.0.5", "ruby"],
        ["rack", "2.0.4", "ruby"],
      ]))

    stub_request(:get, "https://index.rubygems.org/prerelease_specs.4.8.gz").
      to_return(body: specs_gz([
      ]))

    stub_request(:get, "https://index.rubygems.org/quick/Marshal.4.8/rack-2.0.6.gemspec.rz").
      to_return(body: gemspec_rz(name: "rack", version: "2.0.6", dependencies: []))

    stub_request(:get, "https://index.rubygems.org/quick/Marshal.4.8/rack-2.0.5.gemspec.rz").
      to_return(body: gemspec_rz(name: "rack", version: "2.0.5", dependencies: []))

    stub_request(:get, "https://index.rubygems.org/quick/Marshal.4.8/rack-2.0.4.gemspec.rz").
      to_return(body: gemspec_rz(name: "rack", version: "2.0.4", dependencies: []))

    assert_equal <<LOCKFILE, lockfile_for_gemfile(gemfile)
GEM
  remote: https://rubygems.org/
  specs:
    rack (2.0.6)

PLATFORMS
  ruby

DEPENDENCIES
  rack

BUNDLED WITH
   1.999
LOCKFILE
  end

  def lockfile_for_gemfile(gemfile)
    locked = nil

    Dir.mktmpdir do |cache_dir|
      with_empty_store do |store|
        output = StringIO.new
        locked = Paperback::Environment.lock(
          output: output,
          gemfile: Paperback::GemfileParser.parse(gemfile),
          lockfile: nil,
          catalog_options: { cache: cache_dir },
        )

        assert_match(/\AResolving dependencies\.\.\.+\n\z/, output.string)
      end
    end

    locked
  end

  # Set up stubs for a small but real-world-shaped gem source (which
  # supports compact index).
  #
  # Use this when catalog interaction is incidental (i.e., the test is
  # focused on the resolution process/ result) and you just need the
  # test to exist in a world where some gems exist; use explicit request
  # stubs to test catalog interaction details (exactly which/when paths
  # do/don't get downloaded, fallback between catalog formats, etc).
  def stub_gem_mimer
    require fixture_file("index/info.rb")

    stub_request(:get, "https://gem-mimer.org/versions").
      to_return(body: File.open(fixture_file("index/versions")))

    stub_request(:get, Addressable::Template.new("https://gem-mimer.org/info/{gem}")).
      to_return(body: lambda { |request| FIXTURE_INDEX[File.basename(request.uri)] })
  end

  def gemspec_rz(name:, version:, dependencies: [], ruby: [">=", "0"], platform: "ruby")
    m = lambda { |x| Marshal.dump(x)[2..-1] }

    array = lambda { |parts|
      if parts.size == 0
        "[\x00"
      elsif parts.size < 123
        "[#{(5 + parts.size).chr}" +
          parts.join
      else
        raise
      end
    }

    gem_version = lambda { |v|
      "U:\x11Gem::Version[\x06" +
        m.(v)
    }

    gem_requirement = lambda { |pairs|
      "U:\x15Gem::Requirement[\x06" +
        array.(pairs.map { |op, ver| "[\x07" + m.(op) + gem_version.(ver) })
    }

    gem_dependency = lambda { |type, name, requirement_pairs|
      "o:\x14Gem::Dependency\n" +
        ":\n@name" + m.(name) +
        ":\x11@requirement" + gem_requirement.(requirement_pairs) +
        ":\n@type" + m.(type) +
        ":\x10@prerelease" + "F" +
        ":\x1A@version_requirements" + gem_requirement.(requirement_pairs)
    }

    inner = "\x04\b" + array.([
      m.("0.0.0"), # @rubygems_version
      m.(4), # @specification_version
      m.(name), # @name
      gem_version.(version), # @version
      m.(Time.now.utc), # date
      m.(""), # @summary
      gem_requirement.([ruby]), # @required_ruby_version
      gem_requirement.([[">=", "0"]]), # @required_rubygems_version
      m.(platform), # @original_platform
      array.(dependencies.map { |type, name, reqs| gem_dependency.(type, name, reqs) }), # @dependencies
    ])

    Zlib::Deflate.deflate(
      "\x04\bu:\x17Gem::Specification\x02" +
      [inner.size].pack("S<") +
      inner
    )
  end

  def specs_gz(gems)
    m = lambda { |x| Marshal.dump(x)[2..-1] }

    array = lambda { |parts|
      if parts.size == 0
        "[\x00"
      elsif parts.size < 123
        "[#{(5 + parts.size).chr}" +
          parts.join
      else
        raise
      end
    }

    gem_version = lambda { |v|
      "U:\x11Gem::Version[\x06" +
        m.(v)
    }

    io = StringIO.new

    gz = Zlib::GzipWriter.new(io)
    gz.write(
      "\x04\b" +
      array.(gems.map { |name, version, platform|
        array.([m.(name), gem_version.(version), m.(platform)])
      })
    )
    gz.close

    io.string
  end
end
