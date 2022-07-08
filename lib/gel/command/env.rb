# frozen_string_literal: true

class Gel::Command::Env < Gel::Command
  GEL_ROOT = File.expand_path("../../..", __dir__)
  SELF_BIN = File.expand_path("exe/gel", GEL_ROOT)
  HOME_PREFIX = File.join(File.expand_path("~"), "")

  def run(command_line)
    base_store = Gel::Environment.store
    base_store = base_store.inner if base_store.is_a?(Gel::LockedStore)

    config_file = Gel::Environment.config.path

    gemfile = Gel::Environment.find_gemfile(error: false)

    puts
    puts "#### Gel Environment ####"
    puts "```"
    path_entry "Context", Dir.pwd
    if gemfile
      path_entry "  Gemfile", gemfile
      path_entry "  Lockfile", Gel::Environment.lockfile_name(gemfile)
    end
    puts
    gel_version = Gel::VERSION
    if File.exist?(File.expand_path(".git", GEL_ROOT))
      gel_version = "git #{git_revision(GEL_ROOT)} (#{gel_version})"
    end
    text_entry "Gel", gel_version
    path_entry "  bin", SELF_BIN
    path_entry "  Store", base_store.root
    path_entry "  Cache", Gel::Config.cache_dir
    path_entry "  Config", config_file
    puts
    text_entry "Ruby", RUBY_DESCRIPTION
    path_entry "  bin", Gem.ruby
    list_entry "  RUBYLIB", ENV['RUBYLIB']&.split(File::PATH_SEPARATOR) || [], subtype: :path
    text_entry "  RUBYOPT", ENV['RUBYOPT']
    puts
    text_entry "System", ""
    path_entry "  ~", File.expand_path("~")
    # This doesn't use :path, because a raw '~' in PATH is noteworthy
    list_entry "  PATH", ENV['PATH']&.split(File::PATH_SEPARATOR) || []
    path_entry "  SHELL", ENV['SHELL'] || "-"
    puts "```"

    if command_line.include?("-v") || command_line.include?("--verbose")
      puts
      puts "#### Commands ####"
      puts "```"
      {
        "gel" => SELF_BIN,
        "ruby" => Gem.ruby,
        "gem" => File.expand_path("../gem", Gem.ruby),
        "bundle" => File.expand_path("../bundle", Gem.ruby),
      }.each do |name, expected|
        if actual = which(name)
          text_entry name, abbreviated_path(actual), flag: actual == expected ? "" : "!"
        else
          text_entry name, "(not present)", flag: "?"
        end
      end

      puts
      stub_set = Gel::Environment.store.stub_set
      if stub_dir = stub_set&.dir
        if ENV["PATH"].split(File::PATH_SEPARATOR).map { |s| File.expand_path(s) }.include?(File.expand_path(stub_dir))
          stubs = stub_set.all_stubs
          if stubs.empty?
            puts "# No stubs present"
          else
            good_stubs, broken_stubs =
              stubs.map { |stub| [stub, which(stub)] }.
              partition { |_, actual| stub_set.own_stub?(actual) }

            puts "# #{good_stubs.size} active stubs in #{abbreviated_path(stub_dir)}"
            unless broken_stubs.empty?
              puts "# #{broken_stubs.size} stubs broken"
              broken_stubs.sort_by { |x, y| [y || "", x] }.each do |name, actual|
                if actual
                  text_entry name, abbreviated_path(actual) + " (#{stub_type(actual, stub_set)})", flag: "!"
                else
                  text_entry name, "(not found)", flag: "?"
                end
              end
            end
          end
        else
          puts "# Stub directory #{abbreviated_path(stub_dir)} not in PATH"
          stubs = stub_set.all_stubs
          puts "# #{stubs.size} stubs present"
        end
      else
        puts "# No stub directory"
      end
      puts "```"

      puts
      puts "#### Runtime ####"
      puts "```"
      $LOADED_FEATURES.each do |name|
        puts abbreviated_path(name)
      end
      puts "```"

      puts
      puts "#### Load Path ####"
      puts "```"
      $LOAD_PATH.each do |name|
        puts abbreviated_path(name)
      end
      puts "```"

      puts
      puts "#### Files ####"

      file_body config_file

      if gemfile
        file_body gemfile
        file_body Gel::Environment.lockfile_name(gemfile)
      end
    end

    puts
  end

  private

  def abbreviated_path(path)
    path = File.expand_path(path)
    if path.start_with?(HOME_PREFIX)
      File.join("~", path[HOME_PREFIX.length..-1])
    else
      path
    end
  end

  def text_entry(label, value, flag: nil)
    puts("%-16s %1s %s" % [label, flag, value])
  end

  def path_entry(label, path)
    text_entry(label, abbreviated_path(path), flag: File.exist?(path) ? "" : "?")
  end

  def list_entry(label, list, subtype: :text)
    if list.empty?
      text_entry(label, "(none)")
    else
      first, *rest = list
      send("#{subtype}_entry", label, first)
      rest.each do |item|
        send("#{subtype}_entry", "", item)
      end
    end
  end

  def file_body(path)
    puts
    puts "##### `#{abbreviated_path(path)}` #####"
    if File.exist?(path)
      puts "```"
      puts File.read(path)
      puts "```"
    else
      puts "(not present)"
    end
  end

  def which(name)
    ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
      if File.exist?(file = File.join(path, name)) && File.executable?(file)
        return file
      end
    end
    nil
  end

  def stub_type(path, stub_set)
    if stub_set.parse_stub(path)
      return "gel stub"
    end

    content = File.read(path, 512)
    if content.include?("This file was generated by Bundler")
      return "bundler stub"
    end

    if content.include?("This file was generated by RubyGems") ||
        content.include?("Gem.activate_bin_path(") ||
        content.include?("Gem.bin_path(")
      return "gem stub"
    end

    if content.match?(/\A#!.*ruby/)
      return "ruby stub"
    end

    if content.start_with?("#!")
      "script"
    else
      "binary"
    end
  end

  def git_revision(path)
    require "shellwords"
    `git -C #{Shellwords.escape path} rev-parse --short HEAD`.strip
  end
end
