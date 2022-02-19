# frozen_string_literal: true

require_relative "util"
require_relative "vendor/pstore"

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

module Gel::DB::Cache
  def writing(&block)
    @cache = nil
    super
  end

  def reading(&block)
    if @cache.nil?
      super do
        cache = {}
        each_key do |k|
          cache[k] = self[k]
        end
        @cache = cache
      end
    end

    yield
  end

  def each_key(&block)
    if @cache
      @cache.each_key(&block)
    else
      super
    end
  end

  def key?(key)
    if @cache
      @cache.key?(key)
    else
      super
    end
  end

  def [](key)
    if @cache
      @cache[key]
    else
      super
    end
  end
end

class Gel::DB::PStore < Gel::DB
  prepend Gel::DB::Cache
  prepend Gel::DB::AutoTransaction

  def initialize(root, name)
    @filename = "#{root}/#{name}.pstore"
    @pstore = store if ::File.exist?(@filename)
  end

  def writing(&block)
    @pstore ||= store
    @pstore.transaction(false, &block)
  end

  def reading(&block)
    @pstore = store if @pstore.nil? && ::File.exist?(@filename)
    @pstore&.transaction(true, &block)
  end

  def each_key(&block)
    @pstore.roots.each(&block) if @pstore
  end

  def key?(key)
    @pstore&.root?(key.to_s)
  end

  def [](key)
    @pstore && @pstore[key.to_s]
  end

  def []=(key, value)
    @pstore[key.to_s] = value
  end

  def delete(key)
    @pstore.delete(key.to_s)
  end

  private

  def store
    Gel::Util.mkdir_p(::File.dirname(@filename))
    Gel::Vendor::PStore.new(@filename, true)
  end
end

class Gel::DB::File < Gel::DB
  prepend Gel::DB::AutoTransaction

  def initialize(root, name)
    @base = "#{root}/#{name}"
  end

  def writing
    Gel::Util.mkdir_p(@base)
    yield
  end

  def reading
    yield
  end

  def each_key
    return unless Dir.exist?(@base)
    Dir.each_child(@base) do |child|
      yield child
    end
  end

  def key?(key)
    ::File.exist?(path(key))
  end

  def [](key)
    child = path(key)
    if ::File.exist?(child)
      Marshal.load(IO.binread(child))
    end
  end

  def []=(key, value)
    child = path(key)
    if value
      IO.binwrite child, Marshal.dump(value)
    elsif ::File.exist?(child)
      ::File.unlink(child)
    end
  end

  def delete(key)
    child = path(key)
    if ::File.exist?(child)
      value = Marshal.load(IO.binread(child))
      ::File.unlink(child)
      value
    end
  end

  private

  def path(key)
    ::File.join(@base, key)
  end
end
