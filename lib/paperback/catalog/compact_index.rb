require "set"
require "fileutils"

require_relative "../pinboard"

class Paperback::Catalog::CompactIndex
  def initialize(uri, uri_identifier, httpool:)
    @uri = uri
    @uri_identifier = uri_identifier
    @httpool = httpool

    @gem_tokens = Hash.new("NONE")
    @needs_update = true
    @updating = false
    @active_gems = Set.new

    @gem_info = Hash.new { |h, k| h[k] = {} }
  end

  def update
    return false unless @needs_update
    @needs_update = false
    @updating = true

    pinboard.async_file(uri("versions"), tail: true) do |f|
      new_tokens = {}

      started = false
      f.each_line do |line|
        unless started
          started ||= line == "---\n"
          next
        end
        line.chop!

        name, _versions, token = line.split
        new_tokens[name] = token
      end

      @gem_tokens.update new_tokens
      @updating = false

      @active_gems.each do |name|
        refresh_gem(name)
      end
    end

    true
  end

  def refresh_gem(gem_name)
    already_active = !@active_gems.add?(gem_name)

    pinboard.async_file(uri("info", gem_name), token: @gem_tokens[gem_name], only_updated: already_active) do |f|
      dependency_names = Set.new

      started = false
      f.each_line do |line|
        unless started
          started ||= line == "---\n"
          next
        end
        line.chop!

        version, rest = line.split(" ", 2)
        deps, attrs = rest.split("|", 2)

        deps = deps.split(",").map do |entry|
          key, constraints = entry.split(":", 2)
          constraints = constraints.split("&")
          [key, constraints]
        end

        attrs = attrs.split(",").map do |entry|
          key, value = entry.split(":", 2)
          [key.to_sym, value]
        end.to_h

        attrs[:dependencies] = deps

        deps.each do |name, _|
          dependency_names << name
        end

        @gem_info[gem_name][version] = attrs
      end

      dependency_names.each do |dep|
        refresh_gem dep
      end
    end
  end

  private

  def pinboard
    @pinboard ||=
      begin
        FileUtils.mkdir_p(pinboard_dir)
        Paperback::Pinboard.new(pinboard_dir, httpool: @httpool)
      end
  end

  def pinboard_dir
    File.expand_path("~/.cache/paperback/index/#{@uri_identifier}")
  end

  def uri(*parts)
    URI(File.join(@uri.to_s, *parts))
  end
end
