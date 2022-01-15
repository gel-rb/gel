# frozen_string_literal: true

require "test_helper"

class GelTest < Minitest::Test
  SAFE_STDLIB = %w(rbconfig monitor)

  # These depend on the gems feature, so when comparing against a
  # --disable=gems run, they must be disabled to get an accurate
  # comparison.
  GEM_DEPENDENT_FEATURES = RUBY_VERSION.to_f < 3.1 ? "did_you_mean" : "error_highlight,did_you_mean"

  def test_that_it_has_a_version_number
    refute_nil ::Gel::VERSION
  end

  def test_tests_cannot_see_rubygems_runtime
    assert_nil defined?(::Gem.default_exec_format)
  end

  def test_tests_cannot_see_bundler_runtime
    assert_nil defined?(::Bundler::FileUtils)
  end

  def test_tests_dont_have_rubygems_loaded
    assert_empty $".grep(/(?<!slib\/|compatibility\/|pub_grub\/)rubygems\.rb$/i)
  end

  def test_slib_load_path_loads_gel
    assert_equal ["constant"], pure_subprocess_output(<<-RUBY, gel: true)
      puts defined?(::Gel)
    RUBY
  end

  def test_deprecated_compatibility_load_path_loads_gel
    assert_equal ["constant"], pure_subprocess_output(<<-RUBY, gel: File.expand_path("../lib/gel/compatibility", __dir__))
      puts defined?(::Gel)
    RUBY
  end

  def test_subprocess_helper_sees_real_bundler
    fake_version = pure_subprocess_output(<<-RUBY, gel: true, command_line: ["-r", "bundler"])
      puts Bundler::VERSION
    RUBY

    real_version = pure_subprocess_output(<<-RUBY, gel: false, command_line: ["-r", "bundler"])
      puts Bundler::VERSION
    RUBY

    refute_equal fake_version, real_version
  end

  def test_only_expected_files_are_loaded
    base_ruby_only = files_required_at_boot(gel: false, command_line: ["--disable=gems"])
    with_gel = files_required_at_boot(gel: true, command_line: ["--disable=#{GEM_DEPENDENT_FEATURES}"])

    loaded_files = with_gel - base_ruby_only

    # Loading our own files is fine
    loaded_files.delete_if { |path| path.start_with?(File.expand_path("..", __dir__)) }

    # SAFE_STDLIB is.. safe
    loaded_files = loaded_files.grep_v(
      /^
        #{Regexp.union(RbConfig::CONFIG["rubyarchdir"], RbConfig::CONFIG["rubylibdir"])}
        \/
        #{Regexp.union(SAFE_STDLIB)}
        \.
        #{Regexp.union(*["rb", RbConfig::CONFIG["DLEXT"], RbConfig::CONFIG["DLEXT2"]].compact)}
      $/x
    )

    # That's it.. there shouldn't be anything else
    assert_empty loaded_files
  end

  def test_only_expected_constants_are_defined
    # These files are not loaded by default, but are known to be safe for
    # us to load (not gemified, and unlikely to be gemified in future).
    extra_requires = SAFE_STDLIB.flat_map { |r| ["-r", r] }

    base_ruby_only = constants_visible_at_boot(gel: false, command_line: ["--disable=gems", *extra_requires])
    with_gel = constants_visible_at_boot(gel: true, command_line: ["--disable=#{GEM_DEPENDENT_FEATURES}", "-r", "bundler"])
    with_bundler = constants_visible_at_boot(gel: false, command_line: ["--disable=#{GEM_DEPENDENT_FEATURES}", "-r", "bundler"])

    unique_constants = (with_gel - with_bundler).grep_v(/^Gel::/)
    compatible_constants = (with_gel - base_ruby_only - unique_constants).grep_v(/^Gel::/)

    assert_equal %w(
      Gel
    ).join("\n"), unique_constants.join("\n")

    assert_equal %w(
      Bundler
      Bundler::LockfileParser
      Bundler::ORIGINAL_ENV
      Bundler::RubygemsIntegration
      Bundler::VERSION

      Gem
      Gem::Dependency
      Gem::Deprecate
      Gem::LoadError
      Gem::Platform
      Gem::Platform::CURRENT
      Gem::Platform::RUBY
      Gem::Requirement
      Gem::Requirement::BadRequirementError
      Gem::Requirement::DefaultRequirement
      Gem::Requirement::OPS
      Gem::Requirement::PATTERN
      Gem::Requirement::PATTERN_RAW
      Gem::Requirement::SOURCE_SET_REQUIREMENT
      Gem::Specification
      Gem::VERSION
      Gem::Version
      Gem::Version::ANCHORED_VERSION_PATTERN
      Gem::Version::VERSION_PATTERN
    ).join("\n"), compatible_constants.join("\n")
  end

  private

  def files_required_at_boot(gel:, command_line:)
    pure_subprocess_output(<<-RUBY, gel: gel, command_line: command_line)
      puts $"
    RUBY
  end

  def constants_visible_at_boot(gel:, command_line:)
    pure_subprocess_output(<<-RUBY, gel: gel, command_line: command_line)
      def walk(scope, parent_modules = [], parent_names = [])
        parent_modules += [scope]

        scope.constants(false).sort.each do |name|
          full_name = parent_names + [name]

          puts full_name.join("::")

          if ((child = scope.const_get(name)) rescue nil) && child.is_a?(::Module)
            next if parent_modules.include?(child)

            walk(child, parent_modules, full_name)
          end
        end
      end

      walk(Object)
    RUBY
  end
end
