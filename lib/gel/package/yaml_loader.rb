# frozen_string_literal: true

module Gel
  class Package
    class YAMLLoader < ::YAML::ClassLoader::Restricted
      #--
      # Based on YAML.safe_load
      def self.load(yaml, filename)
        result = if Psych::VERSION < "3.1" # Ruby 2.5 & below
                   ::YAML.parse(yaml, filename)
                 else
                   ::YAML.parse(yaml, filename: filename)
                 end
        return unless result

        class_loader = self.new
        scanner      = ::YAML::ScalarScanner.new class_loader

        visitor = ::YAML::Visitors::ToRuby.new scanner, class_loader
        visitor.accept result
      end

      def initialize
        super(%w(Symbol Time Date), [])
      end

      def find(klass)
        case klass
        when "Gem::Specification"
          Gem_Specification
        when "Gem::Version"
          Gem_Version
        when "Gem::Version::Requirement", "Gem::Requirement"
          Gem_Requirement
        when "Gem::Platform"
          Gem_Platform
        when "Gem::Dependency"
          Gem_Dependency
        else
          super
        end
      end

      class Gem_Specification
        attr_accessor :architecture, :bindir, :executables, :name, :platform, :require_paths, :specification_version, :version, :dependencies, :extensions, :required_ruby_version
      end
      class Gem_Dependency
        attr_accessor :name, :requirement, :type, :version_requirements
      end
      class Gem_Platform; end
      Gem_Version = Gel::Support::GemVersion
      class Gem_Requirement
        attr_accessor :requirements
      end
    end
  end
end
