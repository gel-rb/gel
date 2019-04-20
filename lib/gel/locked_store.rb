# frozen_string_literal: true

class Gel::LockedStore
  attr_reader :inner

  def initialize(inner)
    @inner = inner
    @locked_versions = nil

    @lib_cache = Hash.new { |h, k| h[k] = [] }
    @full_cache = false
  end

  def paths
    @inner.paths
  end

  def root
    @inner.root
  end

  def inspect
    content = @locked_versions.map { |name, version| "#{name}=#{version.is_a?(String) ? version : version.root}" }
    content = ["(none)"] if content.empty?
    content.sort!

    "#<#{self.class} inner=#{@inner.inspect} locks=#{content.join(",")}>"
  end

  def prepare(locks)
    return if @full_cache

    inner_versions = {}
    locks.each do |name, version|
      if version.is_a?(Gel::StoreGem)
        version.libs do |file, subdir|
          @lib_cache[file] << [version, subdir]
        end
      else
        inner_versions[name] = version
      end
    end

    g = @inner.gems(inner_versions)
    @inner.libs_for_gems(inner_versions) do |name, version, subs|
      subs.each do |subdir, files|
        v = [g[name], subdir]
        files.each do |file|
          @lib_cache[file] << v
        end
      end
    end
  end

  def lock(locks)
    @locked_versions = locks.dup
    prepare(locks)
    @full_cache = true
  end

  def locked?(gem)
    !@locked_versions || @locked_versions[gem.name] == gem.version
  end

  def locked_gems
    @locked_versions ? @locked_versions.values.grep(Gel::StoreGem) : []
  end

  def gem(name, version)
    if !@locked_versions || @locked_versions[name] == version
      @inner.gem(name, version)
    else
      locked_gems.find { |g| g.name == name && g.version == version }
    end
  end

  def gems(name_version_pairs)
    r = @inner.gems(name_version_pairs)
    locked_gems.each do |g|
      r[g.name] = g
    end
    r
  end

  def gems_for_lib(file)
    if (c = @lib_cache.fetch(file, nil))
      c.each { |gem, subdir| yield gem, subdir }
      return
    end

    hits = []
    unless @full_cache
      @inner.gems_for_lib(file) do |gem, subdir|
        if locked?(gem)
          hits << [gem, subdir]
          yield gem, subdir
        end
      end
    end

    locked_gems.each do |gem|
      if File.exist?(gem.path(file) + ".rb")
        hits << [gem, nil]
        yield gem, nil
      end
    end

    @lib_cache[file] = hits
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
      yield gem if !gem_name || gem.name == gem_name
    end
  end
end
