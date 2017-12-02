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

        ch.puts $:.grep(/\brack/).join(":")
        ch.puts $".grep(/\brack\/request/).join(":")
      end.lines.map(&:chomp)

      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output.shift
      assert_equal "#{store.root}/gems/rack-2.0.3/lib/rack/request.rb", output.shift
    end
  end

  def test_automatic_gem_activation
    with_fixture_gems_installed(["rack-2.0.3.gem", "rack-0.1.0.gem"]) do |store|
      assert_raises(LoadError) { require "rack" }
      assert_raises(LoadError) { require "rack/request" }

      output = read_from_fork do |ch|
        Paperback::Environment.activate(store)
        Paperback::Environment.require "rack/request"

        ch.puts $:.grep(/\brack/).join(":")
        ch.puts $".grep(/\brack\/request/).join(":")
      end.lines.map(&:chomp)

      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output.shift
      assert_equal "#{store.root}/gems/rack-2.0.3/lib/rack/request.rb", output.shift
    end
  end

  def test_activate_simple_dependencies
    with_fixture_gems_installed(["rubyforge-2.0.4.gem", "json_pure-2.1.0.gem"]) do |store|
      assert_raises(LoadError) { require "rubyforge" }

      output = read_from_fork do |ch|
        Paperback::Environment.activate(store)
        $-w = false
        Paperback::Environment.require "rubyforge"

        ch.puts $:.grep(/json_pure/).join(":")
        ch.puts $:.grep(/rubyforge/).join(":")
        ch.puts $".grep(/rubyforge\//).join(":")
      end.lines.map(&:chomp)

      assert_equal "#{store.root}/gems/json_pure-2.1.0/lib", output.shift
      assert_equal "#{store.root}/gems/rubyforge-2.0.4/lib", output.shift
      assert_equal "#{store.root}/gems/rubyforge-2.0.4/lib/rubyforge/client.rb", output.shift
    end
  end

  def test_report_activation_conflicts
    with_fixture_gems_installed(["rubyforge-2.0.4.gem", "json_pure-1.0.0.gem", "json_pure-2.1.0.gem"]) do |store|
      assert_raises(LoadError) { require "rubyforge" }

      output = read_from_fork do |ch|
        Paperback::Environment.activate(store)
        $-w = false
        Paperback::Environment.gem "json_pure", "1.0.0"
        begin
          Paperback::Environment.require "rubyforge"
        rescue => ex
          ch.puts ex
        end
      end.lines.map(&:chomp)

      assert_equal "already loaded gem json_pure 1.0.0, which is incompatible with: >= 1.1.7", output.shift
    end
  end

  def test_report_unsatisfiable_constraints
    with_fixture_gems_installed(["rack-2.0.3.gem"]) do |store|
      assert_raises(LoadError) { require "rack" }

      output = read_from_fork do |ch|
        Paperback::Environment.activate(store)
        begin
          Paperback::Environment.gem "rack", "< 1.0"
        rescue => ex
          ch.puts ex
        end
      end.lines.map(&:chomp)

      assert_equal "unable to satisfy requirements for gem rack: < 1.0", output.shift
    end
  end

  def test_activate_gem_with_extensions
    with_fixture_gems_installed(["fast_blank-1.0.0.gem"]) do |store|
      assert_raises(LoadError) { require "fast_blank" }
      assert_raises(NoMethodError) { "x".blank? }

      output = read_from_fork do |ch|
        Paperback::Environment.activate(store)
        Paperback::Environment.require "fast_blank"

        ch.puts $:.grep(/fast_blank/).join(":")

        ch.puts ["x", "", " "].map(&:blank?).join(",")
      end.lines.map(&:chomp)

      assert_equal ["#{store.root}/gems/fast_blank-1.0.0/lib",
                    "#{store.root}/ext/fast_blank-1.0.0"], output.shift.split(":")

      assert_equal "false,true,true", output.shift
    end
  end
end
