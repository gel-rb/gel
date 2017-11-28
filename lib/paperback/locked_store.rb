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

  def locked?(gem)
    @locked_versions[gem.name] == gem.version
  end

  def gem(name, version)
    @inner.gem(name, version) if @locked_versions[gem.name] == version
  end

  def gems_for_lib(file)
    @inner.gems_for_lib(file) do |gem, subdir|
      yield gem, subdir if locked?(gem)
    end
  end

  def each(gem_name = nil)
    return enum_for(__callee__, gem_name) unless block_given?

    @inner.each(gem_name) do |gem|
      yield gem if locked?(gem)
    end
  end
end
