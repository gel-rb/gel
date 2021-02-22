# frozen_string_literal: true

module Gel::PubGrub
  class PreferenceStrategy
    def initialize(gem_set, overrides, bump: :major, strict: false)
      @gem_set = gem_set
      @overrides = overrides
      @bump = bump
      @strict = strict
    end

    # Overrides first, then packages for which we have a preference (and
    # that preference is still in play), then everything else.
    def package_priority(package, versions)
      if package.is_a?(Package::Pseudo)
        -1000
      elsif @overrides.key?(package.name)
        -100
      elsif range = ranges[package.name]
        yes, no = versions.partition { |version| range.satisfied_by?(version) }
        if yes.any? && no.any?
          -50
        else
          0
        end
      else
        0
      end
    end

    def sort_versions_by_preferred(package, versions)
      return versions if @strict # already filtered
      return versions unless range = ranges[package.name]
      versions.partition { |version| range.satisfied_by?(version) }.inject(:+)
    end

    def refresh_git?(name)
      @overrides.key?(name) || @bump != :hold
    end

    def constraints
      ranges = @strict ? ranges() : @overrides

      result = {}
      ranges.each do |package_name, range|
        result[package_name] = [range] if range
      end
      result
    end

    private

    def ranges
      @ranges ||=
        begin
          result = @overrides.dup
          @gem_set.gems.each do |name, resolved_gems|
            next if @overrides.key?(name)

            result[name] = range_for(resolved_gems.first.version, @bump)
          end
          result.delete_if { |_, v| !v }
          result
        end
    end

    def range_for(version, bump)
      version = Gel::Support::GemVersion.new(version)

      case bump
      when :major
        Gel::Support::GemRequirement.new ">= #{version}"
      when :minor
        next_major = version.bump
        next_major = next_major.bump while next_major.segments.size > 2
        Gel::Support::GemRequirement.new [">= #{version}", "< #{next_major}"]
      when :patch
        next_minor = version.bump
        next_minor = next_minor.bump while next_minor.segments.size > 3
        Gel::Support::GemRequirement.new [">= #{version}", "< #{next_minor}"]
      when :hold
        Gel::Support::GemRequirement.new "= #{version}"
      end
    end
  end
end
