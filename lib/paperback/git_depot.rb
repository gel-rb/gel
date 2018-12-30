# frozen_string_literal: true

class Paperback::GitDepot
  attr_reader :mirror_root

  def initialize(store, mirror_root = "~/.cache/paperback/git")
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
        status = git("remote", "update", chdir: cache_dir)
        raise "git remote update failed" unless status.success?
      end
    else
      status = git("clone", "--mirror", remote, cache_dir)
      raise "git clone --mirror failed" unless status.success?
    end

    cache_dir
  end

  def resolve(remote, ref)
    mirror = remote(remote) { false } # always update mirror

    r, w = IO.pipe
    status = git("rev-parse", ref || "HEAD", chdir: mirror, out: w)
    raise "git rev-parse failed" unless status.success?

    w.close

    r.read.chomp
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
      status = git("rev-list", "--quiet", revision, chdir: cache_dir)
      status.success?
    end

    status = git("clone", mirror, destination)
    raise "git clone --local failed" unless status.success?

    status = git("checkout", "--detach", "--force", revision, chdir: destination)
    raise "git checkout failed" unless status.success?

    destination
  end

  private

  def git(*arguments, **kwargs)
    kwargs[:in] ||= IO::NULL
    kwargs[:out] ||= IO::NULL
    kwargs[:err] ||= IO::NULL

    pid = spawn("git", *arguments, **kwargs)

    _, status = Process.waitpid2(pid)

    status
  end

  def ident(remote)
    short = File.basename(remote, ".git")
    digest = Digest(:SHA256).hexdigest(remote)[0..12]
    "#{short}-#{digest}"
  end
end
