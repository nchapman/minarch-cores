#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'thread'
require_relative 'logger'
require_relative 'cpu_config'

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

    case build_type
    when 'cmake'
      build_cmake(name, metadata, core_dir)
    when 'make'
      build_make(name, metadata, core_dir)
    else
      log_error(name, "Unknown build type: #{build_type}")
      @failed += 1
    end
  rescue StandardError => e
    log_error(name, "Build failed: #{e.message}")
    @failed += 1
  end

  private

  def run_prebuild_steps(name, core_dir)
    # Core-specific pre-build steps
    case name
    when 'picodrive'
      # Build cyclone generator
      @logger.detail("  Pre-build: cyclone")
      env = @cpu_config.to_env
      Dir.chdir(core_dir) do
        run_command(env, "make", "-C", "cpu/cyclone", "CONFIG_FILE=../../cpu/cyclone_config.h")
      end
    when 'emuscv'
      # Build bin2c tool (for host, not target)
      @logger.detail("  Pre-build: bin2c")
      bin2c_dir = File.join(core_dir, 'tools', 'bin2c')
      Dir.chdir(bin2c_dir) do
        # Compile with host compiler, not cross-compiler
        run_command({}, "gcc", "-o", "bin2c", "bin2c.c")
      end
    end
  rescue StandardError => e
    @logger.warn("  Pre-build step failed: #{e.message}")
  end

  def build_cmake(name, metadata, core_dir)
    build_dir = File.join(core_dir, 'build')
    FileUtils.mkdir_p(build_dir)

    # Prepare CMake options
    cmake_opts = metadata['cmake_opts'] || []
    cmake_opts = cmake_opts.flat_map { |opt| opt.split } # Split combined options

    # Add our cross-compile settings
    env = @cpu_config.to_env
    cmake_opts += [
      "-DCMAKE_C_COMPILER=#{env['CC']}",
      "-DCMAKE_CXX_COMPILER=#{env['CXX']}",
      "-DCMAKE_C_FLAGS=#{env['CFLAGS']}",
      "-DCMAKE_CXX_FLAGS=#{env['CXXFLAGS']}",
      "-DCMAKE_BUILD_TYPE=Release"
    ]

    # Run CMake
    Dir.chdir(build_dir) do
      run_command(env, "cmake", "..", *cmake_opts)
      run_command(env, "make", "-j#{@parallel}")
    end

    # Find and copy .so file
    so_file = find_so_file(core_dir, name)
    if so_file
      copy_so_file(so_file, name)
      @built += 1
    else
      log_error(name, "No .so file found")
      @failed += 1
    end
  end

  def build_make(name, metadata, core_dir)
    build_subdir = metadata['build_dir'] || '.'
    makefile = metadata['makefile'] || 'Makefile'
    # Use recipe platform unless it's a variable reference or null
    platform = metadata['platform']
    platform = @cpu_config.platform if platform.nil? || platform.include?('$(')

    # Handle special pre-build steps for specific cores
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

    # Build platform argument
    platform_arg = platform ? "platform=#{platform}" : ""

    # Run make
    env = @cpu_config.to_env
    Dir.chdir(work_dir) do
      # Clean first
      run_command(env, "make", "-f", actual_makefile, "clean") rescue nil

      # Build
      args = ["make", "-f", actual_makefile, "-j#{@parallel}"]
      args << platform_arg unless platform_arg.empty?
      run_command(env, *args)
    end

    # Find and copy .so file
    so_file = find_so_file(core_dir, name)
    if so_file
      copy_so_file(so_file, name)
      @built += 1
    else
      log_error(name, "No .so file found")
      @failed += 1
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

  def find_so_file(core_dir, name)
    # Search for .so files
    pattern = File.join(core_dir, '**', '*_libretro.so')
    so_files = Dir.glob(pattern)

    # Prefer files with matching name
    so_files.find { |f| File.basename(f).start_with?(name) } || so_files.first
  end

  def copy_so_file(so_file, name)
    dest = File.join(@output_dir, "#{name}_libretro.so")
    FileUtils.cp(so_file, dest)
    @logger.detail("  ✓ #{name}_libretro.so")
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
