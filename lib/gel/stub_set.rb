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

  def rebuild!
    @db.reading do
      @db.each_key do |exe|
        create_stub(exe)
      end
    end
  end

  def create_stub(exe)
    Dir.mkdir(@dir) unless Dir.exist?(@dir)

    File.open(bin(exe), "w", 0755) do |f|
      f.write(<<STUB)
#!/usr/bin/env gel
#! This ruby binstub is generated and managed by Gel
require "gel/stub" unless defined? Gel.stub
Gel.stub #{exe.dump}
STUB
    end
  end

  def own_stub?(path)
    File.realpath(path).start_with?(@dir)
  end

  def parse_stub(path)
    return unless File.exist?(path)

    File.open(path, "r") do |f|
      # Stub prefix is ~128 bytes
      content = f.read(500)

      if content =~ /^Gel\.stub (.*)$/
        $1.undump
      elsif content =~ /\A#!.* gel stub (.*)$/
        # Legacy stub
        $1
      end
    end
  end

  def bin(exe)
    File.join(@dir, exe)
  end
end
