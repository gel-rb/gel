# frozen_string_literal: true

class Gel::Command::Lock < Gel::Command
  def run(command_line)
    options = {}

    mode = :hold
    strict = false
    overrides = {}

    until command_line.empty?
      case argument = command_line.shift
      when "--strict"; strict = true
      when "--major"; mode = :major
      when "--minor"; mode = :minor
      when "--patch"; mode = :patch
      when "--hold"; mode = :hold
      when /\A--lockfile(?:=(.*))?\z/
        options[:lockfile] = $1 || command_line.shift
      when /\A((?!-)[A-Za-z0-9_-]+)(?:(?:[\ :\/]|(?=[<>~=]))([<>~=,\ 0-9A-Za-z.-]+))?\z/x
        overrides[$1] = Gel::Support::GemRequirement.new($2 ? $2.split(/\s+(?=[0-9])|\s*,\s*/) : [])
      else
        raise "Unknown argument #{argument.inspect}"
      end
    end

    require_relative "../pub_grub/preference_strategy"
    options[:preference_strategy] = lambda do |gem_set|
      Gel::PubGrub::PreferenceStrategy.new(gem_set, overrides, bump: mode, strict: strict)
    end

    Gel::Environment.write_lock(output: $stderr, **options)
  end
end
