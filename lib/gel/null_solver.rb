# frozen_string_literal: true

class Gel::NullSolver
  NullPackage = Struct.new(:name, :platform)

  def initialize(gemfile:, catalog_set:, platforms:)
    @gemfile = gemfile
    @catalog_set = catalog_set
    @platforms = platforms

    @platform = @platforms.first

    @packages = Hash.new { |h, k| h[k] = NullPackage.new(k, @platform) }

    @solution = {}
    @constraints = Hash.new { |h, k| h[k] = [] }

    @gemfile.gems.each do |name, constraints, options|
      raise "NullSolver can't apply platform constraints" if options[:platforms]
      @constraints[name].concat(constraints || [])
    end
  end

  def solved?
    gems_to_solve.empty?
  end

  def work
    name = gems_to_solve.first

    req = Gel::Support::GemRequirement.new(@constraints[name])

    choice =
      @catalog_set.entries_for(@packages[name]).map(&:gem_version).
      sort_by { |v| [v.prerelease? ? 0 : 1, v] }.
      reverse.find { |v| req.satisfied_by?(v) }

    if choice.nil?
      raise "Failed to resolve #{name.inspect} (#{req.inspect}) given #{@solution.inspect}"
    end

    @solution[name] = choice

    @catalog_set.dependencies_for(@packages[name], choice).each do |dep_name, constraints|
      if @solution[dep_name]
        new_req = Gel::Support::GemRequirement.new(constraints)
        unless new_req.satisfied_by?(@solution[dep_name])
          raise "Already chose #{dep_name.inspect} #{@solution[dep_name]}, which is incompatible with #{name.inspect} #{choice.inspect} (wants #{new_req})"
        end
      else
        @constraints[name].concat(constraints || [])
      end
    end
  end

  def each_resolved_package
    @solution.each do |name, version|
      yield @packages[name], version
    end
  end

  private

  def gems_to_solve
    @constraints.keys - @solution.keys
  end
end
