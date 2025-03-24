# frozen_string_literal: true

class Gel::Logger
  DEBUG = 0
  INFO = 1
  WARN = 2

  attr_accessor :level

  def initialize(io, level = $DEBUG ? DEBUG : WARN)
    @io = io
    @level = level
  end

  def debug(*args, &block)
    log(DEBUG, *args, &block)
  end

  def info(*args, &block)
    log(INFO, *args, &block)
  end

  def warn(*args, &block)
    log(WARN, *args, &block)
  end

  private

  EMPTY = Object.new
  def log(level, message = EMPTY)
    return unless level >= @level

    if EMPTY == message
      message = yield
    end

    @io.puts message
  end
end
