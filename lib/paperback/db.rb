# frozen_string_literal: true

begin
  require "sdbm"
rescue LoadError
end
require "pstore"
require "pathname"

require "monitor"

class Paperback::DB
  def self.new(root, name)
    return super unless self == Paperback::DB

    if defined? ::SDBM
      SDBM.new(root, name)
    else
      PStore.new(root, name)
    end
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
end

module Paperback::DB::AutoTransaction
  def initialize(*)
    super
    @transaction = nil
    @monitor = Monitor.new
  end

  if Monitor.method_defined?(:mon_owned)
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
end

class Paperback::DB::SDBM < Paperback::DB
  prepend Paperback::DB::AutoTransaction

  def initialize(root, name)
    @sdbm = ::SDBM.new("#{root}/#{name}")
  end

  def writing
    yield
  end

  def reading
    yield
  end

  def each_key(&block)
    @sdbm.each_key(&block)
  end

  def key?(key)
    !!@sdbm[key.to_s]
  end

  def [](key)
    if value = @sdbm[key.to_s]
      Marshal.load(value)
    end
  end

  def []=(key, value)
    @sdbm[key.to_s] = value && Marshal.dump(value)
  end
end

class Paperback::DB::PStore < Paperback::DB
  prepend Paperback::DB::AutoTransaction

  def initialize(root, name)
    @pstore = ::PStore.new("#{root}/#{name}.pstore", true)
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
end

class Paperback::DB::File < Paperback::DB
  prepend Paperback::DB::AutoTransaction

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
end
