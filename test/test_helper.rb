# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "gel"
require "gel/compatibility"

require "minitest/autorun"
require "mocha/minitest"
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

def with_empty_store(multi: false, &block)
  if multi
    return with_empty_multi_store(&block)
  end

  Dir.mktmpdir do |dir|
    store = Gel::Store.new(dir)
    yield store
  end
end

def with_empty_multi_store
  Dir.mktmpdir do |dir|
    stores = {}
    Gel::Environment.store_set.each do |arch|
      subdir = File.join(dir, arch)
      Dir.mkdir subdir
      stores[arch] = Gel::Store.new(subdir)
    end
    store = Gel::MultiStore.new(dir, stores)
    yield store
  end
end

def with_fixture_gems_installed(paths, multi: false)
  require "gel/package"
  require "gel/package/installer"

  with_empty_store(multi: multi) do |store|
    paths.each do |path|
      result = Gel::Package::Installer.new(store)
      g = Gel::Package.extract(fixture_file(path), result)
      g.compile
      g.install
    end

    yield store
  end
end

if respond_to?(:fork, true)
  module RequireHack
    def require(path)
    end
  end

  def subprocess_output(code, **kwargs)
    source = caller_locations(1..1).first

    read_from_fork { |ch|
      # This (and the matching one below the eval) allow DeepCover's
      # clone mode to correctly pick up activity in the forked process.
      if defined?($_cov) # rubocop:disable GlobalVars
        $_cov.each_value { |arr| arr.map! { 0 } } # rubocop:disable GlobalVars
        require "fileutils"
      end

      $stdout = ch

      b = binding

      kwargs.each do |name, value|
        b.local_variable_set(name, value)
      end

      eval code, b, source.path, source.lineno + 1 # rubocop:disable Eval

      if defined?(DeepCover::CLONE_MODE_ENTRY_TOP_LEVEL_MODULES)
        # We may have broken require by now. DeepCover will
        # `require "fileutils"`, but we know that's a no-op (because we
        # made sure to load it earlier).
        ::Object.prepend RequireHack

        DeepCover::CLONE_MODE_ENTRY_TOP_LEVEL_MODULES.first::DeepCover.save
      end
    }.lines.map(&:chomp)
  end

  def read_from_fork
    r, w = IO.pipe

    child_pid = fork {
      r.close

      yield w

      w.close

      exit! true
    }

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
    source = caller_locations(1..1).first

    io = StringIO.new

    config = org.jruby.RubyInstanceConfig.new
    config.input = StringIO.new.tap(&:close_write).to_input_stream
    config.output = java.io.PrintStream.new(io.to_output_stream)

    config.required_libraries << File.expand_path("../gel/compatibility", __dir__)

    wrapped_code = kwargs.map { |name, value| "#{name} = Marshal.load(#{Marshal.dump(value).inspect})\n" }.join +
      "eval(#{code.inspect}, binding, #{source.path.inspect}, #{source.lineno + 1})"

    org.jruby.Ruby.new_instance(config).eval_scriptlet(wrapped_code)

    io.string.lines.map(&:chomp)
  end
else
  def subprocess_output(code, **kwargs)
    source = caller_locations(1..1).first

    wrapped_code = kwargs.map { |name, value| "#{name} = Marshal.load(#{Marshal.dump(value).inspect})\n" }.join +
      "eval(#{code.inspect}, binding, #{source.path.inspect}, #{source.lineno + 1})"

    r, w = IO.pipe

    pid = spawn(
      {
        "RUBYLIB" => File.expand_path("../lib/gel/compatibility", __dir__),
        "GEL_STORE" => nil,
        "GEL_LOCKFILE" => nil,
      },
      RbConfig.ruby,
      "-r", File.expand_path("../lib/gel/compatibility", __dir__),
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
