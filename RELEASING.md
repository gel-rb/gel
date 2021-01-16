# Releasing Gel

1. Bump the version in `lib/gel/version.rb`
1. `gel lock`
1. `rake build`
1. `git commit`
1. `git tag vX.Y.Z`
1. `git push --tags origin main vX.Y.Z`
1. On GitHub, convert the tag to a release, and write a changelog
1. `gem push pkg/gel-X.Y.Z.gem`
1. `brew bump-formula-pr --url=https://github.com/gel-rb/gel/archive/vX.Y.Z.tar.gz`
1. Tweet a link to https://github.com/gel-rb/gel/releases/tag/vX.Y.Z
