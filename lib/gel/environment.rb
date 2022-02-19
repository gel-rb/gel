# frozen_string_literal: true

require "rbconfig"
require_relative "util"
require_relative "stdlib"
require_relative "support/gem_platform"

class Gel::Environment
  IGNORE_LIST = %w(bundler gel rubygems-update)

  class << self
    attr_reader :store
    attr_accessor :gemfile
    attr_reader :architectures
  end
  self.gemfile = nil
  @active_lockfile = false
  @architectures =
    begin
      local = Gel::Support::GemPlatform.local

      list = []
      if local.cpu == "universal" && RUBY_PLATFORM =~ /^universal\.([^-]+)/
        list << "#$1-#{local.os}"
      end
      list << "#{local.cpu}-#{local.os}"
      list << "java" if defined?(org.jruby.Ruby)
      list << "ruby"

      list
    end.compact.map(&:freeze).freeze

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

    if store.respond_to?(:locked_versions) && store.locked_versions
      gems = store.gems(store.locked_versions)
      activate_gems gems.values
    end
  end

  def self.original_rubylib
    lib = (ENV["RUBYLIB"] || "").split(File::PATH_SEPARATOR)
    lib.delete File.expand_path("../../slib", __dir__)
    return nil if lib.empty?
    lib.join(File::PATH_SEPARATOR)
  end

  def self.modified_rubylib
    lib = (ENV["RUBYLIB"] || "").split(File::PATH_SEPARATOR)
    dir = File.expand_path("../../slib", __dir__)
    lib.unshift dir unless lib.include?(dir)
    lib.join(File::PATH_SEPARATOR)
  end

  def self.find_gemfile(path = nil, error: true)
    if path && @gemfile && @gemfile.filename != File.expand_path(path)
      raise Gel::Error::CannotActivateError.new(path: path, gemfile: @gemfile.filename)
    end
    return @gemfile.filename if @gemfile

    path ||= ENV["GEL_GEMFILE"]
    path ||= Gel::Util.search_upwards("Gemfile")
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

    target_platforms |= architectures if target_platforms.empty?

    require_relative "work_pool"
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

    vendor_dir = File.expand_path("../vendor/cache", gemfile.filename)
    if Dir.exist?(vendor_dir)
      require_relative "vendor_catalog"
      vendor_catalogs = [Gel::VendorCatalog.new(vendor_dir)]
    else
      vendor_catalogs = []
    end

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
      vendor_catalogs +
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
      require_relative "pub_grub/solver"

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

    active_platforms = []

    packages_by_name.each do |package_name, platformed_packages|
      version = versions_by_name[package_name]

      new_resolution.gems[package_name] =
        platformed_packages.map do |resolved_platform, packages|
          package = packages.first

          active_platforms << resolved_platform

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

    new_resolution.platforms = target_platforms & active_platforms
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
    locked_store = loader.activate(self, base_store, install: true, output: output)
    open(locked_store)
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

    require_relative "../../slib/bundler"

    locked_store = loader.activate(Gel::Environment, base_store, install: install, output: output)
    open(locked_store)
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

      locked_store = loader.activate(self, base_store, install: install, output: output)

      exes.each do |exe|
        if locked_store.each.any? { |g| g.executables.include?(exe) }
          open(locked_store)
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

    activate_gems [gem]
  end

  def self.activate_gems(gems)
    lib_dirs = gems.flat_map(&:require_paths)
    preparation = {}
    activation = {}

    gems.each do |g|
      preparation[g.name] = g.version
      activation[g.name] = g
    end

    @store.prepare(preparation)

    activated_gems.update(activation)
    $:.concat lib_dirs
  end

  # Returns either an array of compatible gems that must all be activated
  # (in the specified order) to activate the given +gem+, or a string
  # describing a dependency conflict that prevents it.
  #
  ##
  #
  # Recurses using internal +context+ as a hash of additional gems to
  # consider already activated. This is used to identify internal conflicts
  # between pending dependencies.
  def self.gems_for_activation(gem, why: nil, context: {})
    if active_gem = activated_gems[gem.name] || context[gem.name]
      # This gem name is already active. Either it's the right version, and
      # we have nothing to do, or it's the wrong version, and we're unable
      # to proceed.
      if active_gem == gem
        return []
      else
        return "already activated #{gem.name} #{active_gem.version} (can't activate #{gem.version})"
      end
    end

    context = context.dup
    new_gems = [gem]
    context[gem.name] = gem

    gem.dependencies.each do |dep, reqs|
      next if IGNORE_LIST.include?(dep)

      inner_why = ["required by #{gem.name} #{gem.version}", *why]

      requirements = Gel::Support::GemRequirement.new(
        reqs.map { |(qual, ver)| "#{qual} #{ver}" }
      )

      if existing = activated_gems[dep] || context[dep]
        if existing.satisfies?(requirements)
          next
        else
          return "already loaded gem #{dep} #{existing.version}, which is incompatible with: #{requirements} (#{inner_why.join("; ")})"
        end
      end

      resolved = nil
      first_failure = nil

      candidates = @store.each(dep).select do |g|
        g.satisfies?(requirements)
      end

      candidates.each do |g|
        result = gems_for_activation(g, why: inner_why, context: context)
        if result.is_a?(String)
          first_failure ||= result
        else
          resolved = result
          break
        end
      end

      if resolved
        new_gems += resolved
        resolved.each do |r|
          context[r.name] = r
        end
      elsif first_failure
        return first_failure
      else
        return "unable to satisfy requirements for gem #{dep}: #{requirements} (#{inner_why.join("; ")})"
      end
    end

    new_gems
  end

  def self.gem_has_file?(gem_name, path)
    search_name, search_ext = Gel::Util.split_filename_for_require(path)

    @store.gems_for_lib(search_name) do |gem, subdir, ext|
      next unless Gel::Util.ext_matches_requested?(ext, search_ext)

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

  # Search gems and stdlib for how we should load the given +path+
  #
  # Returns nil when the path is unrecognised (caller should fall back to
  # scanning $LOAD_PATH). Otherwise, returns an array tuple:
  #
  # [
  #   gem,        # nil == stdlib
  #   file,       # full path to require, or nil if gem is conflicted
  #   resolved,   # if gem: array of gems to activate, or nil if empty
  #               # if conflicted: string describing conflict
  #               # if stdlib: boolean whether the file is known to already
  #               # be loaded (may return false negative)
  # ]
  def self.scan_for_path(path)
    if @store && !path.start_with?("/")
      search_name, search_ext = Gel::Util.split_filename_for_require(path)

      # Fast scan first: find all the gems that supply a file matching
      # +search_name+ (ignoring ext for now)
      hits = []
      @store.gems_for_lib(search_name) do |gem, subdir, ext|
        hits << [gem, subdir, ext]
      end

      # Now we get a bit more detailed: 1) skip any results that don't
      # match the +search_ext+; 2) immediately return if we've matched a
      # gem that's already loaded.
      results = []
      hits.each do |gem, subdir, ext|
        next unless Gel::Util.ext_matches_requested?(ext, search_ext)

        if activated_gems[gem.name] == gem
          return [gem, gem.path(path, subdir), nil]
        else
          results << [gem, subdir, ext]
        end
      end

      # Okay, no already-loaded gems supply the file we're looking for.
      # +results+ contains a list of gems that we could load.

      # Before we start gaming out dependency trees for gems we could load,
      # it's time to check whether we've already loaded this file from
      # stdlib.
      stdlib = Gel::Stdlib.instance

      stdlib_path = stdlib.resolve(search_name, search_ext)
      stdlib_path += search_ext if stdlib_path && search_ext

      if stdlib_path && stdlib.active?(path)
        # Yep, we don't need to do anything
        return [nil, stdlib_path, true]
      end

      # We're going to have to activate a gem if we can. Recursively plan
      # out the set of dependencies we need to activate... or alternatively,
      # identify the conflict that prevents it.
      first_activation_error = nil
      results.each do |gem, subdir, ext|
        a = gems_for_activation(gem, why: ["provides #{path.inspect}"])
        if a.is_a?(Array)
          # This is a valid dependency set; activate +a+, and require the
          # file.
          return [gem, gem.path(path, subdir), a]
        else
          # If we don't find a better answer later in this loop (or in
          # +stdlib_path+), then this will be the failure we report.
          first_activation_error ||= [gem, nil, a]
        end
      end

      # We didn't find any viable gems to activate, so now we consider
      # whether we previously found a not-yet-loaded stdlib file.
      if stdlib_path
        return [nil, stdlib_path, false]
      end

      # Still no luck: this file cannot be resolved. If we found a gem that
      # was blocked by a conflict, we'll return the explanation as a string.
      # Otherwise (no installed gems have any knowledge of this file) we
      # return nil.
      first_activation_error
    end
  end

  def self.gem_for_path(path)
    gem, _file, _resolved = scan_for_path(path)
    gem
  end

  def self.resolve_gem_path(path)
    path = path.to_s # might be e.g. a Pathname

    gem, file, resolved = scan_for_path(path)

    if file
      if gem && resolved
        activate_gems resolved
      else
        unless resolved
          # This is a cheat: we're assuming the caller is about to require
          # the file
          Gel::Stdlib.instance.activate(path)
        end
      end

      return file
    elsif resolved
      raise LoadError, resolved
    end

    path
  end
end
