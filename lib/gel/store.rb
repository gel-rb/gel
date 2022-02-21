# frozen_string_literal: true

require_relative "db"

class Gel::Store
  attr_reader :root
  attr_reader :monitor

  def initialize(root)
    @root = File.realpath(File.expand_path(root))
    @primary_db = Gel::DB.new(root, "store")
    @lib_db = Gel::DB.new(root, "libs")
    @rlib_db = Gel::DB::File.new(root, "meta")

    @monitor = Monitor.new
  end

  def marshal_dump
    @root
  end

  def marshal_load(v)
    initialize(v)
  end

  def stub_set
    @stub_set ||= Gel::StubSet.new(@root)
  end

  def paths
    [@root.dup]
  end

  def add_gem(name, version, bindir, executables, require_paths, dependencies, required_ruby, extensions)
    name = normalize_string(name)
    version = normalize_string(version)
    bindir = normalize_string(bindir)
    executables = executables.map { |v| normalize_string(v) }
    require_paths = require_paths.map { |v| normalize_string(v) }
    _dependencies = {}
    dependencies.each do |key, dep|
      _dependencies[normalize_string(key)] = dep.map { |pair| pair.map { |v| normalize_string(v) } }
    end
    required_ruby = required_ruby&.map { |pair| normalize_string(pair.join(" ")) }
    required_ruby = nil if required_ruby == [">= 0"]
    dependencies = _dependencies
    extensions = !!extensions

    @primary_db.writing do
      vs = @primary_db["v/#{name}"] || []
      raise "already installed" if vs.include?(version)
      vs << version
      vs.sort_by! { |v| Gel::Support::GemVersion.new(v) }
      vs.reverse!
      @primary_db["v/#{name}"] = vs

      d = {}
      d[:bindir] = bindir unless bindir == "bin"
      d[:executables] = executables unless executables.empty?
      d[:require_paths] = require_paths unless require_paths == ["lib"]
      d[:dependencies] = dependencies unless dependencies.empty?
      d[:extensions] = extensions if extensions
      d[:ruby] = required_ruby if required_ruby && !required_ruby.empty?
      @primary_db["i/#{name}/#{version}"] = d

      yield if block_given?
    end
  end

  def remove_gem(name, version)
    @primary_db.writing do
      info = @primary_db["i/#{name}/#{version}"]

      if info[:extensions]
        yield gem_root(name, version), extension_path(name, version)
      else
        yield gem_root(name, version)
      end

      @lib_db.writing do
        @rlib_db.writing do |rst|
          ls = @rlib_db.delete("#{name}-#{version}") || []

          ls.each do |_, sls|
            sls.each do |file|
              h = @lib_db[file] || {}
              d = h[name] || []
              d.delete_if { |dv| dv == version || (dv.is_a?(Array) && dv.first == version) }
              h.delete(name) if d.empty?
              if h.empty?
                @lib_db.delete(file)
              else
                @lib_db[file] = h
              end
            end
          end
        end
      end

      @primary_db.delete("i/#{name}/#{version}")

      vs = @primary_db["v/#{name}"] || []
      vs.delete(version)
      if vs.empty?
        @primary_db.delete("v/#{name}")
      else
        @primary_db["v/#{name}"] = vs
      end
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
          h[name] = d.sort_by.with_index { |(v, _), idx| [Gel::Support::GemVersion.new(v), -idx] }.reverse
          @lib_db[file] = h
        end

        v, d, e = version
        k = e ? [d, e] : d
        ls = @rlib_db["#{name}-#{v}"] || []
        unless sls = ls.assoc(k)
          sls = [k, []]
          ls << sls
        end
        sls.last.concat files
        @rlib_db["#{name}-#{v}"] = ls
      end
    end
  end

  def gem?(name, version, _platform = nil)
    !!gem(name, version)
  end

  def gem(name, version)
    info = gem_info(name, version)
    info && _gem(name, version, info)
  end

  def gems(name_version_pairs)
    result = {}

    @primary_db.reading do
      name_version_pairs.each do |name, version|
        if info = gem_info(name, version)
          if g = _gem(name, version, info)
            result[name] = g
          end
        end
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
    @primary_db.reading do
      versions = versions.select do |name, version|
        @primary_db.key?("i/#{name}/#{version}")
      end
    end

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
            version, subdir, ext = version
            if g = gem(name, version)
              yield g, subdir, ext
            end
          else
            if g = gem(name, version)
              yield g
            end
          end
        end
      end
    end
  end

  def each(gem_name = nil, &block)
    return enum_for(__callee__, gem_name) unless block_given?

    iterate_for_gem = lambda do |gem_name|
      @primary_db["v/#{gem_name}"]&.each do |version|
        if info = @primary_db["i/#{gem_name}/#{version}"]
          if g = _gem(gem_name, version, info)
            yield g
          end
        end
      end
    end

    @primary_db.reading do
      if gem_name
        iterate_for_gem.call(gem_name)
      else
        @primary_db.each_key do |k|
          iterate_for_gem.call($1) if k =~ /\Av\/(.*)\z/
        end
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
    g = Gel::StoreGem.new(gem_root(name, version), name, version, extensions, info)
    g if g.compatible_ruby?
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
