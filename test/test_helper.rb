$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "paperback"

require "minitest"
require "minitest/mock"
require "webmock/minitest"

require "tmpdir"

class << Minitest
  undef load_plugins
  def load_plugins
    # no-op
  end
end

module Gem
  Version = Paperback::Support::GemVersion
end

Minitest.autorun

def fixture_file(path)
  File.expand_path("../fixtures/#{path}", __FILE__)
end

def with_empty_store
  Dir.mktmpdir do |dir|
    store = Paperback::Store.new(dir)
    yield store
  end
end

def with_fixture_gems_installed(paths)
  with_empty_store do |store|
    paths.each do |path|
      result = Paperback::Package::Installer.new(store)
      Paperback::Package.extract(fixture_file(path), result)
    end

    yield store
  end
end

def read_from_fork
  r, w = IO.pipe

  child_pid = fork do
    r.close

    yield w

    w.close

    exit! true
  end

  w.close
  r.read
ensure
  _, status = Process.waitpid2(child_pid)
  raise "child failed: #{status.inspect}" unless status.success?
end
