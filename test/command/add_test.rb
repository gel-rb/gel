# frozen_string_literal: true

require "test_helper"

class AddTest < Minitest::Test
  # def test_add_without_gem
  #   Dir.mktmpdir do |dir|
  #     dir = File.realpath(dir)
  #     gemfile = "#{dir}/Gemfile"
  #     File.write(gemfile, sample_gemfile)

  #     Dir.chdir(dir) do
  #       error = capture_stderr {
  #         Gel::Command.run(["add"])
  #       }
  #       assert_equal "ERROR: Please specify gem to add", error.chomp!
  #     end
  #   end
  # end

  # def test_add_a_gem
  #   Dir.mktmpdir do |dir|
  #     dir = File.realpath(dir)
  #     gemfile = "#{dir}/Gemfile"
  #     File.write(gemfile, sample_gemfile)

  #     Dir.chdir(dir) do
  #       Gel::Command.run(["add", "rack"])
  #     end

  #     assert IO.read(gemfile).include? %(gem "rack"\n)
  #   end
  # end

  # def sample_gemfile
  #   <<~GEMFILE
  #     source "https://rubygems.org"

  #     gemspec
  #   GEMFILE
  # end
end
