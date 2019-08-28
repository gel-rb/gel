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
      long_string = '*' * (Gel::DB::SDBM::SDBM_MAX_STORE_SIZE + 200)
      db['test'] = long_string
      assert_equal db['test'], long_string

      # A object with a long string gets stored and marshaled correctly
      hash_string = { a: long_string, b: long_string }
      db['test'] = hash_string
      assert_equal db['test'], hash_string
    end
  end

  def test_file_store_value_retrieval
    Dir.mktmpdir do |dir|
      db = Gel::DB::File.new(dir, 'test-store')

      # Still handles ints okay
      db['test'] = 12
      assert_equal db['test'], 12

      # A simple string should return a simple string
      db['test'] = 'Hello World'
      assert_equal db['test'], 'Hello World'

      # A simple hash should return a simple hash
      db['test'] = { a: 'Hello World' }
      assert_equal db['test'], { a: 'Hello World' }

      # A long string
      long_string = '*' * 1024
      db['test'] = long_string
      assert_equal db['test'], long_string

      # A object with a long string gets stored and marshaled correctly
      hash_string = { a: long_string, b: long_string }
      db['test'] = hash_string
      assert_equal db['test'], hash_string

      # A key with a slash works
      db['foo/bar'] = hash_string
      assert_equal db['foo/bar'], hash_string
    end
  end
end
