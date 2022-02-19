# frozen_string_literal: true

require "rbconfig"

module Gel::Util
  extend self

  LOADABLE_FILE_TYPES = ["rb", "so", RbConfig::CONFIG["DLEXT"], RbConfig::CONFIG["DLEXT2"]].compact.reject(&:empty?)
  LOADABLE_FILE_TYPES_EXT = LOADABLE_FILE_TYPES.map { |s| -".#{s}" }
  LOADABLE_FILE_TYPES_RE = /(?=\.#{Regexp.union LOADABLE_FILE_TYPES}\z)/
  LOADABLE_FILE_TYPES_PATTERN = "{#{LOADABLE_FILE_TYPES.join(",")}}"

  def loadable_files(dir, name = "**/*")
    range_without_prefix = (dir.size + 1)..-1
    Dir["#{dir}/#{name}.#{LOADABLE_FILE_TYPES_PATTERN}"].map do |absolute|
      absolute[range_without_prefix]
    end
  end

  def ext_matches_requested?(actual_ext, requested_ext)
    # * requested_ext.nil? => no preference (the common case)
    # * actual_ext.nil? is shorthand for '.rb'
    # * All non-.rb (i.e., compiled) extensions are treated as equivalent

    !requested_ext ||
      (!actual_ext || actual_ext == ".rb") == (requested_ext == ".rb")
  end

  def split_filename_for_require(name)
    LOADABLE_FILE_TYPES_EXT.each do |ext|
      next unless name.end_with?(ext)

      return [name[0, name.size - ext.size], ext]
    end
    [name]
  end

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
