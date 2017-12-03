class Paperback::Environment
  IGNORE_LIST = %w(bundler)

  class << self
    attr_reader :store
    attr_accessor :gemfile
  end
  self.gemfile = nil

  def self.activated_gems
    @activated ||= {}
  end

  def self.activate(store)
    @store = store
  end

  def self.search_upwards(name, dir = Dir.pwd)
    file = File.join(dir, name)
    until File.exist?(file)
      next_dir = File.dirname(dir)
      return nil if next_dir == dir
    end
    file
  end

  def self.load_gemfile(path = nil)
    path ||= ENV["PAPERBACK_GEMFILE"]
    path ||= search_upwards("Gemfile")
    path ||= "Gemfile"

    raise "No Gemfile found in #{path.inspect}" unless File.exist?(path)

    content = File.read(path)
    @gemfile = Paperback::GemfileParser.parse(content, path, 1)
  end

  def self.require_groups(*groups)
    gems = @gemfile.gems
    groups = [:default] if groups.empty?
    groups = groups.map(&:to_s)
    gems = gems.reject { |g| ((g[2][:groups] || [:default]).map(&:to_s) & groups).empty? }
    @gemfile.autorequire(self, gems)
  end

  def self.gem(name, *requirements)
    return if IGNORE_LIST.include?(name)

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

  def self.gem_has_file?(gem_name, path)
    @store.gems_for_lib(path) do |gem, subdir|
      if gem.name == gem_name && gem == activated_gems[gem_name]
        return gem.path(path, subdir)
      end
    end

    false
  end

  def self.scoped_require(gem_name, path)
    if full_path = gem_has_file?(gem_name, path)
      require full_path
    else
      raise LoadError, "No file #{path.inspect} found in gem #{gem_name.inspect}"
    end
  end

  def self.resolve_gem_path(path)
    return path if path.start_with?("/")

    if @store
      result = nil
      @store.gems_for_lib(path) do |gem, subdir|
        result = [gem, subdir]
        break
      end

      if result
        activate_gem result[0]
        return result[0].path(path, result[1])
      end
    end

    path
  end
end
