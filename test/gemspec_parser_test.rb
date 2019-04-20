# frozen_string_literal: true

require "test_helper"

class GemspecParserTest < Minitest::Test
  EXAMPLE_LINE, EXAMPLE = __LINE__ + 1, <<~'GEMSPEC'
    require File.expand_path("lib/gel/version")

    # This is based on, but does not match, our real gemspec
    Gem::Specification.new do |spec|
      spec.name          = "gel"
      spec.version       = Gel::VERSION
      spec.authors       = ["Some Authors"]
      spec.email         = ["example@example.com"]

      spec.summary       = "Short summary text"
      spec.homepage      = "https://example.com"
      spec.license       = "MIT"

      # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
      # to allow pushing to a single host or delete this section to allow pushing to any host.
      if spec.respond_to?(:metadata)
        spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
      else
        raise "RubyGems 2.0 or newer is required to protect against " \
          "public gem pushes."
      end

      spec.files         = `git ls-files -z`.split("\x0").reject do |f|
        f.match(%r{^(test|spec|features)/})
      end
      spec.bindir        = "exe"
      spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
      spec.require_paths = ["lib"]

      spec.add_development_dependency "rake", "~> 10.0"
      spec.add_development_dependency "minitest", "~> 5.0"
    end
  GEMSPEC

  def test_simple_parse
    gemspec = Gel::GemspecParser.parse(EXAMPLE, __FILE__, EXAMPLE_LINE, root: File.expand_path("..", __dir__), isolate: false)

    assert_equal "gel", gemspec.name
    assert_equal Gel::VERSION, gemspec.version
    assert_equal ["lib"], gemspec.require_paths
    assert_equal "exe", gemspec.bindir
    assert gemspec.files.include?("lib/gel/gemspec_parser.rb")
    assert_equal [["rake", ["~> 10.0"]], ["minitest", ["~> 5.0"]]], gemspec.development_dependencies
  end
end
