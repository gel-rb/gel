# frozen_string_literal: true

module Gel::PubGrub
  ##
  # Based on PubGrub::Package, but we need some extra tricks
  class Package
    attr_reader :name
    attr_reader :platform

    def initialize(name, platform)
      @name = name
      @platform = platform
    end

    def inspect
      "#<#{self.class} #{name.inspect} (#{platform})>"
    end

    def <=>(other)
      return 1 if other.is_a?(Pseudo)
      (name <=> other.name).nonzero? || (platform <=> other.platform)
    end

    def to_s
      "#{name} (#{platform})"
    end

    def hash
      name.hash ^ platform.hash
    end

    def eql?(other)
      self.class.eql?(other.class) && name.eql?(other.name) && platform.eql?(other.platform)
    end
    alias == eql?

    class Pseudo
      attr_reader :role

      def initialize(role)
        @role = role
      end

      def inspect
        "#<#{self.class} #{role}>"
      end

      def <=>(other)
        return -1 unless other.is_a?(Pseudo)
        role <=> other.role
      end

      def to_s
        "[[#{role}]]"
      end

      def hash
        role.hash
      end

      def eql?(other)
        self.class.eql?(other.class) && role.eql?(other.role)
      end
      alias == eql?
    end
  end
end
