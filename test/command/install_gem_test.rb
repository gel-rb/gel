# frozen_string_literal: true

require "test_helper"

class InstallGemTest < Minitest::Test
  def test_install_gem
    with_empty_store do |store|
      with_empty_cache do
        subprocess_output(<<-'END', store: store, lock_path: nil)
          $stderr.reopen($stdout)

          stub_gem_mimer(source: "https://index.rubygems.org")

          stub_request(:get, "https://rubygems.org/gems/rack-2.0.6.gem")
            .to_return(body: File.open(fixture_file("rack-2.0.6.gem")))

          stub_request(:get, "https://rubygems.org/gems/rack-test-0.6.3.gem")
            .to_return(body: File.open(fixture_file("rack-test-0.6.3.gem")))

          stub_request(:get, "https://rubygems.org/gems/pub_grub-0.5.0.gem")
            .to_return(body: File.open(fixture_file("pub_grub-0.5.0.gem")))

          Gel::Environment.open(store)
          require "gel/command"
          require "gel/command/install_gem"
          Gel::Command.run(["install-gem", "rack-test", "0.6.3"])
        END
      end

      output = subprocess_output(<<-'END', store: store, lock_path: nil)
        Gel::Environment.open(store)
        gem "rack-test"

        puts $:.grep(/\brack(?!-test)/).join(":")
        puts $:.grep(/rack-test/).join(":")
        puts $:.grep(/hoe/).join(":")
        puts $".grep(/rack\/test\//).join(":")
      END

      # Both gems listed in the lockfile are activated
      assert_equal "#{store.root}/gems/rack-2.0.6/lib", output.shift
      assert_equal "#{store.root}/gems/rack-test-0.6.3/lib", output.shift

      # Other installed gems are not
      assert_equal "", output.shift

      # Nothing has been required
      assert_equal "", output.shift
    end
  end
end
