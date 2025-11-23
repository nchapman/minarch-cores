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
    build_type = metadata['build_type'] || raise("Missing 'build_type' for #{name}")

    # Core directory is always libretro-{name}
    core_dir = File.join(@cores_dir, "libretro-#{name}")

    unless Dir.exist?(core_dir)
      raise "Directory not found: #{core_dir}"
    end

    @logger.step("Building #{name} (#{build_type})")

    if @dry_run
      @logger.detail("[DRY RUN] Would build #{name}")
      @built += 1
      return
    end

    # Run prebuild script if specified
    run_prebuild_steps(name, metadata, core_dir)

    # Apply patches before building
    apply_patches(name, core_dir)

    # No need to clean - CPU-specific directories prevent contamination
    # Skipping clean speeds up builds significantly

    result = case build_type
             when 'cmake'
               build_cmake(name, metadata, core_dir)
             when 'make'
               build_make(name, metadata, core_dir)
             else
               raise "Unknown build type: #{build_type}"
             end
    result
  rescue StandardError => e
    log_error(name, "Build failed: #{e.message}")
    @failed += 1
    nil
  end

  private

  def run_prebuild_steps(name, metadata, core_dir)
    return unless metadata['prebuild_script']

    script_path = File.join(File.dirname(__dir__), 'scripts', metadata['prebuild_script'])

    unless File.exist?(script_path)
      raise "Prebuild script not found: #{script_path}"
    end

    @logger.detail("  Running prebuild script: #{metadata['prebuild_script']}")

    # Execute script with core_dir and cpu_config as arguments
    cmd = "#{script_path} #{@cpu_config.arch} #{core_dir}"

    output, status = Open3.capture2e(cmd)
    unless status.success?
      raise "Prebuild script failed:\n#{output}"
    end

    @logger.detail("  ✓ Prebuild script completed")
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

  def build_cmake(name, metadata, core_dir)
    so_file_path = metadata['so_file'] || raise("Missing 'so_file' for #{name}")

    build_dir = File.join(core_dir, 'build')
    FileUtils.mkdir_p(build_dir)

    # Use CommandBuilder to generate CMake commands
    env = @cpu_config.to_env

    # Run CMake
    Dir.chdir(build_dir) do
      run_command(env, *@command_builder.cmake_configure_command(metadata, build_dir: build_dir))
      run_command(env, *@command_builder.cmake_build_command)
    end

    # Copy .so file to output (using explicit path from recipe)
    so_file = File.join(core_dir, so_file_path)
    unless File.exist?(so_file)
      raise "Built .so file not found: #{so_file}"
    end

    dest_path = copy_so_file(so_file, name, metadata)
    @built += 1
    dest_path
  end

  def build_make(name, metadata, core_dir)
    build_subdir = metadata['build_dir'] || raise("Missing 'build_dir' for #{name}")
    makefile = metadata['makefile'] || raise("Missing 'makefile' for #{name}")
    so_file_path = metadata['so_file'] || raise("Missing 'so_file' for #{name}")

    work_dir = File.join(core_dir, build_subdir)
    unless Dir.exist?(work_dir)
      raise "Build directory not found: #{work_dir}"
    end

    makefile_path = File.join(work_dir, makefile)
    unless File.exist?(makefile_path)
      raise "Makefile not found: #{makefile_path}"
    end

    # Verbose logging for debugging
    if ENV['VERBOSE'] == '1'
      puts "\n" + "="*60
      puts "VERBOSE: Building #{name}"
      puts "="*60
      puts "Recipe: recipes/linux/#{@cpu_config.family}.yml"
      puts "Arch: #{@cpu_config.arch} (#{@cpu_config.target_cpu})"
      puts "Flags: #{@cpu_config.target_cflags}"
      puts "="*60 + "\n"
    end

    # Run make
    env = @cpu_config.to_env
    Dir.chdir(work_dir) do
      run_command(env, *@command_builder.make_command(metadata, makefile))
    end

    # Copy .so file to output (using explicit path from recipe)
    so_file = File.join(core_dir, so_file_path)
    unless File.exist?(so_file)
      raise "Built .so file not found: #{so_file}"
    end

    dest_path = copy_so_file(so_file, name, metadata)
    @built += 1
    dest_path
  end

  def copy_so_file(so_file, name, metadata)
    # Use output_name from recipe if specified, otherwise preserve original filename
    if metadata['output_name']
      dest_name = metadata['output_name']
    else
      dest_name = File.basename(so_file)
    end

    dest = File.join(@output_dir, dest_name)
    FileUtils.cp(so_file, dest)
    @logger.detail("  ✓ #{dest_name}")
    dest
  end

  def run_command(env, *args)
    # Verbose logging: show exact command and environment
    if ENV['VERBOSE'] == '1'
      puts "\n" + "="*60
      puts "VERBOSE: Executing Make Command"
      puts "="*60
      puts "Working directory: #{Dir.pwd}"
      puts "\nCommand line:"
      puts "  #{args.join(' ')}"
      puts "\nMake arguments breakdown:"
      args.each_with_index do |arg, i|
        next if i < 3  # Skip 'make', '-f', 'Makefile'
        puts "  [#{i-2}] #{arg}"
      end
      puts "\nEnvironment variables being exported:"
      env.sort.each { |k, v| puts "  #{k}=#{v}" }
      puts "="*60 + "\n"
    end

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
