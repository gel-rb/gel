# frozen_string_literal: true

require "rbconfig"

class Gel::Environment
  IGNORE_LIST = %w(bundler gel rubygems-update)

  class << self
    attr_reader :store
    attr_accessor :gemfile
    attr_reader :architectures
  end
  self.gemfile = nil
  @active_lockfile = false
  @architectures = [defined?(org.jruby.Ruby) ? "java" : nil, "ruby"].compact.freeze

  GEMFILE_PLATFORMS = begin
    v = RbConfig::CONFIG["ruby_version"].split(".")[0..1].inject(:+)

    # FIXME: This isn't the right condition
    if defined?(org.jruby.Ruby)
      ["jruby", "jruby_#{v}", "java", "java_#{v}"]
    else
      ["ruby", "ruby_#{v}", "mri", "mri_#{v}"]
    end
  end

  def self.platform?(platform)
    platform.nil? || architectures.include?(platform)
  end

  def self.config
    @config ||= Gel::Config.new
  end

  def self.store_set
    list = []
    architectures.each do |arch|
      list << Gel::MultiStore.subkey(arch, true)
      list << Gel::MultiStore.subkey(arch, false)
    end
    list
  end

  def self.activated_gems
    @activated ||= {}
  end

  def self.open(store)
    @store = store
  end

  def self.original_rubylib
    lib = (ENV["RUBYLIB"] || "").split(File::PATH_SEPARATOR)
    lib.delete File.expand_path("compatibility", __dir__)
    #lib.delete File.expand_path("..", __dir__)
    return nil if lib.empty?
    lib.join(File::PATH_SEPARATOR)
  end

  def self.modified_rubylib
    lib = (ENV["RUBYLIB"] || "").split(File::PATH_SEPARATOR)
    dir = File.expand_path("compatibility", __dir__)
    lib.unshift dir unless lib.include?(dir)
    #dir = File.expand_path("..", __dir__)
    #lib.unshift dir unless lib.include?(dir)
    lib.join(File::PATH_SEPARATOR)
  end

  def self.search_upwards(name, dir = Dir.pwd)
    until (file = File.join(dir, name)) && File.exist?(file)
      next_dir = File.dirname(dir)
      return nil if next_dir == dir
      dir = next_dir
    end
    file
  end

  def self.find_gemfile(path = nil, error: true)
    if path && @gemfile && @gemfile.filename != File.expand_path(path)
      raise Gel::Error::CannotActivateError.new(path: path, gemfile: @gemfile.filename)
    end
    return @gemfile.filename if @gemfile

    path ||= ENV["GEL_GEMFILE"]
    path ||= search_upwards("Gemfile")
    path ||= "Gemfile"

    if File.exist?(path)
      path
    elsif error
      raise Gel::Error::NoGemfile.new(path: path)
    end
  end

  def self.load_gemfile(path = nil, error: true)
    return @gemfile if @gemfile

    path = find_gemfile(path, error: error)
    return if path.nil?

    content = File.read(path)
    @gemfile = Gel::GemfileParser.parse(content, path, 1)
  end

  def self.lockfile_name(gemfile = self.gemfile&.filename)
    ENV["GEL_LOCKFILE"] || (gemfile && gemfile + ".lock") || "Gemfile.lock"
  end

  def self.with_store(store)
    # Work around the fact Gel::Environment is a singleton: we really
    # want to treat the environment we're running in separately from the
    # application's environment we're working on. But for now, we can
    # just cheat and swap them. (This is clearly not at all thread-safe;
    # we're relying on this method only being called from the CLI and
    # our test suite.)

    original_store = @store
    @store = store

    yield store
  ensure
    @store = original_store
  end

  def self.with_root_store(&block)
    app_store = Gel::Environment.store

    base_store = app_store
    base_store = base_store.inner if base_store.is_a?(Gel::LockedStore)

    with_store(base_store, &block)
  end

  def self.auto_install_pub_grub!
    with_root_store do |base_store|
      base_store.monitor.synchronize do
        if base_store.each("pub_grub").none?
          require_relative "work_pool"

          Gel::WorkPool.new(2) do |work_pool|
            catalog = Gel::Catalog.new("https://rubygems.org", work_pool: work_pool)

            install_gem([catalog], "pub_grub", [">= 0.5.0"], solve: false)
          end
        end
      end
    end
  end

  def self.git_depot
    require_relative "git_depot"
    @git_depot ||= Gel::GitDepot.new(store)
  end

  def self.solve_for_gemfile(store: store(), output: nil, gemfile: Gel::Environment.load_gemfile, lockfile: Gel::Environment.lockfile_name, catalog_options: {}, solve: true, preference_strategy: nil, platforms: nil)
    output = nil if $DEBUG

    target_platforms = Array(platforms)

    if lockfile && File.exist?(lockfile)
      require_relative "resolved_gem_set"
      gem_set = Gel::ResolvedGemSet.load(lockfile, git_depot: git_depot)
      target_platforms |= gem_set.platforms if gem_set.platforms

      strategy = preference_strategy&.call(gem_set)
    end

    # Should we just _always_ include our own architecture, maybe?
    target_platforms |= [architectures.first] if target_platforms.empty?

    require_relative "catalog"
    all_sources = (gemfile.sources | gemfile.gems.flat_map { |_, _, o| o[:source] }).compact
    local_source = all_sources.delete(:local)
    server_gems = gemfile.gems.select { |_, _, o| !o[:path] && !o[:git] }.map(&:first)
    catalog_pool = Gel::WorkPool.new(8, name: "gel-catalog")
    server_catalogs = all_sources.map { |s| Gel::Catalog.new(s, initial_gems: server_gems, work_pool: catalog_pool, **catalog_options) }

    require_relative "store_catalog"
    local_catalogs = local_source ? [Gel::StoreCatalog.new(store)] : []

    git_sources = gemfile.gems.map { |_, _, o|
      if o[:git]
        if o[:branch]
          [o[:git], :branch, o[:branch]]
        elsif o[:tag]
          [o[:git], :tag, o[:tag]]
        else
          [o[:git], :ref, o[:ref]]
        end
      end
    }.compact.uniq

    path_sources = gemfile.gems.map { |_, _, o| o[:path] }.compact

    require_relative "path_catalog"
    require_relative "git_catalog"

    previous_git_catalogs = {}
    if gem_set
      gem_set.gems.each do |gem_name, gem_resolutions|
        next if strategy&.refresh_git?(gem_name)

        gem_resolutions.map(&:catalog).grep(Gel::GitCatalog).uniq.each do |catalog|
          previous_git_catalogs[[catalog.remote, catalog.ref_type, catalog.ref]] = catalog
        end
      end
    end

    git_catalogs = git_sources.map do |remote, ref_type, ref|
      previous_git_catalogs[[remote, ref_type, ref]] || Gel::GitCatalog.new(git_depot, remote, ref_type, ref)
    end

    catalogs =
      path_sources.map { |path| Gel::PathCatalog.new(path) } +
      git_catalogs +
      [nil] +
      local_catalogs +
      server_catalogs

    Gel::WorkPool.new(8, name: "gel-catalog-prep") do |pool|
      if output
        output.print "Fetching sources..."
      else
        Gel::Httpool::Logger.info "Fetching sources..."
      end

      catalogs.each do |catalog|
        next if catalog.nil?

        pool.queue("catalog") do
          catalog.prepare
          output.print "." if output
        end
      end
    end

    require_relative "catalog_set"
    catalog_set = Gel::CatalogSet.new(catalogs)

    if solve
      auto_install_pub_grub!
      with_root_store do
        gem "pub_grub"
        require_relative "pub_grub/solver"
      end

      if gem_set
        # If we have any existing resolution, and no strategy has been
        # provided (i.e. we're doing an auto-resolve for 'gel install'
        # or similar), then default to "anything is permitted, but
        # change the least necessary to satisfy our constraints"

        require_relative "pub_grub/preference_strategy"
        strategy ||= Gel::PubGrub::PreferenceStrategy.new(gem_set, {}, bump: :hold, strict: false)
      end

      solver = Gel::PubGrub::Solver.new(gemfile: gemfile, catalog_set: catalog_set, platforms: target_platforms, strategy: strategy)
    else
      require_relative "null_solver"
      solver = Gel::NullSolver.new(gemfile: gemfile, catalog_set: catalog_set, platforms: target_platforms)
    end

    if output
      output.print "\nResolving dependencies..."
      t = Time.now
      until solver.solved?
        solver.work
        if Time.now > t + 0.1
          output.print "."
          t = Time.now
        end
      end
      output.puts
    else
      if solver.respond_to?(:logger)
        solver.logger.info "Resolving dependencies..."
      end

      solver.work until solver.solved?
    end

    catalog_pool.stop

    new_resolution = Gel::ResolvedGemSet.new(lockfile)

    packages_by_name = {}
    versions_by_name = {}
    solver.each_resolved_package do |package, version|
      ((packages_by_name[package.name] ||= {})[catalog_set.platform_for(package, version)] ||= []) << package

      if versions_by_name[package.name]
        raise "Conflicting version resolution #{versions_by_name[package.name].inspect} != #{version.inspect}" if versions_by_name[package.name] != version
      else
        versions_by_name[package.name] = version
      end
    end

    packages_by_name.each do |package_name, platformed_packages|
      version = versions_by_name[package_name]

      new_resolution.gems[package_name] =
        platformed_packages.map do |resolved_platform, packages|
          package = packages.first

          catalog = catalog_set.catalog_for_version(package, version)

          deps = catalog_set.dependencies_for(package, version)

          resolved_platform = nil if resolved_platform == "ruby"

          Gel::ResolvedGemSet::ResolvedGem.new(
            package.name, version, resolved_platform,
            deps.map do |(dep_name, dep_requirements)|
              next [dep_name] if dep_requirements == [">= 0"] || dep_requirements == []

              req = Gel::Support::GemRequirement.new(dep_requirements)
              req_strings = req.requirements.sort_by { |(_op, ver)| [ver, ver.segments] }.map { |(op, ver)| "#{op} #{ver}" }

              [dep_name, req_strings.join(", ")]
            end,
            set: new_resolution,
            catalog: catalog
          )
        end
    end
    new_resolution.dependencies = gemfile_dependencies(gemfile: gemfile)

    new_resolution.platforms = target_platforms
    new_resolution.server_catalogs = server_catalogs
    new_resolution.bundler_version = gem_set&.bundler_version
    new_resolution.ruby_version = RUBY_DESCRIPTION.split.first(2).join(" ") if gem_set&.ruby_version
    new_resolution
  end

  def self.gemfile_dependencies(gemfile:)
    gemfile.gems.
      group_by { |name, _constraints, _options| name }.
      map do |name, list|

      constraints = list.flat_map { |_, c, _| c }.compact

      if constraints == []
        name
      else
        r = Gel::Support::GemRequirement.new(constraints)
        req_strings = r.requirements.sort_by { |(_op, ver)| [ver, ver.segments] }.map { |(op, ver)| "#{op} #{ver}" }

        "#{name} (#{req_strings.join(", ")})"
      end
    end.sort
  end

  def self.write_lock(output: nil, lockfile: lockfile_name, **args)
    gem_set = solve_for_gemfile(output: output, lockfile: lockfile, **args)

    if lockfile
      output.puts "Writing lockfile to #{File.expand_path(lockfile)}" if output
      File.write(lockfile, gem_set.dump)
    end

    gem_set
  end

  def self.install_gem(catalogs, gem_name, requirements = nil, output: nil, solve: true)
    base_store = Gel::Environment.store
    base_store = base_store.inner if base_store.is_a?(Gel::LockedStore)

    gemfile = Gel::GemfileParser.inline do
      source "https://rubygems.org"

      gem gem_name, *requirements
    end

    gem_set = solve_for_gemfile(output: output, solve: solve, gemfile: gemfile)

    loader = Gel::LockLoader.new(gem_set)
    loader.activate(self, base_store, install: true, output: output)
  end

  def self.activate(install: false, output: nil, error: true)
    loaded = Gel::Environment.load_gemfile
    return if loaded.nil?
    return if @active_lockfile

    lockfile = Gel::Environment.lockfile_name
    if File.exist?(lockfile)
      resolved_gem_set = Gel::ResolvedGemSet.load(lockfile, git_depot: git_depot)

      resolved_gem_set = nil if lock_outdated?(loaded, resolved_gem_set)
    end

    resolved_gem_set ||= write_lock(output: output, lockfile: lockfile)

    @active_lockfile = true
    loader = Gel::LockLoader.new(resolved_gem_set, gemfile)

    base_store = Gel::Environment.store
    base_store = base_store.inner if base_store.is_a?(Gel::LockedStore)

    loader.activate(Gel::Environment, base_store, install: install, output: output)
  end

  def self.lock_outdated?(gemfile, resolved_gem_set)
    gemfile_dependencies(gemfile: gemfile) != resolved_gem_set.dependencies
  end

  def self.activate_for_executable(exes, install: false, output: nil)
    loader = nil
    if loaded = Gel::Environment.load_gemfile(error: false)
      lockfile = Gel::Environment.lockfile_name
      if File.exist?(lockfile)
        resolved_gem_set = Gel::ResolvedGemSet.load(lockfile, git_depot: git_depot)

        resolved_gem_set = nil if lock_outdated?(loaded, resolved_gem_set)
      end

      resolved_gem_set ||= write_lock(output: output, lockfile: lockfile)

      loader = Gel::LockLoader.new(resolved_gem_set, gemfile)

      base_store = Gel::Environment.store
      base_store = base_store.inner if base_store.is_a?(Gel::LockedStore)

      locked_store = loader.activate(nil, base_store, install: install, output: output)

      exes.each do |exe|
        if locked_store.each.any? { |g| g.executables.include?(exe) }
          activate(install: install, output: output)
          return :lock
        end
      end
    end

    locked_gems = loader ? loader.gem_names : []

    @gemfile = nil
    exes.each do |exe|
      candidates = @store.each.select do |g|
        !locked_gems.include?(g.name) && g.executables.include?(exe)
      end.group_by(&:name)

      case candidates.size
      when 0
        nil
      when 1
        gem(candidates.keys.first)
        return :gem
      else
        # Multiple gems can supply this executable; do we have any
        # useful way of deciding which one should win? One obvious
        # tie-breaker: if a gem's name matches the executable, it wins.

        if candidates.keys.include?(exe)
          gem(exe)
        else
          gem(candidates.keys.first)
        end

        return :gem
      end
    end

    nil
  end

  def self.find_executable(exe, gem_name = nil, gem_version = nil)
    @store.each(gem_name) do |g|
      next if gem_version && g.version != gem_version
      return File.join(g.root, g.bindir, exe) if g.executables.include?(exe)
    end
    nil
  end

  def self.filtered_gems(gems = self.gemfile.gems)
    platforms = GEMFILE_PLATFORMS.map(&:to_s)
    gems = gems.reject do |_, _, options|
      platform_options = Array(options[:platforms]).map(&:to_s)

      next true if platform_options.any? && (platform_options & platforms).empty?
      next true unless options.fetch(:install_if, true)
    end
    gems
  end

  def self.require_groups(*groups)
    gems = filtered_gems
    groups = [:default] if groups.empty?
    groups = groups.map(&:to_s)
    gems = gems.reject { |g| ((g[2][:group] || [:default]).map(&:to_s) & groups).empty? }
    @gemfile.autorequire(self, gems)
  end

  def self.find_gem(name, *requirements, &condition)
    requirements = Gel::Support::GemRequirement.new(requirements)

    @store.each(name).find do |g|
      g.satisfies?(requirements) && (!condition || condition.call(g))
    end
  end

  def self.gem(name, *requirements, why: nil)
    return if IGNORE_LIST.include?(name)

    requirements = Gel::Support::GemRequirement.new(requirements)

    if existing = activated_gems[name]
      if existing.satisfies?(requirements)
        return
      else
        why = " (#{why.join("; ")})" if why && why.first
        raise LoadError, "already loaded gem #{name} #{existing.version}, which is incompatible with: #{requirements}#{why}"
      end
    end

    gem = @store.each(name).find do |g|
      g.satisfies?(requirements)
    end

    if gem
      activate_gem gem, why: why
    else
      why = " (#{why.join("; ")})" if why && why.first
      raise LoadError, "unable to satisfy requirements for gem #{name}: #{requirements}#{why}"
    end
  end

  def self.gems_from_lock(name_version_pairs)
    gems = @store.gems(name_version_pairs)

    dirs = []
    gems.each do |name, g|
      dirs += g.require_paths
    end

    activated_gems.update gems
    $:.concat dirs
  end

  def self.activate_gem(gem, why: nil)
    raise gem.version.class.name unless gem.version.class == String
    if activated_gems[gem.name]
      raise activated_gems[gem.name].version.class.name unless activated_gems[gem.name].version.class == String
    end

    return if activated_gems[gem.name] && activated_gems[gem.name].version == gem.version
    raise LoadError, "already activated #{gem.name} #{activated_gems[gem.name].version} (can't activate #{gem.version})" if activated_gems[gem.name]

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

  def self.scan_for_path(path)
    if @store && !path.start_with?("/")
      path = path.sub(/\.rb$/, "") if path.end_with?(".rb")

      results = []
      @store.gems_for_lib(path) do |gem, subdir|
        results << [gem, subdir]
        break if activated_gems[gem.name] == gem
      end
      results.find { |g, _| activated_gems[g.name] == g } || results.first
    end
  end

  def self.gem_for_path(path)
    if result = scan_for_path(path)
      result[0]
    end
  end

  def self.resolve_gem_path(path)
    path = path.to_s # might be e.g. a Pathname

    if result = scan_for_path(path)
      activate_gem result[0], why: ["provides #{path.inspect}"]
      return result[0].path(path, result[1])
    end

    path
  end
end
