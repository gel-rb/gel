# frozen_string_literal: true

require "yaml"

class Gel::Config
  def initialize(root)
    @root = File.expand_path(root)
    @path = File.join(@root, "config")
    @config = nil
  end

  def config
    @config ||= read
  end

  def [](group = nil, key)
    if group.nil?
      group, key = key.split(".", 2)
    end

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
    if File.exist?(@path)
      YAML.safe_load(File.read(@path))
    else
      {}
    end
  end

  def write(data)
    Dir.mkdir(@root) unless Dir.exist?(@root)

    tempfile = File.join(@root, ".config.#{Process.pid}")
    File.open(tempfile, "w", 0644) do |f|
      f.write(YAML.dump(data))
    end

    File.rename(tempfile, @path)
  ensure
    File.unlink(tempfile) if File.exist?(tempfile)
  end
end
