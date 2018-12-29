# frozen_string_literal: true

require "test_helper"

class GemfileParserTest < Minitest::Test
  EXAMPLE_LINE, EXAMPLE = __LINE__ + 1, <<'GEMFILE'
source "https://rubygems.org"
ruby RUBY_VERSION

git_source(:github) { |repo| "https://github.com/#{repo}.git" }

gem "rake", ">= 11.1"
gem "mocha", require: false
gem "bcrypt", "~> 3.1.11", require: false
gem "stopgap_13632", platforms: :mri if RUBY_VERSION == "2.2.8"

group :doc do
  gem "w3c_validators", require: "w3c_validators/validator"
end

group :test do
  gem "minitest-bisect"

  platforms :mri do
    gem "stackprof"
    gem "byebug"
  end

  gem "benchmark-ips"
end

source "https://rails-assets.org" do
  gem "rails-assets-bootstrap"
end
GEMFILE

  def test_simple_parse
    result = Paperback::GemfileParser.parse(EXAMPLE, __FILE__, EXAMPLE_LINE)
    assert_equal ["https://rubygems.org"], result.sources

    assert_equal [
      ["rake", [">= 11.1"], {}],
      ["mocha", [], require: false],
      ["bcrypt", ["~> 3.1.11"], require: false],
      ["w3c_validators", [], group: [:doc], require: "w3c_validators/validator"],
      ["minitest-bisect", [], group: [:test]],
      ["stackprof", [], platforms: [:mri], group: [:test]],
      ["byebug", [], platforms: [:mri], group: [:test]],
      ["benchmark-ips", [], group: [:test]],
      ["rails-assets-bootstrap", [], source: "https://rails-assets.org"],
    ], result.gems
  end

  def test_autorequire_mocked
    result = Paperback::GemfileParser.parse(EXAMPLE, __FILE__, EXAMPLE_LINE)

    requirer = Minitest::Mock.new
    requirer.expect(:gem_has_file?, true, ["rake", "rake"])
    requirer.expect(:scoped_require, true, ["rake", "rake"])
    requirer.expect(:scoped_require, true, ["w3c_validators", "w3c_validators/validator"])
    requirer.expect(:gem_has_file?, true, ["minitest-bisect", "minitest-bisect"])
    requirer.expect(:scoped_require, true, ["minitest-bisect", "minitest-bisect"])
    requirer.expect(:gem_has_file?, true, ["stackprof", "stackprof"])
    requirer.expect(:scoped_require, true, ["stackprof", "stackprof"])
    requirer.expect(:gem_has_file?, false, ["byebug", "byebug"])
    requirer.expect(:gem_has_file?, false, ["benchmark-ips", "benchmark-ips"])
    requirer.expect(:gem_has_file?, true, ["benchmark-ips", "benchmark/ips"])
    requirer.expect(:scoped_require, true, ["benchmark-ips", "benchmark/ips"])
    requirer.expect(:gem_has_file?, false, ["rails-assets-bootstrap", "rails-assets-bootstrap"])
    requirer.expect(:gem_has_file?, false, ["rails-assets-bootstrap", "rails/assets/bootstrap"])

    result.autorequire(requirer)
    requirer.verify
  end

  def test_autorequire_real
    with_fixture_gems_installed(["rack-test-0.6.3.gem", "rack-2.0.3.gem", "hoe-3.0.0.gem"]) do |store|
      output = subprocess_output(<<-'END', store: store)
        result = Paperback::GemfileParser.parse(<<GEMFILE, __FILE__, __LINE__ + 1)
gem "rack", require: "rack/query_parser"
gem "rack-test"
gem "hoe", require: false
GEMFILE

        Paperback::Environment.open(store)
        Paperback::Environment.gem "rack"
        Paperback::Environment.gem "rack-test"
        result.autorequire(Paperback::Environment)

        puts $".grep(/\brack\//).first
        puts $".grep(/rack\/test\//).first
        puts $".grep(/\bhoe\b/).first
      END

      # The first file loaded from rack is the one that was requested
      assert_equal "#{store.root}/gems/rack-2.0.3/lib/rack/query_parser.rb", output.shift

      # rack-test got found by its rack/test alternate name
      assert_equal "#{store.root}/gems/rack-test-0.6.3/lib/rack/test/cookie_jar.rb", output.shift

      # Other installed gems are not required
      assert_equal "", output.shift
    end
  end
end
