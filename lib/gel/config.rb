# frozen_string_literal: true

class Gel::Config
  def initialize
    @root = ENV.fetch('GEL_CONFIG') { File.expand_path("~/.config/gel") }
    @path = File.join(@root, "config")
    @config = nil
  end

  def config
    @config ||= read
  end

  def all
    config
  end

  def [](group = nil, key)
    key = "#{group}.#{key}" unless group.nil?
    config[key.downcase]
  end

  def []=(group = nil, key, value)
    key = "#{group}.#{key}" unless group.nil?
    config[key] = value.to_s
    write(config)
  end

  private

  def read
    result = {}
    if File.exist?(@path)
      File.read(@path).each_line do |line|
        line.chomp!
        key, value = line.split(':')
        next unless key
        result[key.downcase] = value&.strip
      end
    end
    result
  end

  def write(data)
    Dir.mkdir(@root) unless Dir.exist?(@root)

    tempfile = File.join(@root, ".config.#{Process.pid}")
    File.open(tempfile, "w", 0644) do |f|
      data.each { |key, value| f.puts("#{key}: #{value}") }
    end

    File.rename(tempfile, @path)
  ensure
    File.unlink(tempfile) if File.exist?(tempfile)
  end
end
