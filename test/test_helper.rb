$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "paperback"
require "paperback/compatibility"

require "minitest/autorun"
require "webmock/minitest"

require "tmpdir"

class << Minitest
  undef load_plugins
  def load_plugins
    # no-op
  end
end

def fixture_file(path)
  File.expand_path("../fixtures/#{path}", __FILE__)
end

def with_empty_store
  Dir.mktmpdir do |dir|
    store = Paperback::Store.new(dir)
    yield store
  end
end

def with_empty_multi_store
  Dir.mktmpdir do |dir|
    stores = {}
    Paperback::Environment.store_set.each do |arch|
      subdir = File.join(dir, arch)
      Dir.mkdir subdir
      stores[arch] = Paperback::Store.new(subdir)
    end
    store = Paperback::MultiStore.new(dir, stores)
    yield store
  end
end

def with_fixture_gems_installed(paths)
  require "paperback/package"
  require "paperback/package/installer"

  with_empty_store do |store|
    paths.each do |path|
      result = Paperback::Package::Installer.new(store)
      g = Paperback::Package.extract(fixture_file(path), result)
      g.compile
      g.install
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
