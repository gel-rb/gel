# frozen_string_literal: true

require_relative "vendor/ruby_digest"

class Gel::GitDepot
  attr_reader :mirror_root

  def initialize(store, mirror_root = (ENV["GEL_CACHE"] || "~/.cache/gel") + "/git")
    @store = store
    @mirror_root = File.expand_path(mirror_root)
  end

  def git_path(remote, revision)
    short = File.basename(remote, ".git")
    File.join(@store.root, "git", "#{short}-#{revision[0..12]}")
  end

  # Returns a path containing a local mirror of the given remote.
  #
  # If the mirror already exists, yields the path (same as the return
  # value); if the block returns false the mirror will be updated.
  def remote(remote)
    cache_dir = "#{@mirror_root}/#{ident(remote)}"

    if Dir.exist?(cache_dir)
      if block_given? && !yield(cache_dir)
        # The block didn't like what it saw; try updating the mirror
        # from upstream
        status = git(remote, "remote", "update", chdir: cache_dir)
        raise "git remote update failed" unless status.success?
      end
    else
      status = git(remote, "clone", "--mirror", remote, cache_dir)
      raise "git clone --mirror failed" unless status.success?
    end

    cache_dir
  end

  def resolve(remote, ref)
    if ref
      # ref could be an arbitrarily-complex ref (HEAD~3 or whatever), so
      # update our mirror and then resolve it locally

      mirror = remote(remote) { false } # always update mirror

      r, w = IO.pipe
      status = git(remote, "rev-parse", ref || "HEAD", chdir: mirror, out: w)
      w.close

      if status.success?
        r.read.chomp
      else
        # We didn't keep stderr, but we can infer the nature of the problem
        # from whether git produced any output: for simple "I don't know what
        # that is" errors, it returns the input, while more fundamental
        # problems die earlier and return nothing.
        if r.read.chomp.empty?
          # This is an internal error: our mirror must be broken
          raise "git rev-parse failed"
        else
          # This is a user error: the ref doesn't exist
          raise Gel::Error::GitResolveError.new(remote: remote, ref: ref)
        end
      end
    else
      # If we just want to know the remote HEAD, we can ask without even
      # touching our mirror

      r, w = IO.pipe
      status = git(remote, "ls-remote", remote, "HEAD", out: w)
      raise "git ls-remote failed" unless status.success?

      w.close
      r.read.split.first
    end
  end

  def resolve_and_checkout(remote, ref)
    revision = resolve(remote, ref)
    [revision, checkout(remote, revision)]
  end

  def checkout(remote, revision)
    destination = git_path(remote, revision)
    return destination if Dir.exist?(destination)

    mirror = remote(remote) do |cache_dir|
      # Check whether the revision is already in our mirror
      status = git(remote, "rev-list", "--quiet", revision, chdir: cache_dir)
      status.success?
    end

    status = git(remote, "clone", mirror, destination)
    raise "git clone --local failed" unless status.success?

    status = git(remote, "checkout", "--detach", "--force", revision, chdir: destination)
    raise "git checkout failed" unless status.success?

    destination
  end

  private

  def git(remote, *arguments, **kwargs)
    kwargs[:in] ||= IO::NULL
    kwargs[:out] ||= IO::NULL
    kwargs[:err] ||= IO::NULL

    t = Time.now
    pid = spawn("git", *arguments, **kwargs)
    logger&.debug { "#{remote} [#{pid}] #{command_for_log("git", *arguments)}" }

    _, status = Process.waitpid2(pid)
    logger&.debug { "#{remote} [#{pid}]   process exited #{status.exitstatus} (#{status.success? ? "success" : "failure"}) after #{Time.now - t}s" }

    status
  end

  def ident(remote)
    short = File.basename(remote, ".git")
    digest = Gel::Vendor::RubyDigest::SHA256.hexdigest(remote)[0..12]
    "#{short}-#{digest}"
  end

  if $DEBUG
    require "shellwords"
    def shellword(word)
      if word =~ /\A[A-Za-z0-9=+\/,.-]+\z/
        word
      elsif word =~ /'/
        "\"#{Shellwords.shellescape(word).gsub(/\\\s/, "\\1")}\""
      else
        "'#{word}'"
      end
    end

    def command_for_log(*parts)
      parts.map { |part| shellword(part) }.join(" ")
    end

    require_relative "logger"
    Logger = Gel::Logger.new($stderr)

    def logger
      Logger
    end
  else
    def logger
    end
  end
end
