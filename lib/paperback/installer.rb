require "monitor"

class Paperback::Installer
  DOWNLOAD_CONCURRENCY = 6
  COMPILE_CONCURRENCY = 4

  include MonitorMixin

  attr_reader :store

  def initialize(store)
    super()

    @trace = nil

    @shutdown = false

    @messages = Queue.new

    @store = store
    @dependencies = Hash.new { |h, k| h[k] = [] }
    @weights = Hash.new(1)

    @download_cond = new_cond
    @compile_cond = new_cond
    @idle_cond = new_cond

    @download_queue = []
    @compile_queue = []
    @compile_waiting = []

    @total = 0

    @errors = []

    @workers = []
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

      prioritize_queues
    end
  end

  def install_gem(catalogs, name, version)
    synchronize do
      raise "catalogs is nil" if catalogs.nil?
      @download_queue << [catalogs, name, version]
      prioritize_queues
      @total += 1
      @download_cond.signal
    end
  end

  def start
    synchronize do
      DOWNLOAD_CONCURRENCY.times do
        @workers << Thread.new do
          Thread.current.report_on_exception = true
          Thread.current[:role] = :download

          catch(:stop) do
            loop do
              next_job = synchronize do
                Thread.current[:job] = "~"
                Thread.current[:idle] = true
                @download_cond.wait_until do
                  @idle_cond.broadcast
                  @shutdown || @download_queue.first
                end
                throw :stop if @shutdown
                Thread.current[:idle] = false
                @download_queue.shift
              end

              Thread.current[:job] = next_job[1]
              work_download next_job
            end
          end
        end
      end

      COMPILE_CONCURRENCY.times do
        @workers << Thread.new do
          Thread.current.report_on_exception = true
          Thread.current[:role] = :compile

          catch(:stop) do
            loop do
              next_job = synchronize do
                Thread.current[:job] = "~"
                Thread.current[:idle] = true
                @compile_cond.wait_until do
                  @idle_cond.broadcast
                  @shutdown || @compile_queue.first
                end
                throw :stop if @shutdown
                Thread.current[:idle] = false
                @compile_queue.shift
              end

              Thread.current[:job] = next_job.spec.name
              work_compile next_job
            end
          end
        end
      end
    end
  end

  def shutdown
    synchronize do
      @shutdown = true
      @download_cond.broadcast
      @compile_cond.broadcast
    end
  end

  def work_download((catalogs, name, version))
    p [catalogs, name, version] if catalogs.nil?
    catalogs.each do |catalog|
      begin
        f = catalog.download_gem(name, version)
      rescue Net::HTTPError
      else
        f.close
        installer = Paperback::Package::Installer.new(store)
        g = Paperback::Package.extract(f.path, installer)
        known_dependencies g.spec.name => g.spec.runtime_dependencies.keys
        if g.needs_compile?
          synchronize do
            add_weight name, 1000

            @compile_queue << g
            prioritize_queues

            @compile_cond.signal
          end
        else
          @messages << "Installing #{name} (#{version})\n"
          g.install
        end
        return
      ensure
        f.unlink if f
      end
    end

    raise "Unable to locate #{name} #{version} in: #{catalogs.join ", "}"
  rescue => ex
    synchronize do
      @errors << [name, version, ex]
    end
  end

  def work_compile(g)
    if g.compile_ready?
      g.compile
      @messages << "Installing #{g.spec.name} (#{g.spec.version})\n"
      g.install
      synchronize do
        until @compile_waiting.empty?
          @compile_queue << @compile_waiting.shift
        end
        prioritize_queues
      end
    else
      synchronize do
        @compile_waiting << g
      end
    end
  rescue => ex
    synchronize do
      @errors << [g.spec.name, g.spec.version, ex]
    end
  end

  def wait(output = nil)
    synchronize do
      if @workers.empty?
        return if @total.zero?

        start
      end

      clear = ""
      @idle_cond.wait_until do
        if output
          output.write clear
          output.write @messages.pop until @messages.empty?
          groups = @workers.reject { |w| w[:idle] }.group_by { |w| w[:role] }
          if groups[:download]
            download_msg = "Downloading: " + groups[:download].map { |w| w[:job] }.join(" ")
            download_msg << " +#{@download_queue.size}" unless @download_queue.empty?
          end
          if groups[:compile]
            compile_msg = "Compiling: " + groups[:compile].map { |w| w[:job] }.join(" ")
            compile_msg << " +#{@compile_queue.size}" unless @compile_queue.empty?
          end
          if download_msg && compile_msg
            msgline = "[#{download_msg};   #{compile_msg}]"
          elsif download_msg || compile_msg
            msgline = "[#{download_msg || compile_msg}]"
          else
            msgline = ""
          end
          clear = "\b" * msgline.size + " " * msgline.size + "\b" * msgline.size
          output.write msgline
        else
          @messages.pop until @messages.empty?
        end
        @download_queue.empty? && @compile_queue.empty? && @workers.all? { |w| w[:idle] }
      end
      if output
        output.write clear
      end
      raise unless @compile_waiting.empty?
      shutdown
    end

    @workers.each(&:join).clear

    if @errors.empty?
      if output
        output.write "Installed #{@total} gems\n"
      end
    else
      if output
        output.write "Installed #{@total - @errors.size} of #{@total} gems\n\nErrors encountered with #{@errors.size} gems:\n\n"
        @errors.each do |name, version, exception|
          output.write "#{name} (#{version})\n  #{exception}\n\n"
        end
      end

      raise "Errors encountered while installing gems"
    end
  end

  private

  def add_weight(name, weight)
    @weights[name] += weight
    @dependencies[name].each do |dependency|
      add_weight dependency, weight
    end
  end

  # Every time we learn about a new dependency, we reorder the queues to
  # ensure the most depended-on gems are processed first. This ensures
  # we can start compiling extension gems as soon as possible.
  def prioritize_queues
    @download_queue.sort_by! do |_catalogs, name, _version|
      -@weights[name]
    end

    @compile_queue.sort_by! do |g|
      -@weights[g.spec.name]
    end
  end
end
