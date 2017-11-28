require "test_helper"

class LockActivateTest < Minitest::Test
  def test_activate_simple_lockfile
    lockfile = Tempfile.new
    lockfile.write(<<LOCKFILE)
GEM
  remote: https://rubygems.org/
  specs:
    json_pure (2.1.0)
    rubyforge (2.0.4)
      json_pure (>= 1.1.7)

DEPENDENCIES
  rubyforge
LOCKFILE
    lockfile.close

    loader = Paperback::LockLoader.new(lockfile.path)
    with_fixture_gems_installed(["rubyforge-2.0.4.gem", "json_pure-2.1.0.gem", "rack-2.0.3.gem"]) do |store|
      output = read_from_fork do |ch|
        loader.activate(Paperback::Environment, store)
        $-w = false

        ch.puts $:.grep(/json_pure/).join(":")
        ch.puts $:.grep(/rubyforge/).join(":")
        ch.puts $:.grep(/rack/).join(":")
        ch.puts $".grep(/rubyforge\//).join(":")
      end.lines.map(&:chomp)

      # Both gems listed in the lockfile are activated
      assert_equal "#{store.root}/gems/json_pure-2.1.0/lib", output.shift
      assert_equal "#{store.root}/gems/rubyforge-2.0.4/lib", output.shift

      # Other installed gems are not
      assert_equal "", output.shift

      # Nothing has been required
      assert_equal "", output.shift
    end
  end

  def test_activate_lockfile_with_path
    Dir.mktmpdir("json_pure-") do |temp_dir|
      lockfile = Tempfile.new
      lockfile.write(<<LOCKFILE)
PATH
  remote: #{temp_dir}
  specs:
    json_pure (2.1.0)

GEM
  remote: https://rubygems.org/
  specs:
    rubyforge (2.0.4)
      json_pure (>= 1.1.7)

DEPENDENCIES
  json_pure!
  rubyforge
LOCKFILE
      lockfile.close

      loader = Paperback::LockLoader.new(lockfile.path)
      with_fixture_gems_installed(["rubyforge-2.0.4.gem", "json_pure-2.1.0.gem", "rack-2.0.3.gem"]) do |store|
        output = read_from_fork do |ch|
          loader.activate(Paperback::Environment, store)
          $-w = false

          ch.puts $:.grep(/json_pure/).join(":")
          ch.puts $:.grep(/rubyforge/).join(":")
          ch.puts $:.grep(/rack/).join(":")
          ch.puts $".grep(/rubyforge\//).join(":")
        end.lines.map(&:chomp)

        # json_pure is activated from the lockfile-specified path
        assert_equal "#{temp_dir}/lib", output.shift

        # rubyforge is still coming from the main store
        assert_equal "#{store.root}/gems/rubyforge-2.0.4/lib", output.shift

        # Other installed gems are not activated
        assert_equal "", output.shift

        # Nothing has been required
        assert_equal "", output.shift
      end
    end
  end
end
