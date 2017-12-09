require "monitor"

class Paperback::WorkPool
  attr_accessor :queue_order

  attr_reader :count
  attr_reader :errors

  def initialize(concurrency, monitor: Monitor.new, name: nil)
    @monitor = monitor
    @name = name

    @concurrency = concurrency
    @workers = []
    @shutdown = false

    @work_cond = @monitor.new_cond
    @idle_cond = @monitor.new_cond

    @queue = []
    @count = 0
    @errors = []
  end

  def start
    @monitor.synchronize do
      while @workers.size < @concurrency
        @workers << Thread.new do
          Thread.current.name = @name if @name && Thread.current.respond_to?(:name=)
          Thread.current.report_on_exception = true

          catch(:stop) do
            loop do
              current_job = nil
              @monitor.synchronize do
                Thread.current[:active] = nil
                @work_cond.wait_until do
                  @idle_cond.broadcast
                  @shutdown || @queue.first
                end
                throw :stop if @shutdown
                current_job = @queue.shift
                Thread.current[:active] = current_job[1]
                @idle_cond.broadcast
              end

              begin
                current_job[0].call
              rescue Exception => ex
                @monitor.synchronize do
                  @errors << [current_job, ex]
                end
              end
            end
          end
        end
      end
    end
  end

  def stop
    @monitor.synchronize do
      @shutdown = true
      @work_cond.broadcast
    end
    @workers.each(&:join).clear
  end

  def idle?
    @monitor.synchronize do
      @queue.empty? && @workers.none? { |w| w[:active] }
    end
  end

  def tick!
    @monitor.synchronize do
      @idle_cond.broadcast
    end
  end

  def wait
    @monitor.synchronize do
      start if @workers.empty?

      @idle_cond.wait_until do
        (!block_given? || yield) && idle?
      end
    end
  end

  def status
    @monitor.synchronize do
      { active: @workers.map { |w| w[:active] }.compact, queued: @queue.size }
    end
  end

  def queue(job = nil, label, &block)
    raise ArgumentError if job && block
    job ||= block
    label ||= job

    @monitor.synchronize do
      @queue << [job, label]
      @count += 1
      reorder_queue!
      @work_cond.signal
    end
  end

  def reorder_queue!
    @monitor.synchronize do
      @queue.sort_by!(&@queue_order)
    end if @queue_order
  end
end
