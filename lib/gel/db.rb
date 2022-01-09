# frozen_string_literal: true

require_relative "vendor/pstore"
require "pathname"

require "monitor"

class Gel::DB
  def self.new(root, name)
    return super unless self == Gel::DB

    PStore.new(root, name)
  end

  def initialize(root, name)
  end

  def writing
  end

  def reading
  end

  def each_key
  end

  def key?(key)
  end

  def [](key)
  end

  def []=(key, value)
  end

  def delete(key)
  end
end

module Gel::DB::AutoTransaction
  def initialize(root, name)
    @root = root
    @name = name

    super

    @transaction = nil
    @monitor = Monitor.new
  end

  if Monitor.method_defined?(:mon_owned?) # Ruby 2.4+
    def owned?
      @monitor.mon_owned?
    end
  else
    def owned?
      @monitor.instance_variable_get(:@mon_owner) == Thread.current
    end
  end

  def write?
    owned? && @transaction == :write
  end

  def read?
    owned? && @transaction
  end

  def nested?
    owned? && @transaction
  end

  def writing
    raise if nested?

    @monitor.synchronize do
      begin
        @transaction = :write
        super
      ensure
        @transaction = nil
      end
    end
  end

  def reading
    raise if nested?

    @monitor.synchronize do
      begin
        @transaction = :read
        super
      ensure
        @transaction = nil
      end
    end
  end

  def each_key
    if read?
      super
    else
      reading { super }
    end
  end

  def key?(key)
    if read?
      super
    else
      reading { super }
    end
  end

  def [](key)
    if read?
      super
    else
      reading { super }
    end
  end

  def []=(key, value)
    if write?
      super
    else
      writing { super }
    end
  end

  def delete(key)
    if write?
      super
    else
      writing { super }
    end
  end

  private

  def marshal_dump
    [@root, @name]
  end

  def marshal_load((root, name))
    initialize(root, name)
  end
end

class Gel::DB::PStore < Gel::DB
  prepend Gel::DB::AutoTransaction

  def initialize(root, name)
    @pstore = Gel::Vendor::PStore.new("#{root}/#{name}.pstore", true)
  end

  def writing(&block)
    @pstore.transaction(false, &block)
  end

  def reading(&block)
    @pstore.transaction(true, &block)
  end

  def each_key(&block)
    @pstore.roots.each(&block)
  end

  def key?(key)
    @pstore.key?(key.to_s)
  end

  def [](key)
    @pstore[key.to_s]
  end

  def []=(key, value)
    @pstore[key.to_s] = value
  end

  def delete(key)
    @pstore.delete(key.to_s)
  end
end

class Gel::DB::File < Gel::DB
  prepend Gel::DB::AutoTransaction

  def initialize(root, name)
    @path = Pathname.new("#{root}/#{name}")
  end

  def writing
    @path.mkdir unless @path.exist?
    yield
  end

  def reading
    yield
  end

  def each_key
    @path.each_child(false) do |child|
      yield child.to_s
    end
  end

  def key?(key)
    @path.join(key).exist?
  end

  def [](key)
    child = @path.join(key)
    if child.exist?
      Marshal.load(child.binread)
    end
  end

  def []=(key, value)
    child = @path.join(key)
    if value
      child.binwrite Marshal.dump(value)
    elsif child.exist?
      child.unlink
    end
  end

  def delete(key)
    child = @path.join(key)
    if child.exist?
      value = Marshal.load(child.binread)
      child.unlink
      value
    end
  end
end
