# frozen_string_literal: true

class Gel::LockParser
  def parse(input)
    sections = []

    input = input.dup
    while input.sub!(/\A(\w.+)\n/, "")
      section = $1

      case section
      when "GIT", "PATH", "GEM"
        content = {}
        while input.sub!(/\A {2}\b([^:]+):(\s)/, "")
          label = $1
          separator = $2

          if separator == "\n"
            value = []
            while input.sub!(/\A {4}\b(.*)\n/, "")
              entry = $1
              children = []
              while input.sub!(/\A {6}\b(.*)\n/, "")
                children << $1
              end
              if children.empty?
                value << [entry]
              else
                value << [entry, children]
              end
            end
            content[label] = value
          else
            input.sub!(/\A(.*)\n/, "")
            (content[label] ||= []) << $1
          end
        end
      when "PLATFORMS", "DEPENDENCIES"
        content = []
        while input.sub!(/\A {2}\b(.*)\n/, "")
          content << $1
        end
      when "BUNDLED WITH", "RUBY VERSION"
        content = []
        while input.sub!(/\A {3}\b(.*)\n/, "")
          content << $1
        end
      end
      input.sub!(/\A\n+/, "")

      sections << [section, content]
    end

    sections
  end
end
