# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/gel/command"

class EnvTest < Minitest::Test
  def test_env_command
    output = capture_stdout { Gel::Command.run(%w[env]) }

    assert_match(/^Context/, output)
    assert_match(/^Gel/, output)
    assert_match(/^Ruby/, output)
    assert_match(/^System/, output)
    assert_match(/^  PATH/, output)

    refute_match(/^ruby /, output)
    refute_match(/^#{Regexp.escape(home_relative_path(File.expand_path("../../lib/gel/command.rb", __dir__)))}$/, output)

    refute_match(/^source "/, output)
    refute_match(/^DEPENDENCIES/, output)

    headings = output.lines(chomp: true).select { |line| line.start_with?("##") }
    assert_equal([
      "#### Gel Environment ####",
    ], headings)
  end

  def test_env_command_verbose
    output = capture_stdout { Gel::Command.run(%w[env -v]) }

    assert_match(/^Context/, output)
    assert_match(/^Gel/, output)
    assert_match(/^Ruby/, output)
    assert_match(/^System/, output)
    assert_match(/^  PATH/, output)

    assert_match(/^ruby /, output)
    assert_match(/^#{Regexp.escape(home_relative_path(File.expand_path("../../lib/gel/command.rb", __dir__)))}$/, output)

    assert_match(/^source "/, output)
    assert_match(/^DEPENDENCIES/, output)

    headings = output.lines(chomp: true).select { |line| line.start_with?("##") }
    assert_equal([
      "#### Gel Environment ####",
      "#### Commands ####",
      "#### Runtime ####",
      "#### Load Path ####",
      "#### Files ####",
      "##### `#{home_relative_path Gel::Config.new.path}` #####",
      "##### `#{home_relative_path File.expand_path("../../Gemfile", __dir__)}` #####",
      "##### `#{home_relative_path File.expand_path("../../Gemfile.lock", __dir__)}` #####",
    ], headings)
  end

  private

  def home_relative_path(path)
    if path.start_with?(ENV["HOME"])
      path.sub(ENV["HOME"], "~")
    else
      path
    end
  end
end
