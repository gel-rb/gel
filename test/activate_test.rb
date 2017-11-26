require "test_helper"

class ActivateTest < Minitest::Test
  def test_basic_gem_activation
    with_fixture_gems_installed(["rack-2.0.3.gem", "rack-0.1.0.gem"]) do |store|
      assert_raises(LoadError) { require "rack" }
      assert_raises(LoadError) { require "rack/request" }

      output = read_from_fork do |ch|
        Paperback::Environment.activate(store)
        Paperback::Environment.gem "rack", "2.0.3"

        require "rack"
        require "rack/request"

        ch.puts $:.grep(/rack/).join(":")
        ch.puts $".grep(/rack\/request/).join(":")
      end.lines.map(&:chomp)

      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output[0]
      assert_equal "#{store.root}/gems/rack-2.0.3/lib/rack/request.rb", output[1]
    end
  end

  def test_automatic_gem_activation
    with_fixture_gems_installed(["rack-2.0.3.gem", "rack-0.1.0.gem"]) do |store|
      assert_raises(LoadError) { require "rack" }
      assert_raises(LoadError) { require "rack/request" }

      output = read_from_fork do |ch|
        Paperback::Environment.activate(store)
        Paperback::Environment.require "rack/request"

        ch.puts $:.grep(/rack/).join(":")
        ch.puts $".grep(/rack\/request/).join(":")
      end.lines.map(&:chomp)

      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output[0]
      assert_equal "#{store.root}/gems/rack-2.0.3/lib/rack/request.rb", output[1]
    end
  end
end
