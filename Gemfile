source "https://rubygems.org"

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

# We're not using 'gemspec': we can't have real dependencies by design,
# so we instead use our development dependencies to reference the gems
# we vendor.
gem "gel", path: "."

gem "rake", "~> 12.3"
gem "minitest", "~> 5.0", "< 5.16" # Ruby 2.5 compat
gem "mutex_m" # removed from minitest 2.21.0, but no longer default gem
gem "mocha"
gem "webmock"

# We want `ronn` for generating manpages during a release build, but
# it's awkward to carry as a full dependency, because it pulls in
# Nokogiri, which is too complex to expect to work across all the Ruby
# versions we run in CI.
#
# gem "ronn-ng"
