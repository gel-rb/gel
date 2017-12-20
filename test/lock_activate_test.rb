require "test_helper"

class LockActivateTest < Minitest::Test
  def test_activate_simple_lockfile
    lockfile = Tempfile.new
    lockfile.write(<<LOCKFILE)
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

    loader = Paperback::LockLoader.new(lockfile.path)
    with_fixture_gems_installed(["rack-test-0.6.3.gem", "rack-2.0.3.gem", "hoe-3.0.0.gem"]) do |store|
      output = read_from_fork do |ch|
        loader.activate(Paperback::Environment, store)

        ch.puts $:.grep(/\brack(?!-test)/).join(":")
        ch.puts $:.grep(/rack-test/).join(":")
        ch.puts $:.grep(/hoe/).join(":")
        ch.puts $".grep(/rack\/test\//).join(":")
      end.lines.map(&:chomp)

      # Both gems listed in the lockfile are activated
      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output.shift
      assert_equal "#{store.root}/gems/rack-test-0.6.3/lib", output.shift

      # Other installed gems are not
      assert_equal "", output.shift

      # Nothing has been required
      assert_equal "", output.shift
    end
  end

  def test_activate_lockfile_with_path
    Dir.mktmpdir("rack-") do |temp_dir|
      lockfile = Tempfile.new
      lockfile.write(<<LOCKFILE)
PATH
  remote: #{temp_dir}
  specs:
    rack (2.0.3)

GEM
  remote: https://rubygems.org/
  specs:
    rack-test (0.6.3)
      rack (>= 1.0)

DEPENDENCIES
  rack!
  rack-test
LOCKFILE
      lockfile.close

      loader = Paperback::LockLoader.new(lockfile.path)
      with_fixture_gems_installed(["rack-test-0.6.3.gem", "rack-2.0.3.gem", "hoe-3.0.0.gem"]) do |store|
        output = read_from_fork do |ch|
          loader.activate(Paperback::Environment, store)

          ch.puts $:.grep(/\brack(?!-test)/).join(":")
          ch.puts $:.grep(/rack-test/).join(":")
          ch.puts $:.grep(/hoe/).join(":")
          ch.puts $".grep(/rack\/test\//).join(":")
        end.lines.map(&:chomp)

        # rack is activated from the lockfile-specified path
        assert_equal "#{temp_dir}/lib", output.shift

        # rack-test is still coming from the main store
        assert_equal "#{store.root}/gems/rack-test-0.6.3/lib", output.shift

        # Other installed gems are not activated
        assert_equal "", output.shift

        # Nothing has been required
        assert_equal "", output.shift
      end
    end
  end

  def test_ignore_gems_excluded_by_gemfile
    gemfile_content = <<GEMFILE
gem "rack"
gem "rack-test", platforms: :rbx
GEMFILE

    lockfile = Tempfile.new
    lockfile.write(<<LOCKFILE)
GEM
  remote: https://rubygems.org/
  specs:
    rack (2.0.3)
    rack-test (0.6.3)
      rack (>= 1.0)

DEPENDENCIES
  rack
  rack-test
LOCKFILE
    lockfile.close

    loader = Paperback::LockLoader.new(lockfile.path, Paperback::GemfileParser.parse(gemfile_content))
    with_fixture_gems_installed(["rack-test-0.6.3.gem", "rack-2.0.3.gem", "hoe-3.0.0.gem"]) do |store|
      output = read_from_fork do |ch|
        loader.activate(Paperback::Environment, store)

        ch.puts $:.grep(/\brack(?!-test)/).join(":")
        ch.puts $:.grep(/rack-test/).join(":")
        ch.puts $:.grep(/hoe/).join(":")
      end.lines.map(&:chomp)

      # rack is activated because the Gemfile references it directly,
      # for all platforms. rack-test is excluded by its platform option.
      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output.shift
      assert_equal "", output.shift

      # Other installed gems are also not activated
      assert_equal "", output.shift
    end
  end

  def test_ignore_dependent_gems_excluded_by_gemfile
    gemfile_content = <<GEMFILE
gem "rack-test", platforms: :rbx
GEMFILE

    lockfile = Tempfile.new
    lockfile.write(<<LOCKFILE)
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

    loader = Paperback::LockLoader.new(lockfile.path, Paperback::GemfileParser.parse(gemfile_content))
    with_fixture_gems_installed(["rack-test-0.6.3.gem", "rack-2.0.3.gem", "hoe-3.0.0.gem"]) do |store|
      output = read_from_fork do |ch|
        loader.activate(Paperback::Environment, store)

        ch.puts $:.grep(/\brack(?!-test)/).join(":")
        ch.puts $:.grep(/rack-test/).join(":")
        ch.puts $:.grep(/hoe/).join(":")
      end.lines.map(&:chomp)

      # Neither gem is activated; rack-test is not wanted by this
      # platform, and rack is just a dependency
      assert_equal "", output.shift
      assert_equal "", output.shift

      # Other installed gems are also not activated
      assert_equal "", output.shift
    end
  end
end
