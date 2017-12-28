require "sdbm"
require "pathname"

class Paperback::Store
  attr_reader :root

  def initialize(root)
    @root = File.realpath(File.expand_path(root))
    @primary_sdbm = SDBM.new("#{root}/store")
    @lib_sdbm = SDBM.new("#{root}/libs")
    @rlib_path = Pathname.new("#{root}/meta")
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

    primary_db(true) do |st|
      vs = st["v/#{name}"]
      vs = vs ? Marshal.load(vs) : []
      raise "already installed" if vs.include?(version)
      vs << version
      vs.sort_by! { |v| Paperback::Support::GemVersion.new(v) }
      vs.reverse!
      st["v/#{name}"] = Marshal.dump(vs)

      d = {}
      d[:bindir] = bindir unless bindir == "bin"
      d[:executables] = executables unless executables.empty?
      d[:require_paths] = require_paths unless require_paths == ["lib"]
      d[:dependencies] = dependencies unless dependencies.empty?
      d[:extensions] = extensions if extensions
      st["i/#{name}/#{version}"] = Marshal.dump(d)

      yield if block_given?
    end
  end

  def add_lib(name, version, files)
    name = normalize_string(name)
    version = version.is_a?(Array) ? version.map { |v| normalize_string(v) } : normalize_string(version)
    files = files.map { |v| normalize_string(v) }

    lib_db(true) do |st|
      rlib_db(true) do |rst|
        files.each do |file|
          h = st[file]
          h = h ? Marshal.load(h) : {}
          d = h[name] || []
          raise "already installed" if d.include?(version)
          d << version
          h[name] = d.sort_by { |v, _| Paperback::Support::GemVersion.new(v) }.reverse
          st[file] = Marshal.dump(h)
        end

        v, d = version
        f = rst.join("#{name}-#{v}")
        ls = f.exist? ? Marshal.load(f.read) : []
        unless sls = ls.assoc(d)
          sls = [d, []]
          ls << sls
        end
        sls.last.concat files
        f.binwrite Marshal.dump(ls)
      end
    end
  end

  def gem?(name, version, _platform = nil)
    !!gem_info(name, version)
  end

  def gem(name, version)
    info = gem_info(name, version)
    #raise "gem #{name} #{version} not available" if info.nil?
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
    rlib_db do |rst|
      versions.each do |name, version|
        f = rst.join("#{name}-#{version}")
        if f.exist?
          yield name, version, Marshal.load(f.binread)
        end
      end
    end
  end

  def gems_for_lib(file)
    lib_db do |st|
      if h = st[file]
        h = Marshal.load(h)
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
  end

  def each(gem_name = nil)
    return enum_for(__callee__, gem_name) unless block_given?

    if gem_name
      primary_db do |st|
        return unless vs = st["v/#{gem_name}"]
        vs = Marshal.load(vs)
        vs.each do |version|
          info = Marshal.load(st["i/#{gem_name}/#{version}"])
          yield _gem(gem_name, version, info)
        end
      end
    else
      gem_names = []
      primary_db do |st|
        st.each_key do |k|
          gem_names << $1 if k =~ /\Av\/(.*)\z/
        end
      end

      block = Proc.new
      gem_names.each do |n|
        each(n, &block)
      end
    end
  end

  private

  def _gem(name, version, info)
    info = inflate_info(info)
    extensions = extension_path(name, version) if info[:extensions]
    Paperback::StoreGem.new(gem_root(name, version), name, version, extensions, info)
  end

  def gem_info(name, version)
    primary_db do |st|
      d = st["i/#{name}/#{version}"]
      d && Marshal.load(d)
    end
  end

  def inflate_info(d)
    d = d.dup
    d[:bindir] = "bin" unless d.key?(:bindir)
    d[:executables] = [] unless d.key?(:executables)
    d[:require_paths] = ["lib"] unless d.key?(:require_paths)
    d[:dependencies] = {} unless d.key?(:dependencies)
    d
  end

  def primary_db(write = false)
    yield @primary_sdbm
  end

  def lib_db(write = false)
    yield @lib_sdbm
  end

  def rlib_db(write = false)
    @rlib_path.mkdir if write && !@rlib_path.exist?
    yield @rlib_path
  end

  # Almost every string we store is pure ASCII, and binary strings
  # marshal better.
  def normalize_string(str)
    str = str.to_s
    str = str.b if str.ascii_only?
    str
  end
end
