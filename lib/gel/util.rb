# frozen_string_literal: true

module Gel::Util
  extend self

  def search_upwards(name, dir = Dir.pwd)
    until (file = File.join(dir, name)) && File.exist?(file)
      next_dir = File.dirname(dir)
      return nil if next_dir == dir
      dir = next_dir
    end
    file
  end

  def mkdir_p(path)
    return if Dir.exist?(path)

    paths_to_create = []

    until Dir.exist?(path)
      paths_to_create.unshift path
      path = File.dirname(path)
    end

    paths_to_create.each do |path|
      Dir.mkdir(path)
    rescue Errno::EEXIST
    end

    true
  end

  def rm_rf(path)
    return unless File.exist?(path)

    require "fileutils"
    FileUtils.rm_rf(path)
  end

  def relative_path(from, to)
    from_parts = path_parts(from)
    to_parts = path_parts(to)

    while from_parts.first && from_parts.first == to_parts.first
      from_parts.shift
      to_parts.shift
    end

    until from_parts.empty?
      from_parts.shift
      to_parts.unshift ".."
    end

    to_parts.join(File::SEPARATOR)
  end

  private

  def path_parts(path)
    if File::ALT_SEPARATOR
      path.split(Regexp.union(File::SEPARATOR, File::ALT_SEPARATOR))
    else
      path.split(File::SEPARATOR)
    end
  end
end
