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

  def locked_gems
    @locked_versions.values.grep(Paperback::StoreGem)
  end

  def gem(name, version)
    if @locked_versions[gem.name] == version
      @inner.gem(name, version)
    else
      locked_gems.find { |g| g.name == name && g.version == version }
    end
  end

  def gems_for_lib(file)
    @inner.gems_for_lib(file) do |gem, subdir|
      yield gem, subdir if locked?(gem)
    end

    locked_gems.each do |gem|
      yield gem, nil if File.exist?(gem.path(file) + ".rb")
    end
  end

  def each(gem_name = nil)
    return enum_for(__callee__, gem_name) unless block_given?

    list = locked_gems

    @inner.each(gem_name) do |gem|
      next unless locked?(gem)
      yield gem
      list.delete gem
    end

    list.each do |gem|
      yield gem
    end
  end
end
