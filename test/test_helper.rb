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
elsif defined?(org.jruby.Ruby)
  def subprocess_output(code, **kwargs)
    source = caller_locations.first

    io = StringIO.new

    config = org.jruby.RubyInstanceConfig.new
    config.input = StringIO.new.tap(&:close_write).to_input_stream
    config.output = java.io.PrintStream.new(io.to_output_stream)

    config.disable_gems = true
    config.load_paths = [File.expand_path("../lib", __dir__)]
    config.required_libraries << "paperback" << "paperback/compatibility"

    wrapped_code = kwargs.map { |name, value| "#{name} = Marshal.load(#{Marshal.dump(value).inspect})\n" }.join +
      "eval(#{code.inspect}, binding, #{source.path.inspect}, #{source.lineno + 1})"

    org.jruby.Ruby.new_instance(config).eval_scriptlet(wrapped_code)

    io.string.lines.map(&:chomp)
  end
else
  def subprocess_output(code, **kwargs)
    source = caller_locations.first

    wrapped_code = kwargs.map { |name, value| "#{name} = Marshal.load(#{Marshal.dump(value).inspect})\n" }.join +
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

    Process.waitpid2(pid)
    r.read.lines.map(&:chomp)
  end
end

def jruby?
  RUBY_ENGINE == "jruby"
end
