class Paperback::Environment
  def self.activated_gems
    @activated ||= {}
  end

  def self.activate(store)
    @store = store
  end

  def self.gem(name, *requirements)
    requirements = Paperback::Support::GemRequirement.new(requirements)

    if version = activated_gems[name]
      if requirements.satisfied_by?(Paperback::Support::GemVersion.new(version))
        return
      else
        raise "already loaded gem #{name} #{version}, which is incompatible with: #{requirements}"
      end
    end

    _name, version, _info = @store.each(name).find do |_name, v, _info|
      requirements.satisfied_by?(Paperback::Support::GemVersion.new(v))
    end

    if version
      activate_gem name, version
    else
      raise "unable to satisfy requirements for gem #{name}: #{requirements}"
    end
  end

  def self.activate_gem(name, version)
    return if activated_gems[name] == version
    raise "already activated #{name} #{activated_gems[name]}" if activated_gems[name]

    info = @store.gem_info(name, version)
    raise "gem #{name} #{version} not available" if info.nil?

    info[:dependencies].each do |dep, reqs|
      gem dep, *reqs.map { |(qual, ver)| "#{qual} #{ver}" }
    end

    lib_dirs = info[:require_paths].map { |s| File.expand_path(s, "#{@store.root}/gems/#{name}-#{version}/") }

    activated_gems[name] = version
    $:.concat lib_dirs
  end

  def self.require(path)
    @store.gems_for_lib(path) do |gem_name, version, subdir|
      subdir ||= @store.gem_info(gem_name, version)[:require_paths].first
      activate_gem gem_name, version
      return super("#{@store.root}/gems/#{gem_name}-#{version}/#{subdir}/#{path}")
    end

    super
  end
end
