# frozen_string_literal: true

require "test_helper"

class LockInstallTest < Minitest::Test
  def test_install_simple_lockfile
    lockfile = Tempfile.new("")
    lockfile.write(<<~LOCKFILE)
      GEM
        remote: https://rubygems.org/
        specs:
          rack (2.0.3)
          rack-test (0.6.3)
            rack (>= 1.0)

      DEPENDENCIES
        rack-test
    LOCKFILE
    lockfile.close

    stub_request(:get, "https://rubygems.org/gems/rack-2.0.3.gem")
      .to_return(body: File.open(fixture_file("rack-2.0.3.gem")))

    stub_request(:get, "https://rubygems.org/gems/rack-test-0.6.3.gem")
      .to_return(body: File.open(fixture_file("rack-test-0.6.3.gem")))

    with_empty_store do |store|
      output = subprocess_output(<<-'END', store: store, lock_path: lockfile.path)
        loader = Gel::LockLoader.new(lock_path)
        loader.activate(Gel::Environment, store, install: true)

        puts $:.grep(/\brack(?!-test)/).join(":")
        puts $:.grep(/rack-test/).join(":")
        puts $:.grep(/hoe/).join(":")
        puts $".grep(/rack\/test\//).join(":")
      END

      # Both gems listed in the lockfile are activated
      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output.shift
      assert_equal "#{store.root}/gems/rack-test-0.6.3/lib", output.shift

      # Other installed gems are not
      assert_equal "", output.shift

      # Nothing has been required
      assert_equal "", output.shift
    end
  end

  def test_arch_aware_installation
    skip "We (and this test) are not actually arch-aware yet" if jruby?

    lockfile = Tempfile.new("")
    lockfile.write(<<~LOCKFILE)
      GEM
        remote: https://rubygems.org/
        specs:
          atomic (1.1.16)
          atomic (1.1.16-java)
          rack (2.0.3)
          rack-test (0.6.3)
            rack (>= 1.0)

      DEPENDENCIES
        atomic
        rack-test
    LOCKFILE
    lockfile.close

    stub_request(:get, "https://rubygems.org/gems/atomic-1.1.16.gem")
      .to_return(body: File.open(fixture_file("atomic-1.1.16.gem")))

    stub_request(:get, "https://rubygems.org/gems/rack-2.0.3.gem")
      .to_return(body: File.open(fixture_file("rack-2.0.3.gem")))

    stub_request(:get, "https://rubygems.org/gems/rack-test-0.6.3.gem")
      .to_return(body: File.open(fixture_file("rack-test-0.6.3.gem")))

    with_empty_multi_store do |store|
      output = subprocess_output(<<-'END', store: store, lock_path: lockfile.path)
        loader = Gel::LockLoader.new(lock_path)
        loader.activate(Gel::Environment, store, install: true)

        puts $:.grep(/\brack(?!-test)/).join(":")
        puts $:.grep(/rack-test/).join(":")
        puts $:.grep(/atomic/).join(":")
        puts $:.grep(/hoe/).join(":")
        puts $".grep(/rack\/test\//).join(":")
      END

      # All gems listed in the lockfile are activated
      assert_equal "#{store.root}/ruby/gems/rack-2.0.3/lib", output.shift
      assert_equal "#{store.root}/ruby/gems/rack-test-0.6.3/lib", output.shift
      # and in the right directories
      assert_equal "#{store.root}/#{Gel::MultiStore::VERSION}/gems/atomic-1.1.16/lib:#{store.root}/#{Gel::MultiStore::VERSION}/ext/atomic-1.1.16", output.shift

      # Other installed gems are not
      assert_equal "", output.shift

      # Nothing has been required
      assert_equal "", output.shift
    end
  end
end
