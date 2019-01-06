# frozen_string_literal: true

require_relative "db"

class Paperback::Store
  attr_reader :root

  def initialize(root)
    @root = File.realpath(File.expand_path(root))
    @primary_db = Paperback::DB.new(root, "store")
    @lib_db = Paperback::DB.new(root, "libs")
    @rlib_db = Paperback::DB::File.new(root, "meta")
  end

  def paths
    [@root.dup]
  end

  def add_gem(name, version, bindir, executables, require_paths, dependencies, extensions)
    name = normalize_string(name)
    version = normalize_string(version)
    bindir = normalize_string(bindir)
    executables = executables.map { |v| normalize_string(v) }
    require_paths = require_paths.map { |v| normalize_string(v) }
    _dependencies = {}
    dependencies.each do |key, dep|
      _dependencies[normalize_string(key)] = dep.map { |pair| pair.map { |v| normalize_string(v) } }
    end
    dependencies = _dependencies
    extensions = !!extensions

    @primary_db.writing do
      vs = @primary_db["v/#{name}"] || []
      raise "already installed" if vs.include?(version)
      vs << version
      vs.sort_by! { |v| Paperback::Support::GemVersion.new(v) }
      vs.reverse!
      @primary_db["v/#{name}"] = vs

      d = {}
      d[:bindir] = bindir unless bindir == "bin"
      d[:executables] = executables unless executables.empty?
      d[:require_paths] = require_paths unless require_paths == ["lib"]
      d[:dependencies] = dependencies unless dependencies.empty?
      d[:extensions] = extensions if extensions
      @primary_db["i/#{name}/#{version}"] = d

      yield if block_given?
    end
  end

  def add_lib(name, version, files)
    name = normalize_string(name)
    version = version.is_a?(Array) ? version.map { |v| normalize_string(v) } : normalize_string(version)
    files = files.map { |v| normalize_string(v) }

    @lib_db.writing do
      @rlib_db.writing do |rst|
        files.each do |file|
          h = @lib_db[file] || {}
          d = h[name] || []
          raise "already installed" if d.include?(version)
          d << version
          h[name] = d.sort_by { |v, _| Paperback::Support::GemVersion.new(v) }.reverse
          @lib_db[file] = h
        end

        v, d = version
        ls = @rlib_db["#{name}-#{v}"] || []
        unless sls = ls.assoc(d)
          sls = [d, []]
          ls << sls
        end
        sls.last.concat files
        @rlib_db["#{name}-#{v}"] = ls
      end
    end
  end

  def gem?(name, version, _platform = nil)
    !!gem_info(name, version)
  end

  def gem(name, version)
    info = gem_info(name, version)
    info && _gem(name, version, info)
  end

  def gems(name_version_pairs)
    result = {}

    name_version_pairs.each do |name, version|
      if info = gem_info(name, version)
        result[name] = _gem(name, version, info)
      end
    end

    result
  end

  def gem_root(name, version)
    "#{@root}/gems/#{name}-#{version}"
  end

  def extension_path(name, version)
    "#{@root}/ext/#{name}-#{version}"
  end

  def prepare(versions)
  end

  def libs_for_gems(versions)
    @rlib_db.reading do
      versions.each do |name, version|
        if libs = @rlib_db["#{name}-#{version}"]
          yield name, version, libs
        end
      end
    end
  end

  def gems_for_lib(file)
    if h = @lib_db[file]
      h.each do |name, versions|
        versions.each do |version|
          if version.is_a?(Array)
            version, subdir = version
            yield gem(name, version), subdir
          else
            yield gem(name, version)
          end
        end
      end
    end
  end

  def each(gem_name = nil)
    return enum_for(__callee__, gem_name) unless block_given?

    if gem_name
      @primary_db.reading do
        return unless vs = @primary_db["v/#{gem_name}"]
        vs.each do |version|
          if info = @primary_db["i/#{gem_name}/#{version}"]
            yield _gem(gem_name, version, info)
          end
        end
      end
    else
      gem_names = []
      @primary_db.each_key do |k|
        gem_names << $1 if k =~ /\Av\/(.*)\z/
      end

      block = Proc.new
      gem_names.each do |n|
        each(n, &block)
      end
    end
  end

  def inspect
    content = each.map { |g| "#{g.name}-#{g.version}" }
    content = ["(none)"] if content.empty?
    content.sort!

    "#<#{self.class} root=#{@root.inspect} content=#{content.join(",")}>"
  end

  private

  def _gem(name, version, info)
    info = inflate_info(info)
    extensions = extension_path(name, version) if info[:extensions]
    Paperback::StoreGem.new(gem_root(name, version), name, version, extensions, info)
  end

  def gem_info(name, version)
    @primary_db["i/#{name}/#{version}"]
  end

  def inflate_info(d)
    d = d.dup
    d[:bindir] = "bin" unless d.key?(:bindir)
    d[:executables] = [] unless d.key?(:executables)
    d[:require_paths] = ["lib"] unless d.key?(:require_paths)
    d[:dependencies] = {} unless d.key?(:dependencies)
    d
  end

  # Almost every string we store is pure ASCII, and binary strings
  # marshal better.
  def normalize_string(str)
    str = str.to_s
    str = str.b if str.ascii_only?
    str
  end
end
