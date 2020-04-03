# frozen_string_literal: true

require "monitor"
require "net/http"

require_relative "work_pool"
require_relative "git_depot"
require_relative "package"
require_relative "package/installer"

class Gel::Installer
  DOWNLOAD_CONCURRENCY = 6
  COMPILE_CONCURRENCY = 4

  include MonitorMixin

  attr_reader :store

  def initialize(store)
    super()

    @trace = nil

    @messages = Queue.new

    @store = store
    @dependencies = Hash.new { |h, k| h[k] = [] }
    @weights = Hash.new(1)
    @pending = Hash.new(0)
    @git_remotes = Hash.new

    @download_pool = Gel::WorkPool.new(DOWNLOAD_CONCURRENCY, monitor: self, name: "gel-download", collect_errors: true)
    @compile_pool = Gel::WorkPool.new(COMPILE_CONCURRENCY, monitor: self, name: "gel-compile", collect_errors: true)

    @download_pool.queue_order = -> ((_, name)) { -@weights[name] }
    @compile_pool.queue_order = -> ((_, name)) { -@weights[name] }

    @git_depot = Gel::GitDepot.new(store)

    @compile_waiting = []
  end

  def known_dependencies(deps)
    deps = deps.dup

    synchronize do
      @dependencies.update(deps) { |k, l, r| deps[k] = r - l; l | r }
      return if deps.values.all?(&:empty?)

      deps.each do |dependent, dependencies|
        dependencies.each do |dependency|
          add_weight dependency, @weights[dependent]
        end
      end

      # Every time we learn about a new dependency, we reorder the
      # queues to ensure the most depended-on gems are processed first.
      # This ensures we can start compiling extension gems as soon as
      # possible.
      @download_pool.reorder_queue!
      @compile_pool.reorder_queue!
    end
  end

  def install_gem(catalogs, name, version)
    raise "Refusing to install incompatible #{name.inspect}" if Gel::Environment::IGNORE_LIST.include?(name)

    synchronize do
      raise "catalogs is nil" if catalogs.nil?
      @pending[name] += 1
      @download_pool.queue(name) do
        work_download([catalogs, name, version])
      end
    end
  end

  def load_git_gem(remote, revision, name)
    synchronize do
      @pending[name] += 1

      checkout_key = "#{remote}@#{revision}"

      # Has another gem already been pulled from this git repo?
      if @git_remotes.key?(checkout_key)
        if waiting_gems = @git_remotes[checkout_key]
          # The checkout is currently queued or in progress; we'll wait
          # for it too
          waiting_gems << name
        else
          # The checkout has already finished, so this gem is already
          # available
          git_ready(name)
        end
      else
        @git_remotes[checkout_key] = [name]

        @download_pool.queue(name) do
          work_git(remote, revision, checkout_key)
        end
      end
    end
  end

  def work_git(remote, revision, checkout_key)
    @git_depot.checkout(remote, revision)

    synchronize do
      gem_names = @git_remotes[checkout_key]
      @git_remotes[checkout_key] = nil

      gem_names.each do |name|
        git_ready(name)
      end
    end
  end

  def git_ready(name)
    @messages << "Using #{name} (git)\n"
    @pending[name] -= 1
  end

  def download_gem(catalogs, name, version)
    catalogs.each do |catalog|
      if fpath = catalog.cached_gem(name, version)
        return fpath
      end
    end

    catalogs.each do |catalog|
      begin
        return catalog.download_gem(name, version)
      rescue Net::HTTPExceptions
      end
    end

    raise "Unable to locate #{name} #{version} in: #{catalogs.join ", "}"
  end

  def work_download((catalogs, name, version))
    fpath = download_gem(catalogs, name, version)

    installer = Gel::Package::Installer.new(store)
    g = Gel::Package.extract(fpath, installer)
    known_dependencies g.spec.name => g.spec.runtime_dependencies.keys
    if g.needs_compile?
      synchronize do
        add_weight name, 1000

        @compile_pool.queue(g.spec.name) do
          work_compile(g)
        end
      end
    else
      work_install(g)
    end
  end

  def work_compile(g)
    synchronize do
      unless compile_ready?(g.spec.name)
        @compile_waiting << g
        return
      end
    end

    g.compile
    work_install(g)
  end

  def work_install(g)
    @messages << "Installing #{g.spec.name} (#{g.spec.version})\n"
    g.install
    @pending[g.spec.name] -= 1

    synchronize do
      compile_recheck, @compile_waiting = @compile_waiting, []

      compile_recheck.each do |gem|
        @compile_pool.queue(gem.spec.name) do
          work_compile(gem)
        end
      end
    end
  end

  def wait(output = nil)
    clear = ""
    tty = output && output.isatty

    pools = { "Downloading" => @download_pool, "Compiling" => @compile_pool }

    return if pools.values.all?(&:idle?)

    update_status = lambda do
      synchronize do
        if output
          output.write clear
          output.write @messages.pop until @messages.empty?

          if tty
            messages = pools.map { |label, pool| pool_status(label, pool, label == "Compiling" ? @compile_waiting.size : 0) }.compact
            if messages.empty?
              msgline = ""
            else
              msgline = "[" + messages.join(";   ") + "]"
            end
            clear = "\r" + " " * msgline.size + "\r"
            output.write msgline
          end
        else
          @messages.pop until @messages.empty?
        end
        pools.values.all?(&:idle?) && @compile_waiting.empty?
      end
    end

    pools.values.map do |pool|
      Thread.new do
        Thread.current.abort_on_exception = true

        pool.wait(&update_status)
        pools.values.each(&:tick!)
        pool.stop
      end
    end.each(&:join)

    errors = @download_pool.errors + @compile_pool.errors

    if errors.empty?
      if output
        output.write "Installed #{@download_pool.count} gems\n"
      end
    else
      if output
        output.write "Installed #{@download_pool.count - errors.size} of #{@download_pool.count} gems\n\nErrors encountered with #{errors.size} gems:\n\n"
        errors.each do |(_, name), exception|
          output.write "#{name}\n  #{exception}\n\n"
        end
      end

      if errors.first
        raise errors.first.last
      else
        raise "Errors encountered while installing gems"
      end
    end
  end

  private

  def compile_ready?(name)
    @dependencies[name].all? do |dep|
      if @pending[dep] == 0
        compile_ready?(dep)
      elsif @download_pool.errors.any? { |(_, failed_name), ex| failed_name == dep }
        raise "Depends on #{dep.inspect}, which failed to download"
      elsif @compile_pool.errors.any? { |(_, failed_name), ex| failed_name == dep }
        raise "Depends on #{dep.inspect}, which failed to compile"
      else
        false
      end
    end
  end

  def pool_status(label, pool, extra_queue = 0)
    st = pool.status
    queue = st[:queued] + extra_queue

    return if st[:active].empty? && queue.zero?

    msg = +"#{label}:"
    msg << " #{st[:active].join(" ")}" unless st[:active].empty?
    msg << " +#{queue}" unless queue.zero?
    msg
  end

  def add_weight(name, weight)
    @weights[name] += weight
    @dependencies[name].each do |dependency|
      add_weight dependency, weight
    end
  end
end
