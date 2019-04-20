# frozen_string_literal: true

class Gel::Command::Lock < Gel::Command
  def run(command_line)
    options = {}

    mode = :hold
    strict = false
    overrides = {}

    until command_line.empty?
      case argument = command_line.shift
      when "--strict" then strict = true
      when "--major" then mode = :major
      when "--minor" then mode = :minor
      when "--patch" then mode = :patch
      when "--hold" then mode = :hold
      when /\A--lockfile(?:=(.*))?\z/
        options[:lockfile] = $1 || command_line.shift
      when /\A((?!-)[A-Za-z0-9_-]+)(?:(?:[\ :\/]|(?=[<>~=]))([<>~=,\ 0-9A-Za-z.-]+))?\z/x
        overrides[$1] = Gel::Support::GemRequirement.new($2 ? $2.split(/\s+(?=[0-9])|\s*,\s*/) : [])
      else
        raise "Unknown argument #{argument.inspect}"
      end
    end

    require_relative "../pub_grub/preference_strategy"
    options[:preference_strategy] = lambda do |loader|
      Gel::PubGrub::PreferenceStrategy.new(loader, overrides, bump: mode, strict: strict)
    end

    Gel::Environment.lock(output: $stderr, **options)
  end
end
