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
    return target_platform if available_platforms.include?(target_platform)

    SYNONYMS.each do |row|
      next unless row.include?(target_platform)

      overlap = row & available_platforms
      return overlap.first unless overlap.empty?
    end

    return "ruby" if available_platforms.include?("ruby")

    nil
  end
end
