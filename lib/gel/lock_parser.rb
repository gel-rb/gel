# frozen_string_literal: true

require "strscan"

class Gel::LockParser
  def parse(content)
    sections = []

    scanner = StringScanner.new(content)
    while section = scanner.scan(/^(\w.+)\n/)
      section.chomp!
      case section
      when "GIT", "PATH", "GEM"
        content = {}
        while scanner.skip(/^  \b/)
          label = scanner.scan(/[^:]+:/).chop
          if scanner.skip(/ /)
            value = scanner.scan(/.*/)
            scanner.skip(/\n/)
            (content[label] ||= []) << value
          else
            scanner.skip(/\n/)
            value = []
            while scanner.skip(/^    \b/)
              entry = scanner.scan(/.*/)
              scanner.skip(/\n/)
              children = []
              while scanner.skip(/^      \b/)
                child = scanner.scan(/.*/)
                children << child
                scanner.skip(/\n/)
              end
              if children.empty?
                value << [entry]
              else
                value << [entry, children]
              end
            end
            content[label] = value
          end
        end
      when "PLATFORMS", "DEPENDENCIES"
        content = []
        while scanner.skip(/^  \b/)
          entry = scanner.scan(/.*/)
          content << entry
          scanner.skip(/\n/)
        end
      when "BUNDLED WITH"
        content = []
        while scanner.skip(/^   \b/)
          entry = scanner.scan(/.*/)
          content << entry
          scanner.skip(/\n/)
        end
      end
      scanner.skip(/\n+/)

      sections << [section, content]
    end

    sections
  end
end
