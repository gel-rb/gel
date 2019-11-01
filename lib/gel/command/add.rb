# frozen_string_literal: true

class Gel::Command::Add < Gel::Command
  def run(argv)
    name = argv[0]
    raise Gel::Error::NoGemError if name.nil? || name.empty?

    line = %(gem "#{name}"\n)
    old_gemfile = IO.read(Gel::Environment.find_gemfile)
    new_gemfile = old_gemfile + line

    IO.write(Gel::Environment.find_gemfile, new_gemfile)
    Gel::Environment.write_lock(output: $stdout)
  rescue StandardError => exception
    File.write("Gemfile", old_gemfile)
    puts exception.message
  end
end
