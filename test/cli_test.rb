# frozen_string_literal: true

require "test_helper"
require "paperback/command"

class CLITest < Minitest::Test
  def setup
    @original_env = ENV.map { |k, v| [k, v.dup] }.to_h

    ENV["PAPERBACK_GEMFILE"] = nil
    ENV["PAPERBACK_LOCKFILE"] = nil
    ENV["RUBYLIB"] = nil
    ENV["RUBYOPT"] = nil
    Paperback::Environment.gemfile = nil
  end

  def teardown
    (@original_env.keys | ENV.keys).each do |key|
      ENV[key] = @original_env[key]
    end
  end

  def test_basic_install
    Paperback::Environment.expects(:activate).with(has_entries(install: true, output: $stderr))

    Paperback::Command.run(%W(install))
  end

  # TODO: There's too much behaviour here, yet it's still not a full
  # integration test. Move the exec logic out of Command::Exec, reducing
  # that to a simple wrapper.
  def test_exec_inline
    Dir.mktmpdir do |dir|
      dir = File.realpath(dir)

      File.write("#{dir}/Gemfile", "")
      File.write("#{dir}/Gemfile.lock", "")
      File.write("#{dir}/ruby-executable", "#!/usr/bin/ruby\n")
      FileUtils.chmod 0755, "#{dir}/ruby-executable"

      Paperback::Environment.expects(:activate)

      Kernel.expects(:load).with do |path|
        assert_equal "ruby-executable", path

        assert_equal "#{dir}/Gemfile", ENV["PAPERBACK_GEMFILE"]
        assert_equal "#{dir}/Gemfile.lock", ENV["PAPERBACK_LOCKFILE"]
        assert_equal "--disable=gems -rpaperback/runtime", ENV["RUBYOPT"]
        assert_equal File.expand_path("../lib", __dir__), ENV["RUBYLIB"]

        assert_equal "ruby-executable", $0
        assert_equal ["some", "args"], ARGV
      end

      Dir.chdir(dir) do
        catch(:exit) do
          Paperback::Command.run(%W(exec ruby-executable some args))
        end
      end
    end
  end

  def test_exec_nonruby
    Dir.mktmpdir do |dir|
      dir = File.realpath(dir)

      File.write("#{dir}/Gemfile", "")
      File.write("#{dir}/Gemfile.lock", "")
      File.write("#{dir}/shell-executable", "#!/bin/sh\n")
      FileUtils.chmod 0755, "#{dir}/shell-executable"

      Kernel.expects(:exec).with do |*command|
        assert_equal [["shell-executable", "shell-executable"], "some", "args"], command

        assert_equal "#{dir}/Gemfile", ENV["PAPERBACK_GEMFILE"]
        assert_equal "#{dir}/Gemfile.lock", ENV["PAPERBACK_LOCKFILE"]
        assert_equal "--disable=gems -rpaperback/runtime", ENV["RUBYOPT"]
        assert_equal File.expand_path("../lib", __dir__), ENV["RUBYLIB"]
      end.throws(:exit)

      Dir.chdir(dir) do
        catch(:exit) do
          Paperback::Command.run(%W(exec shell-executable some args))
        end
      end
    end
  end
end
