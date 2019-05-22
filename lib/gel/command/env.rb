# frozen_string_literal: true

class Gel::Command::Env < Gel::Command
  def run(command_line)
    MarkdownFormatter.format(metadata)
  end

  private

  def metadata
    {
      "Gel" => gel_envs,
      "User" => user_envs,
      "Ruby" => ruby_envs,
      "Relevant Files" => RELEVANT_FILES,
    }
  end

  module MarkdownFormatter
    def self.format(data)
      data.each do |section, value_hash|
        puts "\n## #{section}"
        value_hash.each do |name, value|

          if value.is_a?(RelevantFile)
            print_codeblock(name, value)
          else
            print_code_in_list(name, value)
          end
        end
      end
    end

    def self.print_code_in_list(name, value)
      if !value.empty?
        puts "- `#{name}`: `#{value}`"
      end
    end

    def self.print_codeblock(name, content)
      puts "`#{name}`"
      puts "\n```"
      puts content
      puts "```\n"
    end
  end
  private_constant :MarkdownFormatter

  USER_HOME = begin
    require "etc"
    File.expand_path(Dir.home(Etc.getlogin))
  end
  private_constant :USER_HOME

  class RelevantFile
    def initialize(path)
      @path = path
    end

    def to_s
      IO.read(path)
    end

    private
    attr_reader :path
  end
  private_constant :RelevantFile

  RELEVANT_FILES = Dir[
    "#{USER_HOME}/.config/gel/config",
    "Gemfile",
    "Gemfile.lock",
    "*.gemspec",
  ].compact.map { |path| [path, RelevantFile.new(path)] }.to_h
  private_constant :RELEVANT_FILES

  def env_fetch(key, fallback = nil)
    ENV.fetch(key) { fallback }
  end

  def gel_envs
    {
      "GEL_VERSION": Gel::VERSION,
    }
  end

  def user_envs
    {
      SHELL: env_fetch("SHELL"),
    }
  end

  def ruby_envs
    {
      GEM_HOME: env_fetch("GEM_HOME"),
      GEM_PATH: env_fetch("GEM_PATH"),
      GEM_ROOT: env_fetch("GEM_ROOT"),
      RUBY_ENGINE: env_fetch("RUBY_ENGINE"),
      RUBY_ENGINE_VERSION: env_fetch("RUBY_ENGINE_VERSION", RUBY_ENGINE_VERSION),
      RUBYOPT: env_fetch("RUBYOPT"),
      RUBY_ROOT: env_fetch("RUBY_ROOT"),
      RUBY_VERSION: env_fetch("RUBY_VERSION", RUBY_VERSION),
    }
  end
end
