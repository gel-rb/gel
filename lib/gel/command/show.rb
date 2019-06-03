# frozen_string_literal: true

class Gel::Command::Show < Gel::Command
  def run(command_line)
    mode = :human

    until command_line.empty?
      case argument = command_line.shift
      when "--list"; mode = :list
      when "-l"; mode = :list
      when "--paths"; mode = :paths
      when "-p"; mode = :paths
      else
        raise "Unknown argument #{argument.inspect}"
      end
    end

    Gel::Environment.activate(output: $stderr)

    case mode
    when :human
      puts "Gems included by the bundle:"
      gems.each { |gem|
        puts "  * #{gem.name} (#{gem.version})"
      }
    when :list
      puts gems.map(&:name)
    when :paths
      puts gems.map(&:root)
    end
  end

  private
  def gems
    gems_for(Gel::Environment.gemfile.gems)
  end

  def gems_for(gems)
    # Special handling for bundler since it just returns nil if we try to resolve it
    gems.map(&:first).reject { |g| g == 'bundler' }.map { |gem|
      current_gem = Gel::Environment.find_gem(gem)
      raise "Could not find gem #{gem}, have you successfully run gel install?" unless current_gem

      [current_gem, gems_for(current_gem.dependencies)]
    }.flatten.uniq(&:name).sort_by(&:name)
  end
end
