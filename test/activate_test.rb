# frozen_string_literal: true

require "test_helper"

class ActivateTest < Minitest::Test
  def test_basic_gem_activation
    with_fixture_gems_installed(["rack-2.0.3.gem", "rack-0.1.0.gem"]) do |store|
      assert_raises(LoadError) { require "rack" }
      assert_raises(LoadError) { require "rack/request" }

      output = subprocess_output(<<-'END', store: store)
        Gel::Environment.open(store)
        Gel::Environment.gem "rack", "2.0.3"

        require "rack"
        require "rack/request"

        puts $LOAD_PATH.grep(/\brack/).join(":")
        puts $LOADED_FEATURES.grep(/\brack\/request/).join(":")
      END

      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output.shift
      assert_equal "#{store.root}/gems/rack-2.0.3/lib/rack/request.rb", output.shift
    end
  end

  def test_basic_gem_activation_prefers_latest
    with_fixture_gems_installed(["rack-0.1.0.gem", "rack-2.0.3.gem"]) do |store|
      assert_raises(LoadError) { require "rack" }
      assert_raises(LoadError) { require "rack/request" }

      output = subprocess_output(<<-'END', store: store)
        Gel::Environment.open(store)
        Gel::Environment.gem "rack"

        require "rack"
        require "rack/request"

        puts $LOAD_PATH.grep(/\brack/).join(":")
        puts $LOADED_FEATURES.grep(/\brack\/request/).join(":")
      END

      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output.shift
      assert_equal "#{store.root}/gems/rack-2.0.3/lib/rack/request.rb", output.shift
    end
  end

  def test_basic_gem_activation_loads_older_when_requested
    with_fixture_gems_installed(["rack-0.1.0.gem", "rack-2.0.3.gem"]) do |store|
      assert_raises(LoadError) { require "rack" }
      assert_raises(LoadError) { require "rack/utils" }

      output = subprocess_output(<<-'END', store: store)
        Gel::Environment.open(store)
        Gel::Environment.gem "rack", "< 2"

        # Avoid requiring "rack" itself, because 0.1.0's rack.rb
        # directly manipulates $LOAD_PATH, which is confusing
        require "rack/utils"

        puts $LOAD_PATH.grep(/\brack/).join(":")
        puts $LOADED_FEATURES.grep(/\brack\/utils/).join(":")
      END

      assert_equal "#{store.root}/gems/rack-0.1.0/lib", output.shift
      assert_equal "#{store.root}/gems/rack-0.1.0/lib/rack/utils.rb", output.shift
    end
  end

  def test_automatic_gem_activation
    with_fixture_gems_installed(["rack-2.0.3.gem", "rack-0.1.0.gem"]) do |store|
      assert_raises(LoadError) { require "rack" }
      assert_raises(LoadError) { require "rack/request" }

      output = subprocess_output(<<-'END', store: store)
        Gel::Environment.open(store)
        require Gel::Environment.resolve_gem_path("rack/request")

        puts $LOAD_PATH.grep(/\brack/).join(":")
        puts $LOADED_FEATURES.grep(/\brack\/request/).join(":")
      END

      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output.shift
      assert_equal "#{store.root}/gems/rack-2.0.3/lib/rack/request.rb", output.shift
    end
  end

  def test_automatic_gem_activation_prefers_latest
    with_fixture_gems_installed(["rack-0.1.0.gem", "rack-2.0.3.gem"]) do |store|
      assert_raises(LoadError) { require "rack" }
      assert_raises(LoadError) { require "rack/request" }

      output = subprocess_output(<<-'END', store: store)
        Gel::Environment.open(store)
        require Gel::Environment.resolve_gem_path("rack/request")

        puts $LOAD_PATH.grep(/\brack/).join(":")
        puts $LOADED_FEATURES.grep(/\brack\/request/).join(":")
      END

      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output.shift
      assert_equal "#{store.root}/gems/rack-2.0.3/lib/rack/request.rb", output.shift
    end
  end

  def test_activate_simple_dependencies
    with_fixture_gems_installed(["rack-test-0.6.3.gem", "rack-2.0.3.gem"]) do |store|
      assert_raises(LoadError) { require "rack/test" }

      output = subprocess_output(<<-'END', store: store)
        Gel::Environment.open(store)
        require Gel::Environment.resolve_gem_path("rack/test")

        puts $LOAD_PATH.grep(/\brack(?!-test)/).join(":")
        puts $LOAD_PATH.grep(/rack-test/).join(":")
        puts $LOADED_FEATURES.grep(/rack\/test\/ut/).join(":")
      END

      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output.shift
      assert_equal "#{store.root}/gems/rack-test-0.6.3/lib", output.shift
      assert_equal "#{store.root}/gems/rack-test-0.6.3/lib/rack/test/utils.rb", output.shift
    end
  end

  def test_report_activation_conflicts
    with_fixture_gems_installed(["rack-test-0.6.3.gem", "rack-0.1.0.gem", "rack-2.0.3.gem"]) do |store|
      assert_raises(LoadError) { require "rack/test" }

      output = subprocess_output(<<-'END', store: store)
        Gel::Environment.open(store)
        Gel::Environment.gem "rack", "0.1.0"
        begin
          require Gel::Environment.resolve_gem_path("rack/test")
        rescue LoadError => ex
          puts ex
        end
      END

      assert_equal "already loaded gem rack 0.1.0, which is incompatible with: >= 1.0 (required by rack-test 0.6.3; provides \"rack/test\")", output.shift
    end
  end

  def test_report_unsatisfiable_constraints
    with_fixture_gems_installed(["rack-2.0.3.gem"]) do |store|
      assert_raises(LoadError) { require "rack" }

      output = subprocess_output(<<-'END', store: store)
        Gel::Environment.open(store)
        begin
          Gel::Environment.gem "rack", "< 1.0"
        rescue LoadError => ex
          puts ex
        end
      END

      assert_equal "unable to satisfy requirements for gem rack: < 1.0", output.shift
    end
  end

  def test_activate_gem_with_extensions
    skip if jruby?

    with_fixture_gems_installed(["fast_blank-1.0.0.gem"]) do |store|
      assert_raises(LoadError) { require "fast_blank" }
      assert_raises(NoMethodError) { "x".blank? }

      output = subprocess_output(<<-'END', store: store)
        Gel::Environment.open(store)
        require Gel::Environment.resolve_gem_path("fast_blank")

        puts $LOAD_PATH.grep(/fast_blank/).join(":")

        puts ["x", "", " "].map(&:blank?).join(",")
      END

      assert_equal ["#{store.root}/gems/fast_blank-1.0.0/lib",
                    "#{store.root}/ext/fast_blank-1.0.0"], output.shift.split(":")

      assert_equal "false,true,true", output.shift
    end
  end
end
