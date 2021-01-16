<p align="center"><a href="https://gel.dev"><img src="https://gel.dev/images/gel.svg" width="150" /></a></p>

# Gel

A modern gem manager.

Gel is a lightweight alternative to Bundler.

|         |         Gel        | Bundler & Rubygems |
|---------|--------------------|--------------------|
| install | :white_check_mark: | :white_check_mark: |
| update  | :white_check_mark: | :white_check_mark: |
| lock    | :white_check_mark: | :white_check_mark: |
| exec    | :white_check_mark: | :white_check_mark: |
| gem authoring | :x: | :white_check_mark: |
| vendoring     | :x: | :white_check_mark: |
| anything else | :x: | :white_check_mark: |

This gem is still a work in progress, and things that are still needing some additional improvements include Documentation, UI & Error Messages, and Platform compatibility. We are open to and appreciate any help improving any of these areas.

## Why Should I Use Gel?

Gel was written with the goal of improving the performance of common Bundler tasks. Eventually we would like to backport known performance improvements back into Bundler so that everyone can benefit from these improvements, but it is easier to implement and test potential performance improvements in a smaller, more lightweight codebase beforehand.

Another way that Gel gains a performance benefit over Bundler is simply that Gel includes less features overall. For anyone that doesn't need _all_ the features provided by Bundler, using Gel as a more lightweight gem manager might be beneficial.

One of the improvements that Gel has over Bundler is being able to take advantage of a new version solver called [Pub Grub](https://medium.com/@nex3/pubgrub-2fb6470504f). Gel utilizes the `pub_grub` gem (https://github.com/jhawthorn/pub_grub) which is a Ruby port of the PubGrub algorithm.

Some real world examples of the types of performance improvements Gel provides over Bundler are as follows:

* `% gel exec rake -version`: 55% faster than `bundle`
* `% gel exec rails --version`: 60% faster than `bundle`
* `% gel exec rails runner nil`: 45% faster than `bundle`

Comparing using a complex, mature Rails application:

* `% gel install`: 55% faster than `bundle`
* `% gel lock`: 78% faster than `bundle` on first run
* `% gel lock`: 95% faster than `bundle` on later runs (cache exists)


Comparing using a simple Gemfile with a complex gem:

```
source "https://rubygems.org"

gem "tty"
```

* `% gel install`: 70% faster than `bundle`
* `% gel lock`: 34% faster than `bundle`

Comparing using an example Gemfile with gems that showcase a difficult version resolving:

```
source "https://rubygems.org"

gem "activerecord"
gem "quiet_assets"
```

* `% gel lock`: 96% faster than `bundle`

This example showcases the speed improvements provided by the new PubGrub Version Solving algorithm.

Note that all of the performance numbers were gathered using just a regular laptop used for common day-to-day development. These numbers were not measured in perfect isolation and your experience may vary.

## Installation

If you're on a Mac, we recommend that you install via Homebrew:

    $ brew install gel

Otherwise, you can install Gel as a gem:

    $ gem install gel

Then, either activate Gel in your current shell:

    $ eval "$(gel shell-setup)"

Or add it to your `.bashrc` or `.zshrc` to enable it everywhere:

    $ echo 'eval "$(gel shell-setup)"' >> ~/.bashrc

## Usage

Use `gel install`, `gel lock`, `gel update`, and `gel exec` as you would the equivalent `bundle` subcommands.

## ENVIRONMENT VARIABLES

* `GEL_GEMFILE`
  The path to the gemfile gel should use

* `GEL_LOCKFILE`
  The path to the lockfile that gel should use

* `GEL_CACHE`
  The path to the gel version information cache

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/rake test` to run the tests.

To use your development instance as your primary Gel, add its `exe/` to your `$PATH` before running `shell-setup`, ensuring it comes before any RubyGems `bin` directory that might override it.

For example:

```sh
PATH="$HOME/projects/gel/exe:$PATH"
eval "$(gel shell-setup)"
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/gel-rb/gel. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Gel project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/gel-rb/gel/blob/main/CODE_OF_CONDUCT.md).
