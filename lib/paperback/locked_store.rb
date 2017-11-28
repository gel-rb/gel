class Paperback::LockedStore
  attr_reader :inner

  def initialize(inner)
    @inner = inner
    @locked_versions = {}
  end

  def root
    @inner.root
  end

  def lock(locks)
    @locked_versions = locks.dup
  end

  def gem_info(name, version)
    @inner.gem_info(name, version) if @locked_versions[name] == version
  end

  def gems_for_lib(file)
    @inner.gems_for_lib(file) do |name, version, *args|
      yield name, version, *args if @locked_versions[name] == version
    end
  end

  def each(gem_name = nil)
    return enum_for(__callee__, gem_name) unless block_given?

    @inner.each(gem_name) do |name, version, info|
      yield name, version, info if @locked_versions[name] == version
    end
  end
end
