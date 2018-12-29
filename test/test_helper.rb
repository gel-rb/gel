# frozen_string_literal: true

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

if respond_to?(:fork, true)
  def subprocess_output(code, **kwargs)
    source = caller_locations.first

    read_from_fork do |ch|
      $stdout = ch

      b = binding

      kwargs.each do |name, value|
        b.local_variable_set(name, value)
      end

      eval code, b, source.path, source.lineno + 1
    end.lines.map(&:chomp)
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
    if child_pid
      _, status = Process.waitpid2(child_pid)
      raise "child failed: #{status.inspect}" unless status.success?
    end
  end
else
  def reconstruct_in_subprocess(object)
    case object
    when Paperback::MultiStore
      "Paperback::MultiStore.new(#{reconstruct_in_subprocess(object.root)}, #{reconstruct_in_subprocess(object.instance_variable_get(:@stores))})"
    when Paperback::Store
      "Paperback::Store.new(#{reconstruct_in_subprocess(object.root)})"
    when String, Integer, NilClass
      object.inspect
    when Array
      "[#{object.map { |item| reconstruct_in_subprocess(item) }.join(", ") }]"
    when Hash
      "{#{object.map { |key, value|
        "#{reconstruct_in_subprocess(key)} => #{reconstruct_in_subprocess(value)}"
      }.join(", ")}}"
    else
      raise "Unknown object #{object.class}"
    end
  end

  def subprocess_output(code, **kwargs)
    source = caller_locations.first

    wrapped_code = kwargs.map { |name, value| "#{name} = #{reconstruct_in_subprocess(value)}\n" }.join +
      "eval(#{code.inspect}, binding, #{source.path.inspect}, #{source.lineno + 1})"

    r, w = IO.pipe

    pid = spawn(
      { "RUBYOPT" => nil, "PAPERBACK_STORE" => nil, "PAPERBACK_LOCKFILE" => nil },
      RbConfig.ruby, "--disable=gems",
      "-I", File.expand_path("../lib", __dir__),
      "-r", "paperback",
      "-r", "paperback/compatibility",
      "-e", wrapped_code,
      in: IO::NULL,
      out: w,
    )

    w.close

    _, status = Process.waitpid2(pid)
    r.read.lines.map(&:chomp)
  end
end

def jruby?
  RUBY_ENGINE == "jruby"
end
