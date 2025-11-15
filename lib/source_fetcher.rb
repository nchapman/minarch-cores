#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'uri'
require 'thread'
require_relative 'logger'

# Fetch source code for cores (tarballs or git repos)
# Optimizes for speed: tarballs > shallow git clones
class SourceFetcher
  def initialize(cores_dir:, logger: nil, parallel: 4)
    @cores_dir = cores_dir
    @logger = logger || BuildLogger.new
    @parallel = parallel
    @mutex = Mutex.new
    @fetched = 0
    @skipped = 0
    @failed = 0
  end

  def fetch_all(recipes)
    @logger.section("Fetching Sources")
    @logger.info("Cores directory: #{@cores_dir}")
    FileUtils.mkdir_p(@cores_dir)

    # Process in parallel with thread pool
    queue = Queue.new
    recipes.each { |name, metadata| queue << [name, metadata] }

    threads = Array.new(@parallel) do
      Thread.new do
        loop do
          item = queue.pop(true) rescue nil
          break unless item

          name, metadata = item
          fetch_one(name, metadata)
        end
      end
    end

    threads.each(&:join)

    @logger.success("Fetched: #{@fetched}, Skipped: #{@skipped}, Failed: #{@failed}")
  end

  def fetch_one(name, metadata)
    repo_name = metadata['repo']
    url = metadata['url']
    commit = metadata['commit']
    needs_submodules = metadata['submodules']

    target_dir = File.join(@cores_dir, repo_name)

    # Skip if already exists
    if Dir.exist?(target_dir)
      log_thread("Skipping #{name} (already exists)")
      @mutex.synchronize { @skipped += 1 }
      return
    end

    log_thread("Fetching #{name}")

    # Determine fetch strategy
    if url.end_with?('.tar.gz', '.zip', '.tar.bz2')
      fetch_tarball(url, target_dir, repo_name)
    elsif url.end_with?('.git') || url.include?('github.com') && !url.include?('/archive/')
      fetch_git(url, target_dir, commit, needs_submodules)
    else
      # Assume tarball
      fetch_tarball(url, target_dir, repo_name)
    end

    @mutex.synchronize { @fetched += 1 }
  rescue StandardError => e
    log_thread("Failed to fetch #{name}: #{e.message}", error: true)
    @mutex.synchronize { @failed += 1 }
  end

  private

  def fetch_tarball(url, target_dir, repo_name)
    temp_file = File.join(@cores_dir, "#{repo_name}.tar.gz")
    FileUtils.mkdir_p(target_dir)

    # Download tarball
    run_command("wget", "-q", "-O", temp_file, url)

    # Extract (handle GitHub archive structure)
    run_command("tar", "-xzf", temp_file, "-C", target_dir, "--strip-components=1")

    # Cleanup
    FileUtils.rm_f(temp_file)
  end

  def fetch_git(url, target_dir, commit, needs_submodules)
    # Convert .git URLs to https if needed
    url = url.sub('git://', 'https://') if url.start_with?('git://')

    # Check if commit is a SHA or branch/tag
    if commit && commit =~ /^[0-9a-f]{40}$/
      # Full SHA - need full clone then checkout
      run_command("git", "clone", "--quiet", url, target_dir)
      Dir.chdir(target_dir) do
        run_command("git", "checkout", "--quiet", commit)
        if needs_submodules
          run_command("git", "submodule", "update", "--init", "--recursive", "--quiet")
        end
      end
    else
      # Branch or tag - can use shallow clone
      args = ["git", "clone", "--quiet", "--depth", "1"]
      args += ["--branch", commit] if commit
      args += ["--recurse-submodules"] if needs_submodules
      args += [url, target_dir]

      run_command(*args)
    end
  end

  def run_command(*args)
    stdout, stderr, status = Open3.capture3(*args)

    unless status.success?
      raise "Command failed: #{args.join(' ')}\n#{stderr}"
    end

    stdout
  end

  def log_thread(message, error: false)
    @mutex.synchronize do
      if error
        @logger.error(message)
      else
        @logger.step(message)
      end
    end
  end
end
