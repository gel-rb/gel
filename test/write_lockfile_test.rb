# frozen_string_literal: true

require "test_helper"

class WriteLockfileTest < Minitest::Test
  def test_lockfile_written_when_missing
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


    stub_request(:get, "https://rubygems.org/gems/rack-2.0.3.gem").
      to_return(body: File.open(fixture_file("rack-2.0.3.gem")))

    env = {
      "GEL_LOCKFILE" => nil
    }
    with_env(env: env) do
      gemfile = File.new("Gemfile", "w+")
      gemfile.write(<<GEMFILE)
source "https://rubygems.org"

gem "rack"
GEMFILE
      gemfile.close
      with_empty_store do |store|
        subprocess_output(<<-'END', store: store)
          Gel::Environment.activate(install: true, output: StringIO.new)
        END
      end
      assert_equal <<LOCKFILE, File.read("#{Dir.pwd}/Gemfile.lock")
GEM
  remote: https://rubygems.org/
  specs:
    rack (2.0.3)

PLATFORMS
  ruby

DEPENDENCIES
  rack
LOCKFILE
    end
  end

  def test_lockfile_updated_when_gem_added
        stub_request(:get, "https://index.rubygems.org/versions").
      to_return(body: <<VERSIONS)
created_at: 2017-03-27T04:38:13+00:00
---
rack 2.0.3 xxx
rack-test 0.6.3 xxx

VERSIONS

    stub_request(:get, "https://index.rubygems.org/info/rack").
      to_return(body: <<INFO)
---
2.0.3 |checksum:zzz
INFO

    stub_request(:get, "https://index.rubygems.org/info/rack-test").
      to_return(body: <<INFO)
---
0.6.3 |checksum:zzz
INFO


    stub_request(:get, "https://rubygems.org/gems/rack-2.0.3.gem").
      to_return(body: File.open(fixture_file("rack-2.0.3.gem")))

    env = {
      "GEL_LOCKFILE" => nil
    }
    with_env(env: env) do
      gemfile = File.new("Gemfile", "w+")
      gemfile.write(<<GEMFILE)
source "https://rubygems.org"

gem "rack"
gem "rack-test"
GEMFILE
      gemfile.close

      lockfile = File.new("Gemfile.lock", "w+")
      lockfile.write(<<CURRENT_LOCKFILE)
GEM
  remote: https://rubygems.org/
  specs:
    rack (2.0.3)

PLATFORMS
  ruby

DEPENDENCIES
  rack
CURRENT_LOCKFILE
      lockfile.close

      with_empty_store do |store|
        subprocess_output(<<-'END', store: store)
          Gel::Environment.activate(install: true, output: StringIO.new)
        END
      end

      assert_equal <<LOCKFILE, File.read("#{Dir.pwd}/Gemfile.lock")
GEM
  remote: https://rubygems.org/
  specs:
    rack (2.0.3)
    rack-test (0.6.3)

PLATFORMS
  ruby

DEPENDENCIES
  rack
  rack-test
LOCKFILE
    end
  end

  def test_lockfile_updated_when_gem_removed
        stub_request(:get, "https://index.rubygems.org/versions").
      to_return(body: <<VERSIONS)
created_at: 2017-03-27T04:38:13+00:00
---
rack 2.0.3 xxx
rack-test 0.6.3 xxx

VERSIONS

    stub_request(:get, "https://index.rubygems.org/info/rack").
      to_return(body: <<INFO)
---
2.0.3 |checksum:zzz
INFO

#     stub_request(:get, "https://index.rubygems.org/info/rack-test").
#       to_return(body: <<INFO)
# ---
# 0.6.3 |checksum:zzz
# INFO


    stub_request(:get, "https://rubygems.org/gems/rack-2.0.3.gem").
      to_return(body: File.open(fixture_file("rack-2.0.3.gem")))

    env = {
      "GEL_LOCKFILE" => nil
    }
    with_env(env: env) do
      gemfile = File.new("Gemfile", "w+")
      gemfile.write(<<GEMFILE)
source "https://rubygems.org"

gem "rack"
GEMFILE
      gemfile.close

      lockfile = File.new("Gemfile.lock", "w+")
      lockfile.write(<<CURRENT_LOCKFILE)
GEM
  remote: https://rubygems.org/
  specs:
    rack (2.0.3)
    rack-test (0.6.3)

PLATFORMS
  ruby

DEPENDENCIES
  rack
  rack-test
CURRENT_LOCKFILE
      lockfile.close

      with_empty_store do |store|
        subprocess_output(<<-'END', store: store)
          Gel::Environment.activate(install: true, output: StringIO.new)
        END
      end

      assert_equal <<LOCKFILE, File.read("#{Dir.pwd}/Gemfile.lock")
GEM
  remote: https://rubygems.org/
  specs:
    rack (2.0.3)

PLATFORMS
  ruby

DEPENDENCIES
  rack
LOCKFILE
    end
  end

  def with_env(env:)
    prev_env = {}
    prev_dir = Dir.pwd
    prev_gemfile = Gel::Environment.instance_variable_get(:@gemfile)
    prev_active_lockfile = Gel::Environment.instance_variable_get(:@active_lockfile)


    Gel::Environment.instance_variable_set(:@gemfile, nil)
    Gel::Environment.instance_variable_set(:@active_lockfile, nil)


    env.each do |key, val|
      prev_env[key] = ENV[key]
      ENV[key] = val
    end

    Dir.mktmpdir do |project_dir|
      Dir.chdir project_dir do
        yield
      end
    end


  ensure
    prev_env.each do |key, val|
      ENV[key] = val
    end

    Gel::Environment.instance_variable_set(:@gemfile, prev_gemfile)
    Gel::Environment.instance_variable_set(:@active_lockfile, prev_active_lockfile)
  end
end
