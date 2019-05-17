# frozen_string_literal: true

class Gel::Config
  def initialize
    @root = File.expand_path("~/.config/gel")
    @path = File.join(@root, "config")
    @config = nil
  end

  def config
    @config ||= read
  end

  def all
    config
  end

  def config_exists?
    File.exist?(@path)
  end

  def config_file
    File.read(@path)
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
    result = {}
    if config_exists?
      context = nil
      config_file.each_line do |line|
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
    result
  end

  def write(data)
    Dir.mkdir(@root) unless Dir.exist?(@root)

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
