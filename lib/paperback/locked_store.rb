class Paperback::LockedStore
  attr_reader :inner

  def initialize(inner)
    @inner = inner
    @locked_versions = {}

    @lib_cache = nil
    @full_cache = false
  end

  def root
    @inner.root
  end

  def prepare(locks)
    return if @full_cache

    @lib_cache ||= {}

    inner_versions = {}
    locks.each do |name, version|
      next if version.is_a?(Paperback::StoreGem)
      inner_versions[name] = version
    end

    g = Hash.new { |h, k| h[k] = gem(k, inner_versions[k]) }
    @inner.libs_for_gems(inner_versions) do |name, version, file, subdir|
      (@lib_cache[file] ||= []) << [g[name], subdir]
    end
  end

  def lock(locks)
    @locked_versions = locks.dup
    prepare(locks)
    @full_cache = true
  end

  def locked?(gem)
    @locked_versions[gem.name] == gem.version
  end

  def locked_gems
    @locked_versions.values.grep(Paperback::StoreGem)
  end

  def gem(name, version)
    if @locked_versions[name] == version
      @inner.gem(name, version)
    else
      locked_gems.find { |g| g.name == name && g.version == version }
    end
  end

  def gems_for_lib(file)
    if @lib_cache
      if c = @lib_cache[file]
        c.each { |gem, subdir| yield gem, subdir }
        return
      end
    end

    unless @full_cache
      @inner.gems_for_lib(file) do |gem, subdir|
        yield gem, subdir if locked?(gem)
      end
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
