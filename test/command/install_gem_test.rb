# frozen_string_literal: true

require "test_helper"

class InstallGemTest < Minitest::Test
  def test_install_gem
    stub_gem_mimer(source: "https://index.rubygems.org")

    stub_request(:get, "https://rubygems.org/gems/rack-2.0.3.gem")
      .to_return(body: File.open(fixture_file("rack-2.0.3.gem")))

    stub_request(:get, "https://rubygems.org/gems/rack-test-0.6.3.gem")
      .to_return(body: File.open(fixture_file("rack-test-0.6.3.gem")))

    with_empty_store do |store|
      subprocess_output(<<-'END', store: store, lock_path: nil)
        Gel::Environment.open(store)
        require "gel/command"
        require "gel/command/install_gem"
        Gel::Command.run(["install-gem", "rack-test", "0.6.3"])
      END

      output = subprocess_output(<<-'END', store: store, lock_path: nil)
        Gel::Environment.open(store)
        gem "rack-test"

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
end
