<p align="center"><a href="https://gel.dev"><img src="https://gel.dev/images/gel.svg" width="150" /></a></p>

# Gel

A modern gem manager.

Gel is a lightweight alternative to Bundler.

Through a combination of algorithm choices and skipping compatibility
with some legacy features that date back to the earliest days of
RubyGems, Gel is able to outperform both Bundler and RubyGems in many
common use cases.

In making this trade, Gel chooses not to support some less frequently
used, but independently valuable, Bundler features:

|         |         Gel        | Bundler & Rubygems |
|---------|--------------------|--------------------|
| install | :white_check_mark: | :white_check_mark: |
| update  | :white_check_mark: | :white_check_mark: |
| lock    | :white_check_mark: | :white_check_mark: |
| exec    | :white_check_mark: | :white_check_mark: |
| gem authoring | :x:  | :white_check_mark: |
| vendoring     | :ok: | :white_check_mark: |
| anything else | :x:  | :white_check_mark: |

In most cases, Gel will be a drop-in replacement, and you can still use
RubyGems directly if you need to `gem push`, for example.

## Can I Use Gel Today?

I ([@matthewd](https://github.com/matthewd)) have been using Gel
exclusively on my local development machines since January 2019. While I
have occasionally encountered issues when installing some new gem, they
have been rare and minor, requiring only a small additional API or
similar -- and as those outliers have been addressed, they become
increasingly infrequent.

In particular (and as is consistent with the type of work it does), Gel
will either work or it will fail -- perhaps on encountering an unusual
construct in your Gemfile, or perhaps while attempting to install a gem
that does something weird. The "latest" it is likely to fail is if, at
runtime, your code (or a gem you've loaded) assumes the presence of a
specific RubyGems/Bundler API that Gel does not emulate. It's extremely
rare to encounter more subtle issues that don't manifest as immediate
failure.

You can use Gel in your local environment with no effect upon your
production setup, or even your coworkers' -- Gel uses the same Gemfile
and Gemfile.lock files as Bundler. It also maintains completely
independent copies of installed gems, so it's totally safe to co-exist
with Bundler on your machine. (Which one is active is determined by the
environment variables within your shell terminal.)

## Why Should I Use Gel?

Gel was written with the goal of improving the performance of common
Bundler tasks.

By focusing on those common requirements, and leaving more obscure needs
to be filled by Bundler, Gel is able to outperform Bundler in the
operations you use most.

Gel also uses a new version solving algorithm called [Pub
Grub](https://medium.com/@nex3/pubgrub-2fb6470504f) to resolve
dependencies between gems, via the `pub_grub` gem
(https://github.com/jhawthorn/pub_grub).

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

Use `gel install`, `gel lock`, `gel update`, and `gel exec` as you would
the equivalent `bundle` subcommands.

While it will work, in general you should not actually need to use `gel
exec` directly -- installed gems' executables will automatically respect
the locally locked versions where appropriate.

Where you would previously have run `bundle exec rubocop` or
`bundle exec rake` inside an application directory, you can run
`rubocop` or `rake` and expect the same results, even if you have other
versions of those gems installed.

## ENVIRONMENT VARIABLES

* `GEL_GEMFILE`
  The path to the gemfile gel should use

* `GEL_LOCKFILE`
  The path to the lockfile that gel should use

* `GEL_CACHE`
  The path to the gel version information cache

* `GEL_AUTH`
  Gem server credentials as a space-separated list of URIs, e.g.:
  "http://user:pass@ruby.example.com/ http://user2:pass2@gems.example.org/"

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
