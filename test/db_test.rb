# frozen_string_literal: true

require "test_helper"

class DbTest < Minitest::Test
  def test_sdbm_store_value_retrieval
    skip unless defined? ::SDBM
    Dir.mktmpdir do |dir|
      db = Gel::DB::SDBM.new(dir, 'test-store')

      # Still handles ints okay
      db['test'] = 12
      assert_equal db['test'], 12

      # A simple string should return a simple string
      db['test'] = 'Hello World'
      assert_equal db['test'], 'Hello World'

      # A simple hash should return a simple hash
      db['test'] = { a: 'Hello World' }
      assert_equal db['test'], { a: 'Hello World' }

      # A string that will be split up over multiple stores
      long_string = '*' * (Gel::DB::SDBM::SDBM_PAIRMAX + 200)
      db['test'] = long_string
      assert_equal db['test'], long_string

      # Long keys must be storable, too
      long_key = "*" * 200
      db[long_key] = long_string
      assert_equal db[long_key], long_string

      # A object with a long string gets stored and marshaled correctly
      hash_string = { a: long_string, b: long_string }
      db['test'] = hash_string
      assert_equal db['test'], hash_string
    end
  end

  def test_previous_multikey_format
    skip unless defined? ::SDBM
    Dir.mktmpdir do |dir|
      db = Gel::DB::SDBM.new(dir, "test-store")

      sdbm = db.instance_variable_get(:@sdbm)
      sdbm["test"] = "~4"
      sdbm["test---0"] = "\x04\x08\"\x09a"
      sdbm["test---1"] = "b"
      sdbm["test---2"] = "c"
      sdbm["test---3"] = "d"

      assert_equal "abcd", db["test"]

      assert_equal %w(test test---0 test---1 test---2 test---3), sdbm.keys.sort

      db["test"] = "short"

      assert_equal %w(test), sdbm.keys.sort

      sdbm["test"] = "~4"
      sdbm["test---0"] = "\x04\x08\"\x09a"
      sdbm["test---1"] = "b"
      sdbm["test---2"] = "c"
      sdbm["test---3"] = "d"

      long_string = "*" * (Gel::DB::SDBM::SDBM_PAIRMAX + 200)
      db["test"] = long_string

      assert_equal %w(test test~0 test~1), sdbm.keys.sort
    end
  end
end
