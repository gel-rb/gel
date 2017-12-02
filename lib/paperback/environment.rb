class Paperback::Environment
  def self.activated_gems
    @activated ||= {}
  end

  def self.activate(store)
    @store = store
  end

  def self.gem(name, *requirements)
    requirements = Paperback::Support::GemRequirement.new(requirements)

    if existing = activated_gems[name]
      if existing.satisfies?(requirements)
        return
      else
        raise "already loaded gem #{name} #{existing.version}, which is incompatible with: #{requirements}"
      end
    end

    gem = @store.each(name).find do |g|
      g.satisfies?(requirements)
    end

    if gem
      activate_gem gem
    else
      raise "unable to satisfy requirements for gem #{name}: #{requirements}"
    end
  end

  def self.activate_gem(gem)
    return if activated_gems[gem.name] && activated_gems[gem.name].version == gem.version
    raise "already activated #{gem.name} #{activated_gems[gem.name].version}" if activated_gems[gem.name]

    gem.dependencies.each do |dep, reqs|
      self.gem(dep, *reqs.map { |(qual, ver)| "#{qual} #{ver}" })
    end

    lib_dirs = gem.require_paths
    @store.prepare gem.name => gem.version

    activated_gems[gem.name] = gem
    $:.concat lib_dirs
  end

  def self.require(path)
    @store.gems_for_lib(path) do |gem, subdir|
      activate_gem gem
      return super(gem.path(path, subdir))
    end

    super
  end
end
