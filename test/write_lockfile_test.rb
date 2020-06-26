# frozen_string_literal: true

require "test_helper"

class WriteLockfileTest < Minitest::Test
  def test_lockfile_written_when_missing
    stub_gem_mimer(source: "https://index.rubygems.org")

    stub_request(:get, "https://rubygems.org/gems/rack-2.0.6.gem").
      to_return(body: File.open(fixture_file("rack-2.0.6.gem")))

    stub_request(:get, "https://rubygems.org/gems/pub_grub-0.5.0.gem").
      to_return(body: File.open(fixture_file("pub_grub-0.5.0.gem")))

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
        output = subprocess_output(<<-'END', store: store)
          Gel::Environment.with_store(store) do
            Gel::Environment.activate(install: true, output: StringIO.new)
            Gel::Environment.gem "rack"

            puts $:.grep(/\brack/).join(":")
          end
        END

        assert_equal "#{store.root}/gems/rack-2.0.6/lib", output.shift
      end
      assert_equal <<LOCKFILE, File.read("#{Dir.pwd}/Gemfile.lock")
GEM
  remote: https://rubygems.org/
  specs:
    rack (2.0.6)

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

    stub_request(:get, "https://rubygems.org/gems/rack-test-0.6.3.gem").
      to_return(body: File.open(fixture_file("rack-test-0.6.3.gem")))

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

  def test_does_not_write_lockfile_when_unchanged
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

      lockfile_contents = <<CURRENT_LOCKFILE
GEM
  remote: https://rubygems.org/
  specs:
    rack (2.0.3)

PLATFORMS
  ruby

DEPENDENCIES
  rack
CURRENT_LOCKFILE

      lockfile = File.new("Gemfile.lock", "w+")
      lockfile.write(lockfile_contents)
      lockfile.close

      with_empty_store do |store|
        subprocess_output(<<-'END', store: store)
          Gel::Environment.activate(install: true, output: StringIO.new)
        END
      end

      assert_equal lockfile_contents, File.read("#{Dir.pwd}/Gemfile.lock")
    end
  end

  def test_does_write_lockfile_when_gem_version_changes
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

gem "rack", "2.0.3"
GEMFILE
      gemfile.close

      lockfile_contents = <<CURRENT_LOCKFILE
GEM
  remote: https://rubygems.org/
  specs:
    rack (2.0.2)

PLATFORMS
  ruby

DEPENDENCIES
  rack
CURRENT_LOCKFILE

      lockfile = File.new("Gemfile.lock", "w+")
      lockfile.write(lockfile_contents)
      lockfile.close

      expected_lockfile_contents = <<EXPECTED_LOCKFILE
GEM
  remote: https://rubygems.org/
  specs:
    rack (2.0.3)

PLATFORMS
  ruby

DEPENDENCIES
  rack (= 2.0.3)
EXPECTED_LOCKFILE

      with_empty_store do |store|
        subprocess_output(<<-'END', store: store)
          Gel::Environment.activate(install: true, output: StringIO.new)
        END
      end

      assert_equal expected_lockfile_contents, File.read("#{Dir.pwd}/Gemfile.lock")
    end
  end

  def test_correctly_handles_bang_gemfile
    stub_gem_mimer(source: "https://index.rubygems.org")

    stub_request(:get, "https://rubygems.org/gems/pub_grub-0.5.0.gem").
      to_return(body: File.open(fixture_file("pub_grub-0.5.0.gem")))

    stub_request(:get, "https://rubygems.org/gems/rack-2.0.6.gem").
      to_return(body: File.open(fixture_file("rack-2.0.6.gem")))

    env = {
      "GEL_LOCKFILE" => nil
    }
    with_env(env: env) do
      Dir.mkdir "my-local-gem"
      IO.write("my-local-gem/my-local-gem.gemspec", <<GEMSPEC)
Gem::Specification.new do |spec|
  spec.name = "my-local-gem"
  spec.version = "867.5309"

  spec.add_runtime_dependency "rack"
end
GEMSPEC

      gemfile = File.new("Gemfile", "w+")
      gemfile.write(<<GEMFILE)
source "https://rubygems.org"

gem "my-local-gem", path: './my-local-gem'
GEMFILE
      gemfile.close

      lockfile_contents = <<LOCKFILE
PATH
  remote: ./my-local-gem
  specs:
    my-local-gem (867.5309)
      rack

GEM
  remote: https://rubygems.org/
  specs:
    rack (2.0.6)

PLATFORMS
  ruby

DEPENDENCIES
  my-local-gem!
LOCKFILE

      # Resolve from scratch, generating the lockfile
      with_empty_store do |store|
        output = subprocess_output(<<-'END', store: store)
          Gel::Environment.with_store(store) do
            Gel::Environment.activate(install: true, output: StringIO.new)
            Gel::Environment.gem "my-local-gem"

            puts $:.grep(/\bmy-local-gem/).join(":")
          end
        END

        assert_equal "#{Dir.pwd}/my-local-gem/lib", output.shift
      end

      # Check we ended up with the lockfile we expected
      assert_equal lockfile_contents, File.read("#{Dir.pwd}/Gemfile.lock")

      # Now do a fresh run, using that as an "existing" lockfile
      with_empty_store do |store|
        output = subprocess_output(<<-'END', store: store)
          Gel::Environment.with_store(store) do
            Gel::Environment.activate(install: true, output: StringIO.new)
            Gel::Environment.gem "my-local-gem"

            puts $:.grep(/\bmy-local-gem/).join(":")
          end
        END

        assert_equal "#{Dir.pwd}/my-local-gem/lib", output.shift
      end

      # Check it didn't change
      assert_equal lockfile_contents, File.read("#{Dir.pwd}/Gemfile.lock")
    end
  end

  def with_env(env:)
    prev_env = {}

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
