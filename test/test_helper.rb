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

if false
  Minitest.after_run { $stderr.puts Thread.list.map(&:inspect) }
end

def fixture_file(path)
  File.expand_path("../fixtures/#{path}", __FILE__)
end

module CacheOverride
  def setup
    @cache_override_original = ENV["GEL_CACHE"]
    ENV["GEL_CACHE"] = @cache_override_cache = Dir.mktmpdir
    super
  end

  def teardown
    super
    FileUtils.remove_entry @cache_override_cache
    ENV["GEL_CACHE"] = @cache_override_original
  end
end

Minitest::Test.prepend CacheOverride

def with_empty_store(multi: false, &block)
  if multi
    return with_empty_multi_store(&block)
  end

  Dir.mktmpdir do |dir|
    store = Gel::Store.new(dir)
    yield store
  end
end

def with_baseline_store
  with_empty_multi_store(fallbacks: true) do |store|
    yield store
  end
end

def with_empty_cache
  previous = ENV["GEL_CACHE"]

  begin
    Dir.mktmpdir do |dir|
      ENV["GEL_CACHE"] = dir
      yield
    end
  ensure
    ENV["GEL_CACHE"] = previous
  end
end

def with_empty_multi_store(fallbacks: false)
  original_stores = Gel::Environment.root_store

  Dir.mktmpdir do |dir|
    stores = {}
    Gel::Environment.store_set.each do |arch|
      subdir = File.join(dir, arch)
      Dir.mkdir subdir
      stores[arch] = Gel::Store.new(subdir)

      if fallbacks
        stores["#{arch}.fallback"] = original_stores[arch]
      end
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

# Set up stubs for a small but real-world-shaped gem source (which
# supports compact index).
#
# Use this when catalog interaction is incidental (i.e., the test is
# focused on the resolution process/ result) and you just need the
# test to exist in a world where some gems exist; use explicit request
# stubs to test catalog interaction details (exactly which/when paths
# do/don't get downloaded, fallback between catalog formats, etc).
def stub_gem_mimer(source: "https://gem-mimer.org")
  require fixture_file("index/info.rb")

  stub_request(:get, "#{source}/versions")
    .to_return(body: File.open(fixture_file("index/versions")))

  stub_request(:get, Addressable::Template.new("#{source}/info/{gem}"))
    .to_return(body: lambda { |request| FIXTURE_INDEX[File.basename(request.uri)] })
end

if respond_to?(:fork, true)
  module RequireHack
    def require(path)
    end
  end

  def subprocess_output(code, **kwargs)
    source = caller_locations.first

    read_from_fork { |ch|
      # This (and the matching one below the eval) allow DeepCover's
      # clone mode to correctly pick up activity in the forked process.
      if defined?($_cov)
        $_cov.each_value { |arr| arr.map! { 0 } }
        require "fileutils"
      end

      $stdout = ch

      b = binding

      kwargs.each do |name, value|
        b.local_variable_set(name, value)
      end

      eval code, b, source.path, source.lineno + 1

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
    source = caller_locations.first

    io = StringIO.new

    config = org.jruby.RubyInstanceConfig.new
    config.input = StringIO.new.tap(&:close_write).to_input_stream
    config.output = java.io.PrintStream.new(io.to_output_stream)

    config.load_paths << File.expand_path("../slib", __dir__)
    config.required_libraries << __FILE__

    wrapped_code = kwargs.map { |name, value| "#{name} = Marshal.load(#{Marshal.dump(value).inspect})\n" }.join +
      "include WebMock::API; WebMock.enable!\n" +
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
      {
        "RUBYLIB" => File.expand_path("../slib", __dir__),
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

def pure_subprocess_output(code, command_line: nil, gel: true, variables: {}, chdir: nil)
  source = caller_locations.first

  wrapped_code = variables.map { |name, value| "#{name} = Marshal.load(#{Marshal.dump(value).inspect})\n" }.join +
    "eval(#{code.inspect}, binding, #{source.path.inspect}, #{source.lineno + 1})"

  r, w = IO.pipe

  args = []
  args += command_line if command_line

  env =
    if gel
      {
        "RUBYOPT" => nil,
        "RUBYLIB" => gel.is_a?(String) ? gel : File.expand_path("../slib", __dir__),
        "GEL_STORE" => nil,
        "GEL_LOCKFILE" => nil,
      }
    else
      {
        "RUBYOPT" => nil,
        "RUBYLIB" => nil,
      }
    end

  pid = spawn(
    env,
    RbConfig.ruby,
    *args,
    "-e", wrapped_code,
    in: IO::NULL,
    out: w,
    err: w,
    **chdir.nil? ? {} : { chdir: chdir },
  )

  w.close

  output = []

  t = Process.detach(pid)

  while t.alive?
    output.concat(r.read.lines.map(&:chomp))
  end
  t.join

  output.concat(r.read.lines.map(&:chomp))

  output
end

def jruby?
  RUBY_ENGINE == "jruby"
end

def capture_stdout
  original_stdout = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = original_stdout
end

def assert_nothing_raised
  yield
end
