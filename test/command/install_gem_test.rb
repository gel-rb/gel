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
          Gel::Command.run(["install-gem", "rack-test", "0.6.3"])
        END
      end

      output = subprocess_output(<<-'END', store: store, lock_path: nil)
        Gel::Environment.open(store)
        gem "rack-test"

        puts $:.grep(/\brack(?!-test)/).join(":")
        puts $:.grep(/rack-test/).join(":")
      END

      # Both expected gems have been installed and activated: the
      # requested version of rack-test, and the latest version of rack
      # listed in our fixture catalog.
      assert_equal "#{store.root}/gems/rack-2.0.6/lib", output.shift
      assert_equal "#{store.root}/gems/rack-test-0.6.3/lib", output.shift
    end
  end
end
