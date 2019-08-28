# frozen_string_literal: true

begin
  require "sdbm"
rescue LoadError
end
require "pstore"
require "pathname"

require "monitor"

class Gel::DB
  def self.new(root, name)
    return super unless self == Gel::DB

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

  private

  def marshal_dump
    [@root, @name]
  end

  def marshal_load((root, name))
    initialize(root, name)
  end
end

class Gel::DB::SDBM < Gel::DB
  prepend Gel::DB::AutoTransaction
  SDBM_MAX_STORE_SIZE = 1000 - 1 # arbitrary on PBLKSIZ-N
  SAFE_DELIMITER = '---'

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

  ##
  # Retrieve the value from SDBM and handle for when we split
  # over multiple stores. It is safe to assume that the value
  # stored will be a marshaled value or a integer implying the
  # amount of extra stores to retrieve the data string form. A
  # marshaled store would have special starting delimiter that
  # is not a decimal. If a number is not found at start of string
  # then simply load it as a string and you get a value that
  # is then marshaled.
  def [](key)
    value = @sdbm[key.to_s]
    return nil unless value

    if value =~ /\A~(\d+)\z/
      value = $1.to_i.times.map do |idx|
        @sdbm["#{key}#{SAFE_DELIMITER}#{idx}"]
      end.join
    end

    return Marshal.load(value)
  end


  ##
  # SDBM has an arbitrary limit on the size of a string it stores,
  # so we simply split any string over multiple stores for the edge
  # case when it reaches this. It's optimised to take advantage of the common
  # case where this is not needed.
  # When the edge case is hit, the first value in the storage will be the amount
  # of extra values stored to hold the split string. This amount is determined by string
  # size split by the arbitrary limit imposed by SDBM
  def []=(key, value)
    return unless value && key

    dump = Marshal.dump(value)
    count = dump.length / SDBM_MAX_STORE_SIZE

    if count > 0
      count += 1
      @sdbm["#{key.to_s}"] = "~#{count}"
      count.times.map do |idx|
        @sdbm["#{key.to_s}#{SAFE_DELIMITER}#{idx}"] = dump.slice!(0, SDBM_MAX_STORE_SIZE)
      end
    else
      @sdbm[key.to_s] = dump
    end
  end
end

class Gel::DB::PStore < Gel::DB
  prepend Gel::DB::AutoTransaction

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
    Dir.each_child(@path) do |child|
      yield unmangle(child)
    end
  end

  def key?(key)
    @path.join(mangle(key)).exist?
  end

  def [](key)
    child = @path.join(mangle(key))
    if child.exist?
      Marshal.load(child.binread)
    end
  end

  def []=(key, value)
    child = @path.join(mangle(key))
    if value
      child.binwrite Marshal.dump(value)
    elsif child.exist?
      child.unlink
    end
  end

  private

  def mangle(key)
    [key].pack("m").chomp
  end

  def unmangle(filename)
    filename.unpack1("m")
  end
end
