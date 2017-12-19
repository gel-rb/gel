class Paperback::Environment
  IGNORE_LIST = %w(bundler)

  class << self
    attr_reader :store
    attr_accessor :gemfile
    attr_reader :architectures
  end
  self.gemfile = nil
  @active_lockfile = false
  @architectures = ["ruby".freeze].freeze

  def self.store_set
    list = []
    architectures.each do |arch|
      list << Paperback::MultiStore.subkey(arch, true)
      list << Paperback::MultiStore.subkey(arch, false)
    end
    list
  end

  def self.activated_gems
    @activated ||= {}
  end

  def self.open(store)
    @store = store
  end

  def self.search_upwards(name, dir = Dir.pwd)
    until (file = File.join(dir, name)) && File.exist?(file)
      next_dir = File.dirname(dir)
      return nil if next_dir == dir
      dir = next_dir
    end
    file
  end

  def self.find_gemfile(path = nil)
    if path && @gemfile && @gemfile.filename != File.expand_path(path)
      raise "Cannot activate #{path.inspect}; already activated #{@gemfile.filename.inspect}"
    end
    return @gemfile.filename if @gemfile

    path ||= ENV["PAPERBACK_GEMFILE"]
    path ||= search_upwards("Gemfile")
    path ||= "Gemfile"

    raise "No Gemfile found in #{path.inspect}" unless File.exist?(path)

    path
  end

  def self.load_gemfile(path = nil)
    return if @gemfile

    path = find_gemfile(path)

    content = File.read(path)
    @gemfile = Paperback::GemfileParser.parse(content, path, 1)
  end

  def self.lockfile_name(gemfile = self.gemfile.filename)
    ENV["PAPERBACK_LOCKFILE"] ||
      (gemfile && File.exist?(gemfile + ".lock") && gemfile + ".lock") ||
      search_upwards("Gemfile.lock") ||
      "Gemfile.lock"
  end

  def self.activate(install: false, output: nil)
    Paperback::Environment.load_gemfile
    return if @active_lockfile

    lockfile = Paperback::Environment.lockfile_name
    if File.exist?(lockfile)
      @active_lockfile = true
      loader = Paperback::LockLoader.new(lockfile)

      loader.activate(Paperback::Environment, Paperback::Environment.store.inner, install: install, output: output)
    else
      raise "No lockfile found in #{lockfile.inspect}"
    end
  end

  def self.find_executable(exe, gem_name = nil, gem_version = nil)
    @store.each(gem_name) do |g|
      next if gem_version && g.version != gem_version
      return File.join(g.root, g.bindir, exe) if g.executables.include?(exe)
    end
    nil
  end

  def self.require_groups(*groups)
    gems = @gemfile.gems
    groups = [:default] if groups.empty?
    groups = groups.map(&:to_s)
    gems = gems.reject { |g| ((g[2][:groups] || [:default]).map(&:to_s) & groups).empty? }
    @gemfile.autorequire(self, gems)
  end

  def self.gem(name, *requirements, why: nil)
    return if IGNORE_LIST.include?(name)

    requirements = Paperback::Support::GemRequirement.new(requirements)

    if existing = activated_gems[name]
      if existing.satisfies?(requirements)
        return
      else
        why = " (#{why.join("; ")})" if why && why.first
        raise "already loaded gem #{name} #{existing.version}, which is incompatible with: #{requirements}#{why}"
      end
    end

    gem = @store.each(name).find do |g|
      g.satisfies?(requirements)
    end

    if gem
      activate_gem gem, why: why
    else
      why = " (#{why.join("; ")})" if why && why.first
      raise "unable to satisfy requirements for gem #{name}: #{requirements}#{why}"
    end
  end

  def self.activate_gem(gem, why: nil)
    return if activated_gems[gem.name] && activated_gems[gem.name].version == gem.version
    raise "already activated #{gem.name} #{activated_gems[gem.name].version}" if activated_gems[gem.name]

    gem.dependencies.each do |dep, reqs|
      self.gem(dep, *reqs.map { |(qual, ver)| "#{qual} #{ver}" }, why: ["required by #{gem.name} #{gem.version}", *why])
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
    if @store && !path.start_with?("/")
      results = []
      @store.gems_for_lib(path) do |gem, subdir|
        results << [gem, subdir]
        break if activated_gems[gem.name] == gem
      end
      result = results.find { |g, _| activated_gems[g.name] == g } || results.first

      if result
        activate_gem result[0], why: ["provides #{path.inspect}"]
        return result[0].path(path, result[1])
      end
    end

    path
  end
end
