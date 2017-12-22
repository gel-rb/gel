require "pstore"

class Paperback::Store
  attr_reader :root

  def initialize(root)
    @root = File.expand_path(root)
    @primary_pstore = PStore.new("#{root}/.pstore", true)
    @bin_pstore = PStore.new("#{root}/bin.pstore", true)
    @lib_pstore = PStore.new("#{root}/lib.pstore", true)
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

    primary_pstore(true) do |st|
      h = st[name] || {}
      raise "already installed" if h[version]
      d = {}
      d[:bindir] = bindir unless bindir == "bin"
      d[:executables] = executables unless executables.empty?
      d[:require_paths] = require_paths unless require_paths == ["lib"]
      d[:dependencies] = dependencies unless dependencies.empty?
      d[:extensions] = extensions if extensions
      h[version] = d
      h.keys.sort_by { |v| Paperback::Support::GemVersion.new(v) }.reverse_each do |v|
        h[v] = h.delete(v)
      end
      st[name] = h

      yield if block_given?
    end
  end

  def add_lib(name, version, files)
    name = normalize_string(name)
    version = version.is_a?(Array) ? version.map { |v| normalize_string(v) } : normalize_string(version)
    files = files.map { |v| normalize_string(v) }

    lib_pstore(true) do |st|
      files.each do |file|
        h = st[file] || {}
        d = h[name] || []
        raise "already installed" if d.include?(version)
        d << version
        h[name] = d.sort_by { |v,_| Paperback::Support::GemVersion.new(v) }.reverse
        st[file] = h
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

    primary_pstore do |st|
      name_version_pairs.each do |name, version|
        x = st[name]
        x &&= x[version]
        result[name] = x if x
      end
    end

    result.each do |k, v|
      result[k] = _gem(k, name_version_pairs[k], v)
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
    lib_pstore do |st|
      st.roots.each do |file|
        h = st[file]
        h.each do |fname, fversions|
          next unless version = versions[fname]
          fversions.each do |fversion|
            if fversion.is_a?(Array)
              fversion, subdir = fversion
              yield fname, fversion, file, subdir if fversion == version
            else
              yield fname, fversion, file if fversion == version
            end
          end
        end
      end
    end
  end

  def gems_for_lib(file)
    lib_pstore do |st|
      if h = st[file]
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

    primary_pstore do |st|
      gems = gem_name ? [gem_name] : st.roots
      gems.each do |name|
        next unless st[name]
        st[name].each do |version, info|
          yield _gem(name, version, info)
        end
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
    primary_pstore do |st|
      return unless h = st[name]
      return unless d = h[version]
      d
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

  def primary_pstore(write = false)
    @primary_pstore.transaction(!write) do
      yield @primary_pstore
    end
  end

  def lib_pstore(write = false)
    @lib_pstore.transaction(!write) do
      yield @lib_pstore
    end
  end

  def bin_pstore(write = false)
    @bin_pstore.transaction(!write) do
      yield @bin_pstore
    end
  end

  # Almost every string we store is pure ASCII, and binary strings
  # marshal better.
  def normalize_string(str)
    str = str.to_s
    str = str.b if str.ascii_only?
    str
  end
end
