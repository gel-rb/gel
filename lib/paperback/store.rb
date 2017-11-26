require "pstore"

class Paperback::Store
  attr_reader :root

  def initialize(root)
    @root = root
    @pstore = PStore.new("#{root}/.pstore")
  end

  def add_gem(name, version, bindir, require_paths)
    name = name.to_s
    version = version.to_s
    bindir = bindir.to_s
    require_paths = require_paths.map(&:to_s)

    pstore(true) do |st|
      h = st[name] || {}
      raise "already installed" if h[version]
      d = {}
      d[:bindir] = bindir unless bindir == "bin"
      d[:require_paths] = require_paths unless require_paths == ["lib"]
      h[version] = d
      st[name] = h
    end
  end

  def gem_info(name, version)
    pstore do |st|
      return unless h = st[name]
      return unless d = h[version]
      d = d.dup
      d[:bindir] = "bin" unless d.key?(:bindir)
      d[:require_paths] = ["lib"] unless d.key?(:require_paths)
      d
    end
  end

  def each
    pstore do |st|
      st.roots.each do |name|
        st[name].each do |version, info|
          yield name, version, info
        end
      end
    end
  end

  private

  def pstore(write = false)
    @pstore.transaction(!write) do
      yield @pstore
    end
  end
end
