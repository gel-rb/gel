# frozen_string_literal: true

class Paperback::Command::Lock < Paperback::Command
  def run(command_line)
    options = {}

    if command_line.first =~ /\A--lockfile=(.*)/
      options[:lockfile] = $1
    end

    Paperback::Environment.lock(output: $stderr, **options)
  end
end
