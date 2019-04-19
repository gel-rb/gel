# frozen_string_literal: true

require "test_helper"

class MultiStoreTest < Minitest::Test
  def test_activation_across_stores
    with_fixture_gems_installed(["rack-2.0.3.gem", "rack-0.1.0.gem"]) do |store_1|
      with_fixture_gems_installed(["rack-test-0.6.3.gem"]) do |store_2|
        multi = Gel::MultiStore.new(nil,
          "ruby-#{RbConfig::CONFIG["ruby_version"]}" => store_1,
          "ruby" => store_2)

        output = subprocess_output(<<-'END', store: multi)
          Gel::Environment.open(store)
          require Gel::Environment.resolve_gem_path("rack/test")

          puts $:.grep(/\brack(?!-test)/).join(":")
          puts $:.grep(/rack-test/).join(":")
          puts $".grep(/rack\/test\/ut/).join(":")
        END

        assert_equal "#{store_1.root}/gems/rack-2.0.3/lib", output.shift
        assert_equal "#{store_2.root}/gems/rack-test-0.6.3/lib", output.shift
        assert_equal "#{store_2.root}/gems/rack-test-0.6.3/lib/rack/test/utils.rb", output.shift
      end
    end
  end
end
