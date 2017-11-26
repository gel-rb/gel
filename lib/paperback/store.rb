require "pstore"

class Paperback::Store
  attr_reader :root

  def initialize(root)
    @root = root
    @primary_pstore = PStore.new("#{root}/.pstore")
    @bin_pstore = PStore.new("#{root}/bin.pstore")
    @lib_pstore = PStore.new("#{root}/lib.pstore")
  end

  def add_gem(name, version, bindir, require_paths)
    name = name.to_s
    version = version.to_s
    bindir = bindir.to_s
    require_paths = require_paths.map(&:to_s)

    primary_pstore(true) do |st|
      h = st[name] || {}
      raise "already installed" if h[version]
      d = {}
      d[:bindir] = bindir unless bindir == "bin"
      d[:require_paths] = require_paths unless require_paths == ["lib"]
      h[version] = d
      st[name] = h

      yield if block_given?
    end
  end

  def add_lib(name, version, files)
    name = name.to_s
    version = version.to_s
    files = files.map(&:to_s)

    lib_pstore(true) do |st|
      files.each do |file|
        h = st[file] || {}
        d = h[name] || []
        raise "already installed" if d.include?(version)
        d << version
        h[name] = d
        st[file] = h
      end
    end
  end

  def gem_info(name, version)
    primary_pstore do |st|
      return unless h = st[name]
      return unless d = h[version]
      d = d.dup
      d[:bindir] = "bin" unless d.key?(:bindir)
      d[:require_paths] = ["lib"] unless d.key?(:require_paths)
      d
    end
  end

  def gems_for_lib(file)
    lib_pstore do |st|
      if h = st[file]
        h.flat_map do |name, versions|
          versions.map do |version|
            [name, version]
          end
        end
      else
        []
      end
    end
  end

  def each
    primary_pstore do |st|
      st.roots.each do |name|
        st[name].each do |version, info|
          yield name, version, info
        end
      end
    end
  end

  private

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
end
