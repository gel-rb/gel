require "test_helper"

class LockedActivateTest < Minitest::Test
  def test_lock_forces_version
    with_fixture_gems_installed(["rack-2.0.3.gem", "rack-0.1.0.gem"]) do |store|
      output = read_from_fork do |ch|
        Paperback::Environment.open(store)
        Paperback::Environment.gem "rack"

        ch.puts $:.grep(/\brack/).join(":")
      end.lines.map(&:chomp)

      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output.shift


      locked_store = Paperback::LockedStore.new(store)
      locked_store.lock("rack" => "0.1.0")

      output = read_from_fork do |ch|
        Paperback::Environment.open(locked_store)
        Paperback::Environment.gem "rack"

        ch.puts $:.grep(/\brack/).join(":")
      end.lines.map(&:chomp)

      assert_equal "#{store.root}/gems/rack-0.1.0/lib", output.shift
    end
  end

  def test_lock_excludes_gems
    with_fixture_gems_installed(["hoe-3.0.0.gem", "rack-2.0.3.gem"]) do |store|
      output = read_from_fork do |ch|
        Paperback::Environment.open(store)
        Paperback::Environment.gem "rack"

        ch.puts $:.grep(/\brack/).join(":")
      end.lines.map(&:chomp)

      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output.shift


      locked_store = Paperback::LockedStore.new(store)
      locked_store.lock("hoe" => "3.0.0")

      output = read_from_fork do |ch|
        Paperback::Environment.open(locked_store)
        begin
          Paperback::Environment.gem "rack"
        rescue => ex
          ch.puts ex.message
        end
      end.lines.map(&:chomp)

      assert_equal "unable to satisfy requirements for gem rack: >= 0", output.shift
    end
  end
end

