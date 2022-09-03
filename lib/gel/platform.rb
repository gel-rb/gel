# frozen_string_literal: true

module Gel::Platform
  SYNONYMS = [
    ["ruby", "mri", "rbx"],
    ["java", "jruby"],
    ["x64-mingw32", "mswin64", "x64_mingw"],
    ["x86-mingw32", "mswin", "mingw"],
  ]

  def self.filter(target_platforms, filter)
    # Ignore ruby-version constraint tails ("mri_23" => "mri")
    filter = filter.map { |f| f.sub(/_[0-9]+\z/, "") }

    target_platforms.select do |platform|
      next true if filter.include?(platform)

      SYNONYMS.any? do |row|
        row.include?(platform) && !(row & filter).empty?
      end
    end
  end

  def self.match(target_platform, available_platforms)
    matcher = Gel::Support::GemPlatform.new(target_platform)

    return available_platforms.include?("ruby") ? "ruby" : nil if matcher == "ruby"

    matches = available_platforms.select do |candidate|
      matcher =~ candidate
    end.sort_by { |candidate| candidate&.size || 0 }.reverse

    matches << "ruby" if available_platforms.include?("ruby")

    matches.first
  end
end
