source "https://rubygems.org"

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

# We're not using 'gemspec': we can't have real dependencies by design,
# so we instead use our development dependencies to reference the gems
# we vendor.
gem "gel", path: "."

gem "rake", "~> 12.3"
gem "minitest", "~> 5.0", "< 5.16" # Ruby 2.5 compat
gem "mocha"
gem "webmock"

gem "ronn-ng"
