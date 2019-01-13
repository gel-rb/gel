# frozen_string_literal: true

class Paperback::Command::Lock < Paperback::Command
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
        overrides[$1] = Paperback::Support::GemRequirement.new($2 ? $2.split(/\s+(?=[0-9])|\s*,\s*/) : [])
      else
        raise "Unknown argument #{argument.inspect}"
      end
    end

    require_relative "../pub_grub/preference_strategy"
    options[:preference_strategy] = lambda do |loader|
      Paperback::PubGrub::PreferenceStrategy.new(loader, overrides, bump: mode, strict: strict)
    end

    Paperback::Environment.lock(output: $stderr, **options)
  end
end
