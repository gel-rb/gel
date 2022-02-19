# frozen_string_literal: true

require_relative "db"

class Gel::StubSet
  attr_reader :root

  def initialize(root)
    @root = File.realpath(File.expand_path(root))
    @db = Gel::DB.new(root, "stubs")
    @dir = File.join(@root, "bin")
  end

  def add(store, executables)
    @db.writing do
      executables.each do |exe|
        create_stub(exe) unless File.exist?(bin(exe))
        @db[exe] = (@db[exe] || []) + [store]
      end
    end
  end

  def remove(store, executables)
    @db.writing do
      executables.each do |exe|
        remaining_stores = (@db[exe] || []) - [store]
        if remaining_stores.empty?
          File.unlink(bin(exe))
          @db.delete(exe)
        else
          @db[exe] = remaining_stores
        end
      end
    end
  end

  def create_stub(exe)
    Dir.mkdir(@dir) unless Dir.exist?(@dir)

    File.open(bin(exe), "w", 0755) do |f|
      f.write(<<STUB)
#!/usr/bin/env gel stub ruby #{exe}
# This file is generated and managed by Gel.
Gel.stub(#{exe.inspect})
STUB
    end
  end

  def bin(exe)
    File.join(@dir, exe)
  end
end
