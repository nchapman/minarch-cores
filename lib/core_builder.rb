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

    # Clean before building to prevent contamination
    clean_before_build(name, build_type, metadata, core_dir)

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
    # Core-specific pre-build steps can be added here if needed
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

          # Also manually remove common artifacts as fallback
          Dir.glob('*.o').each { |f| File.delete(f) rescue nil }
          Dir.glob('*.so').each { |f| File.delete(f) rescue nil }
          Dir.glob('*.a').each { |f| File.delete(f) rescue nil }
        end

      when 'cmake'
        # CMake-based cores: Delete entire build directory
        # This is critical because CMakeCache.txt stores architecture-specific settings
        FileUtils.rm_rf('build') if Dir.exist?('build')
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
      "-DCMAKE_SYSTEM_PROCESSOR=#{@cpu_config.arch}",
      "-DTHREADS_PREFER_PTHREAD_FLAG=ON",
      "-DCMAKE_BUILD_TYPE=Release"
    ]

    # Add CMAKE_PREFIX_PATH if set (for dependency finding)
    if ENV['CMAKE_PREFIX_PATH']
      cmake_opts += ["-DCMAKE_PREFIX_PATH=#{ENV['CMAKE_PREFIX_PATH']}"]
    end

    # Run CMake
    Dir.chdir(build_dir) do
      run_command(env, "cmake", "..", *cmake_opts)
      run_command(env, "make", "-j#{@parallel}")
    end

    # Find and copy .so file
    # For cmake builds, the .so might be in build/ subdirectory
    so_file = find_so_file(core_dir, name, metadata)
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

    # flycast-xtreme requires CPU-specific platform flags
    extra_make_args = []

    if name == 'flycast-xtreme'
      extra_make_args << 'HAVE_OPENMP=1'

      case @cpu_config.family
      when 'cortex-a53'
        # H700/A133 devices (RG28xx/35xx/40xx, Trimui)
        platform = 'odroid-n2'
        extra_make_args += ['FORCE_GLES=1', 'ARCH=arm64', 'LDFLAGS=-lrt']
        @logger.detail("  Using Knulli H700/A133 config: platform=#{platform}")
      when 'cortex-a35'
        # RG351 series (legacy 64-bit ARM)
        platform = 'odroid-n2'
        extra_make_args += ['FORCE_GLES=1', 'ARCH=arm64', 'LDFLAGS=-lrt']
        @logger.detail("  Using platform=#{platform} for Cortex-A35")
      when 'cortex-a55'
        # RK3566 devices (Miyoo Flip, etc.)
        platform = 'odroidc4'
        extra_make_args += ['FORCE_GLES=1', 'ARCH=arm64', 'LDFLAGS=-lrt']
        @logger.detail("  Using platform=#{platform} for Cortex-A55")
      when 'cortex-a7'
        platform = 'arm'
        extra_make_args += ['FORCE_GLES=1', 'ARCH=arm', 'LDFLAGS=-lrt']
        @logger.detail("  Using platform=#{platform} for ARM32")
      else
        # Generic ARM64 fallback
        if @cpu_config.arch == 'aarch64'
          platform = 'arm64'
          extra_make_args += ['FORCE_GLES=1', 'ARCH=arm64', 'LDFLAGS=-lrt']
          @logger.detail("  Using platform=#{platform} for ARM64")
        end
      end
    end

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

    # Build make arguments
    make_args = []
    make_args << "platform=#{platform}" if platform
    make_args += extra_make_args

    # Run make
    env = @cpu_config.to_env
    Dir.chdir(work_dir) do
      # Clean first
      run_command(env, "make", "-f", actual_makefile, "clean") rescue nil

      # Build
      args = ["make", "-f", actual_makefile, "-j#{@parallel}"]
      args += make_args
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
