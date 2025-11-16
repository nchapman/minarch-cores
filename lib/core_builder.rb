#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'thread'
require_relative 'logger'
require_relative 'cpu_config'
require_relative 'command_builder'

# Build individual libretro cores with cross-compilation
# Handles both Make and CMake builds
class CoreBuilder
  def initialize(cores_dir:, output_dir:, cpu_config:, logger: nil, parallel: 1, dry_run: false)
    @cores_dir = cores_dir
    @output_dir = output_dir
    @cpu_config = cpu_config
    @logger = logger || BuildLogger.new
    @parallel = parallel
    @dry_run = dry_run
    @mutex = Mutex.new
    @built = 0
    @failed = 0
    @skipped = 0

    # Initialize command builder for generating build commands
    @command_builder = CommandBuilder.new(cpu_config: @cpu_config, parallel: @parallel)

    FileUtils.mkdir_p(@output_dir)
  end

  def build_all(recipes)
    @logger.section("Building Cores for #{@cpu_config.family}")
    @logger.info("Architecture: #{@cpu_config.arch}")
    @logger.info("Toolchain: #{@cpu_config.target_cross}gcc")
    @logger.info("Output: #{@output_dir}")
    @logger.info("Dry run: #{@dry_run}") if @dry_run

    # Build sequentially for now (parallel builds can cause issues)
    recipes.each do |name, metadata|
      build_one(name, metadata)
    end

    @logger.summary(built: @built, failed: @failed, skipped: @skipped)
    @built > 0 ? 0 : 1
  end

  def build_one(name, metadata)
    repo_name = metadata['repo']
    build_type = metadata['build_type']
    core_dir = File.join(@cores_dir, repo_name)

    unless Dir.exist?(core_dir)
      log_error(name, "Directory not found: #{core_dir}")
      @failed += 1
      return
    end

    @logger.step("Building #{name} (#{build_type})")

    if @dry_run
      @logger.detail("[DRY RUN] Would build #{name}")
      @built += 1
      return
    end

    # Apply patches before building
    apply_patches(name, core_dir)

    # Clean before building to prevent contamination
    clean_before_build(name, build_type, metadata, core_dir)

    result = case build_type
             when 'cmake'
               build_cmake(name, metadata, core_dir)
             when 'make'
               build_make(name, metadata, core_dir)
             else
               log_error(name, "Unknown build type: #{build_type}")
               @failed += 1
               nil
             end
    result # Return the path to the built .so file (or nil if failed)
  rescue StandardError => e
    log_error(name, "Build failed: #{e.message}")
    @failed += 1
    nil
  end

  private

  def run_prebuild_steps(name, core_dir)
    # Core-specific pre-build steps can be added here if needed
  end

  def apply_patches(name, core_dir)
    # Check if there are patches for this core
    patches_dir = File.join(File.dirname(__dir__), 'patches', name)
    return unless Dir.exist?(patches_dir)

    patches = Dir.glob(File.join(patches_dir, '*.patch')).sort

    return if patches.empty?

    @logger.detail("  Applying #{patches.length} patch(es)")

    Dir.chdir(core_dir) do
      patches.each do |patch_file|
        patch_name = File.basename(patch_file)
        @logger.detail("    → #{patch_name}")

        # Use git apply if available (better handling), otherwise fall back to patch
        if system('git rev-parse --git-dir > /dev/null 2>&1')
          # Check if patch is already applied
          unless system("git apply --check #{patch_file} > /dev/null 2>&1")
            # Patch already applied or doesn't apply cleanly
            # Try reverse check to see if it's already applied
            if system("git apply --reverse --check #{patch_file} > /dev/null 2>&1")
              @logger.detail("      (already applied, skipping)")
              next
            else
              raise "Patch #{patch_name} doesn't apply cleanly"
            end
          end

          run_command({}, 'git', 'apply', patch_file)
        else
          # Fall back to patch command
          run_command({}, 'patch', '-p1', '-i', patch_file)
        end
      end
    end
  end

  def clean_before_build(name, build_type, metadata, core_dir)
    # Clean build artifacts to prevent cross-contamination between CPU families
    @logger.detail("  Cleaning previous build artifacts")

    Dir.chdir(core_dir) do
      case build_type
      when 'make'
        # Make-based cores: Use standard 'make clean'
        build_subdir = metadata['build_dir'] || '.'
        makefile = metadata['makefile'] || 'Makefile'

        Dir.chdir(build_subdir) do
          # Try to run make clean (ignore errors if clean target doesn't exist)
          platform = metadata['platform'] || @cpu_config.platform
          system("make -f #{makefile} clean platform=#{platform} 2>/dev/null") || true

          # Also manually remove common artifacts as fallback (recursively to catch subdirs)
          Dir.glob('**/*.o').each { |f| File.delete(f) rescue nil }
          Dir.glob('**/*.so').each { |f| File.delete(f) rescue nil }
          Dir.glob('**/*.a').each { |f| File.delete(f) rescue nil }
        end

      when 'cmake'
        # CMake-based cores: Delete build directory carefully
        # Use git clean if possible to avoid deleting committed files (e.g., TIC-80's build/assets/)
        if system('git rev-parse --git-dir > /dev/null 2>&1')
          # Use git clean to remove untracked files in build/, preserving tracked files
          system('git clean -fd build/ 2>/dev/null') if Dir.exist?('build')
        else
          # Fallback: delete entire build directory if not a git repo
          FileUtils.rm_rf('build') if Dir.exist?('build')
        end

        FileUtils.rm_f('CMakeCache.txt')
        FileUtils.rm_f('cmake_install.cmake')
        FileUtils.rm_rf('CMakeFiles')

        # Remove any stray build artifacts
        Dir.glob('*.so').each { |f| File.delete(f) rescue nil }
        Dir.glob('**/*.o').each { |f| File.delete(f) rescue nil }
        Dir.glob('**/*.a').each { |f| File.delete(f) rescue nil }
      end
    end
  rescue StandardError => e
    @logger.detail("  Warning: Clean failed (#{e.message}), continuing anyway")
  end

  def build_cmake(name, metadata, core_dir)
    run_prebuild_steps(name, core_dir)

    build_dir = File.join(core_dir, 'build')
    FileUtils.mkdir_p(build_dir)

    # Use CommandBuilder to generate CMake commands
    env = @cpu_config.to_env

    # Run CMake
    Dir.chdir(build_dir) do
      run_command(env, *@command_builder.cmake_configure_command(metadata))
      run_command(env, *@command_builder.cmake_build_command)
    end

    # Find and copy .so file
    # For cmake builds, the .so might be in build/ subdirectory
    so_file = find_so_file(core_dir, name, metadata)
    if so_file
      dest_path = copy_so_file(so_file, name, metadata)
      @built += 1
      dest_path # Return the destination path
    else
      log_error(name, "No .so file found")
      @failed += 1
      nil
    end
  end

  def build_make(name, metadata, core_dir)
    build_subdir = metadata['build_dir'] || '.'
    makefile = metadata['makefile'] || 'Makefile'

    run_prebuild_steps(name, core_dir)

    work_dir = File.join(core_dir, build_subdir)

    unless Dir.exist?(work_dir)
      log_error(name, "Build directory not found: #{work_dir}")
      @failed += 1
      return
    end

    # Find actual makefile
    actual_makefile = find_makefile(work_dir, makefile)
    unless actual_makefile
      log_error(name, "Makefile not found: #{makefile}")
      @failed += 1
      return
    end

    # Run make
    env = @cpu_config.to_env
    Dir.chdir(work_dir) do
      # Clean first
      run_command(env, *@command_builder.make_command(metadata, actual_makefile, clean: true)) rescue nil

      # Build using CommandBuilder
      run_command(env, *@command_builder.make_command(metadata, actual_makefile))
    end

    # Find and copy .so file
    so_file = find_so_file(core_dir, name, metadata)
    if so_file
      dest_path = copy_so_file(so_file, name, metadata)
      @built += 1
      dest_path # Return the destination path
    else
      log_error(name, "No .so file found")
      @failed += 1
      nil
    end
  end

  def find_makefile(dir, preferred)
    candidates = [preferred, 'Makefile.libretro', 'Makefile', 'makefile']
    candidates.each do |mf|
      path = File.join(dir, mf)
      return mf if File.exist?(path)
    end
    nil
  end

  def find_so_file(core_dir, name, metadata = {})
    # If recipe specifies exact .so file path, use it
    if metadata && metadata['so_file']
      specific_path = File.join(core_dir, metadata['so_file'])
      return specific_path if File.exist?(specific_path)
    end

    # Fallback: Search for .so files
    pattern = File.join(core_dir, '**', '*_libretro.so')
    so_files = Dir.glob(pattern)

    # Prefer files with matching name
    so_files.find { |f| File.basename(f).start_with?(name) } || so_files.first
  end

  def copy_so_file(so_file, name, metadata = {})
    # Use custom so_file name if specified in recipe (for output file override)
    # Otherwise, preserve the original filename from the build
    if metadata && metadata['so_file'] && !metadata['so_file'].include?('/')
      dest_name = metadata['so_file']
    else
      # Preserve the original filename (e.g., snes9x2005_plus_libretro.so)
      dest_name = File.basename(so_file)
    end

    dest = File.join(@output_dir, dest_name)
    FileUtils.cp(so_file, dest)
    @logger.detail("  ✓ #{dest_name}")
    dest # Return the destination path
  end

  def run_command(env, *args)
    # Filter output to reduce noise
    stdout, stderr, status = Open3.capture3(env, *args)

    unless status.success?
      # Show last 20 lines of error
      error_lines = stderr.lines.last(20).join
      raise "Command failed: #{args.join(' ')}\n#{error_lines}"
    end

    stdout
  end

  def log_error(name, message)
    @logger.error("  ✗ #{name}: #{message}")
  end
end
