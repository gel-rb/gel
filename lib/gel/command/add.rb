# frozen_string_literal: true

class Gel::Command::Add < Gel::Command
  def run(argv)
    name = argv[0]
    raise Gel::Error::NoGemError if name.nil? || name.empty?
    line = %(gem "#{name}"\n)
    File.open("Gemfile", "a") { |file| file.write(line) }
  end
end
