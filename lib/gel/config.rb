# frozen_string_literal: true

require_relative "util"

##
# Reads an optional config file ~/.config/gel/config and injects
# authorization info from the environment $GEL_AUTH.
#
# Environment format:
#
#     GEL_AUTH="https://user@pass:host1/ https://user@pass:host2/"
#
# Config file format:
#
#     # comment:
#     context-name: # where context-name in [build]
#       key: val
#
#     key: val
#
# Example:
#
#     build:
#       nokogiri: --libdir=blah
#
#     rails-assets.org: username:password
#
#     ---
#
#     GEL_AUTH="https://user@pass:private-gem-server.local"

class Gel::Config
  def initialize(root_path = "~/.config/gel")
    @root = File.expand_path(root_path)
    @path = File.join(@root, "config")
    @config = nil
  end

  def config
    @config ||= read
  end

  def [](group = nil, key)
    (group ? (config[group.to_s] || {}) : config)[key.to_s]
  end

  def []=(group = nil, key, value)
    if group.nil?
      group, key = key.split(".", 2)
    end

    (group ? (config[group.to_s] ||= {}) : config)[key.to_s] = value.to_s

    write(config)
  end

  private

  def read
    result = {}
    if File.exist?(@path)
      context = nil
      File.read(@path).each_line do |line|
        line.chomp!
        if line =~ /\A(\S[^:]*):\z/
          context = result[$1] = {}
        elsif line =~ /\A  ([^:]*): (.*)\z/
          context[$1] = $2
        elsif line =~ /\A([^:]*): (.*)\z/
          result[$1] = $2
        elsif line =~ /\A\s*(?:#|\z)/
          # comment / empty
        else
          raise Gel::Error::UnexpectedConfigError.new(line: line)
        end
      end
    end

    # GEL_AUTH = "http://username:password@host http://username:password@host"
    if auths = ENV["GEL_AUTH"] then
      auths.split.each do |auth|
        auth = URI(auth)
        result[auth.host] = auth.userinfo
      end
    end

    result
  end

  def write(data)
    Gel::Util.mkdir_p(@root)

    tempfile = File.join(@root, ".config.#{Process.pid}")
    File.open(tempfile, "w", 0644) do |f|
      data.each do |key, value|
        next if value.is_a?(Hash)
        f.puts("#{key}: #{value}")
      end

      data.each do |key, value|
        next unless value.is_a?(Hash)
        f.puts
        f.puts("#{key}:")
        value.each do |subkey, subvalue|
          f.puts("  #{subkey}: #{subvalue}")
        end
      end
    end

    File.rename(tempfile, @path)
  ensure
    File.unlink(tempfile) if File.exist?(tempfile)
  end
end
