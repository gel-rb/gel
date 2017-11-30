require "test_helper"

class LockInstallTest < Minitest::Test
  def test_install_simple_lockfile
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
    with_empty_store do |store|
      output = read_from_fork do |ch|
        loader.activate(Paperback::Environment, store, install: true)
        $-w = false

        ch.puts $:.grep(/json_pure/).join(":")
        ch.puts $:.grep(/rubyforge/).join(":")
        ch.puts $:.grep(/\brack/).join(":")
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
end
