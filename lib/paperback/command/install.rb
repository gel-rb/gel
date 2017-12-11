class Paperback::Command::Install < Paperback::Command
  def run(command_line)
    Paperback::Environment.activate(install: true, output: $stderr)
  end
end
