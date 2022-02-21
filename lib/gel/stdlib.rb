# frozen_string_literal: true

require "rbconfig"

class Gel::Stdlib
  PATHS = $LOAD_PATH & (RbConfig::CONFIG.values + [File.expand_path("../../slib", __dir__)])

  def self.instance
    @instance ||= new
  end

  def initialize
    @files = {}
    @active = {}

    PATHS.each do |path|
      path_prefix = Gel::Util.join(path, "")
      exclusions = PATHS.
        select { |nested| nested.start_with?(path_prefix) }.
        map { |x| Gel::Util.join(x, "")[path_prefix.size..-1] }
      exclusions << "rubygems" << "bundler" unless path == File.expand_path("../../slib", __dir__)

      entry_for_ext = Hash.new { |h, k| h[k] = [k, path].freeze }
      single_entry_for_ext = Hash.new { |h, k| h[k] = [entry_for_ext[k]].freeze }

      Gel::Util.loadable_files(path).each do |file|
        next if file != "rubygems/deprecate.rb" && exclusions.any? { |exc| file.start_with?(exc) }

        basename, ext = Gel::Util.split_filename_for_require(file)

        basename = -basename
        ext = -ext

        if @files.key?(basename)
          @files[basename] = @files[basename].dup << entry_for_ext[ext]
        else
          @files[basename] = single_entry_for_ext[ext]
        end
      end
    end

    @builtins = $LOADED_FEATURES.grep(/\A[^\/\\]+\z/)
    @builtins += @builtins.map { |s| Gel::Util.split_filename_for_require(s).first }

    $LOADED_FEATURES.each do |feat|
      @files.each do |basename, pairs|
        next unless feat.include?(basename)
        pairs.each do |ext, path|
          if feat == Gel::Util.join(path, basename + ext)
            @active[basename] = @active[-(basename + ext)] = true
          end
        end
      end
    end
  end

  def activate(path)
    @active[path] = true
  end

  def active?(path)
    @active[path]
  end

  def resolve(search_name, search_ext)
    if @builtins.include?(search_name)
      if search_ext
        full_name = search_name + search_ext
        if @builtins.include?(full_name)
          return search_name
        end
      else
        return search_name
      end
    end

    @files[search_name]&.each do |ext, path|
      return Gel::Util.join(path, search_name) if Gel::Util.ext_matches_requested?(ext, search_ext)
    end

    nil
  end
end
