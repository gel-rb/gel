# frozen_string_literal: true

class Gel::Set
  include Enumerable

  def initialize
    @inner = {}
  end

  def each(&block)
    @inner.each_key(&block)
  end

  def include?(value)
    @inner.key?(value)
  end

  def size
    @inner.size
  end

  def add(value)
    @inner[value] = true
  end
  alias << add

  def delete(value)
    @inner.delete(value)
  end

  def add?(value)
    if @inner.key?(value)
      false
    else
      @inner[value] = true
    end
  end

  def merge(other)
    other.each do |value|
      add(value)
    end
    self
  end

  def subtract(other)
    other.each do |value|
      delete(value)
    end
    self
  end

  def |(other)
    dup.tap do |result|
      result.merge(other)
    end
  end
end
