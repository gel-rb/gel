# frozen_string_literal: true

class Paperback::GitDepot
  attr_reader :mirror_root

  require "logger"
  Logger = ::Logger.new($stderr)
  Logger.level = $DEBUG ? ::Logger::DEBUG : ::Logger::WARN

  def initialize(store, cache: "~/.cache/paperback")
    @store = store
    @mirror_root = File.expand_path("#{cache}/git")

    @github_disabled = false
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

  def current_revision(mirror, remote, ref)
    read_git(remote, "rev-parse", ref, chdir: mirror)
  end

  def get_config(dir, name, type: nil, default: nil)
    arguments = []
    arguments.append("--type", type) if type
    arguments.append("--default", default) if default

    read_git(dir, "config", *arguments, "--get", name, chdir: dir)
  end

  def set_config(dir, name, value, type: nil)
    arguments = []
    arguments.append("--type", type) if type

    status = git(dir, "config", *arguments, "--replace-all", name, value, chdir: dir)
    raise "git config failed" unless status.success?
  end

  def resolve(remote, ref)
    ref ||= "HEAD"

    mirror = remote(remote) do |cache_dir|
      if github?(remote)
        current = current_revision(cache_dir, remote, ref)

        # If we can, it's faster to ask GitHub's API whether our mirror
        # is up to date
        return current if github_current?(remote, ref, current, cache_dir)
      end

      # Other than that special case, we never consider the mirror up to
      # date (i.e., we always do an update)
      false
    end

    current_revision(mirror, remote, ref)
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

  def github?(remote)
    return false if @github_disabled

    case remote
    when /\A(?:git|https?):\/\/github\.com\/([^\/]+\/[^\/]+)/
      $1.sub(/\.git$/, "")
    when /\Agit@github\.com:([^\/]+\/[^\/]+)/
      $1.sub(/\.git$/, "")
    end
  end

  def github_current?(remote, ref, known_revision, cache_dir)
    if org_and_repo = github?(remote)
      allowed = get_config(cache_dir, "paperback.github", default: "true", type: "bool")
      return false unless allowed == "true"

      uri = URI("https://api.github.com/repos/#{org_and_repo}/commits/#{ref}")

      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/vnd.github.v3.sha"
      request["If-None-Match"] = "\"#{known_revision}\""

      response = httpool.request(uri, request)
      case response
      when Net::HTTPOK
        response.body
      when Net::HTTPNotModified
        known_revision
      when Net::HTTPNotFound
        if response["X-GitHub-Media-Type"] == "github.v3, param=sha"
          # We're talking to the API we intended to; this 404 suggests
          # it's not a public repo. We'll remember that and not bother
          # trying this again. (But we won't set @github_disabled,
          # because we still want to try other repos.)
          set_config cache_dir, "paperback.github", "false", type: "bool"

          nil
        else
          @github_disabled = true
          nil
        end
      else
        @github_disabled = true
        nil
      end
    end
  end

  def httpool
    @httpool ||= Paperback::Httpool.new
  end

  def read_git(label, command, *arguments, **kwargs)
    output = nil

    r, w = IO.pipe
    status = git(label, command, *arguments, **kwargs, out: w) do
      w.close
      output = r.read
    end

    raise "git #{command} failed" unless status.success?

    output.chomp
  end

  def git(label, *arguments, **kwargs)
    kwargs[:in] ||= IO::NULL
    kwargs[:out] ||= IO::NULL
    kwargs[:err] ||= IO::NULL

    t = Time.now
    pid = spawn("git", *arguments, **kwargs)
    logger.debug { "#{label} [#{pid}] #{command_for_log("git", *arguments)}" }

    yield if block_given?

    _, status = Process.waitpid2(pid)
    logger.debug { "#{label} [#{pid}]   process exited #{status.exitstatus} (#{status.success? ? "success" : "failure"}) after #{Time.now - t}s" }

    status
  end

  def ident(remote)
    short = File.basename(remote, ".git")
    digest = Digest(:SHA256).hexdigest(remote)[0..12]
    "#{short}-#{digest}"
  end

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

  def logger
    Logger
  end
end
