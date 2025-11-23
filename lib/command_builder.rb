#!/usr/bin/env ruby
# frozen_string_literal: true

# Centralized command construction for building cores
# Handles all the complexity of Make/CMake args, platform detection, and special cases
class CommandBuilder
  def initialize(cpu_config:, parallel: 1)
    @cpu_config = cpu_config
    @parallel = parallel
  end

  # Build Make command arguments for a core
  # Order of arguments (all are appended to make command):
  #   1. Toolchain vars (CC, CXX, AR) - ensures correct cross-compiler is used
  #   2. platform=<value> (from recipe or CPU config)
  #   3. Recipe extra_args (from YAML) - e.g., USE_BLARGG_APU=1
  # Make variables can be overridden; last value wins
  def make_args(metadata)
    args = []

    # Toolchain arguments (must be passed on command line, not just env vars)
    # Some platform strings (classic_armv7_a7) don't set CC, so we must provide it
    env = @cpu_config.to_env
    args << "CC=#{env['CC']}"
    args << "CXX=#{env['CXX']}"
    args << "AR=#{env['AR']} cru"

    # Platform argument (required for most cores)
    platform = metadata['platform'] || raise("Missing 'platform' in metadata")
    args << "platform=#{platform}"

    # Core-specific extra args from recipe (e.g., USE_BLARGG_APU=1 for snes9x2005)
    recipe_extra_args = metadata['extra_args'] || []
    args += recipe_extra_args

    args
  end

  # Build CMake configuration arguments
  # Order of arguments (CMake uses last value for duplicates):
  #   1. Recipe cmake_opts (from YAML) - user-specified options
  #   2. Our cross-compile settings - always added
  #   3. Build type (if not in recipe) - default to Release
  #   4. ARM32 standards (if ARM32) - forced values
  #   5. CMAKE_PREFIX_PATH (if set) - dependency finding
  def cmake_args(metadata)
    env = @cpu_config.to_env

    # Start with recipe-specific options (these come first, can be overridden)
    cmake_opts = metadata['cmake_opts'] || []
    cmake_opts = cmake_opts.flat_map { |opt| opt.split } # Split combined options

    # Add cross-compile settings (always required)
    cmake_opts += [
      "-DCMAKE_C_COMPILER=#{env['CC']}",
      "-DCMAKE_CXX_COMPILER=#{env['CXX']}",
      "-DCMAKE_C_FLAGS=#{env['CFLAGS']}",
      "-DCMAKE_CXX_FLAGS=#{env['CXXFLAGS']}",
      "-DCMAKE_SYSTEM_PROCESSOR=#{@cpu_config.arch}",
      "-DTHREADS_PREFER_PTHREAD_FLAG=ON"
    ]

    # Only add CMAKE_BUILD_TYPE if recipe didn't specify it
    unless has_cmake_option?(cmake_opts, 'CMAKE_BUILD_TYPE')
      cmake_opts << "-DCMAKE_BUILD_TYPE=Release"
    end

    # For ARM32, force C99 standard to avoid glibc Float128 issues (GCC 8.3 limitation)
    if @cpu_config.arch == 'arm'
      cmake_opts += [
        "-DCMAKE_C_STANDARD=99",
        "-DCMAKE_CXX_STANDARD=11"
      ]
    end

    # Add CMAKE_PREFIX_PATH if set (for dependency finding)
    if ENV['CMAKE_PREFIX_PATH']
      cmake_opts += ["-DCMAKE_PREFIX_PATH=#{ENV['CMAKE_PREFIX_PATH']}"]
    end

    cmake_opts
  end

  # Build full make command (with makefile and args)
  def make_command(metadata, makefile, clean: false)
    cmd = ["make", "-f", makefile]

    if clean
      cmd << "clean"
    else
      cmd << "-j#{@parallel}"
      cmd += make_args(metadata)
    end

    cmd
  end

  # Build CMake configuration command
  def cmake_configure_command(metadata, build_dir:)
    ["cmake", "..", *cmake_args(metadata)]
  end

  # Build CMake build command
  def cmake_build_command
    ["make", "-j#{@parallel}"]
  end

  private

  # Check if a CMake option is already present in the arguments
  # Example: has_cmake_option?(['-DFOO=bar'], 'FOO') => true
  def has_cmake_option?(cmake_opts, option_name)
    cmake_opts.any? { |opt| opt.start_with?("-D#{option_name}=") }
  end

  def resolve_platform(metadata)
    name = metadata['name']
    platform = metadata['platform']

    # Handle variable references or null - use CPU config default
    return @cpu_config.platform if platform.nil? || platform.include?('$(')

    # Special case: flycast-xtreme needs CPU-specific platform
    if name == 'flycast-xtreme'
      return resolve_flycast_platform
    end

    platform
  end

  def resolve_flycast_platform
    case @cpu_config.family
    when 'cortex-a53'
      'odroid-n2'  # H700/A133 devices (RG28xx/35xx/40xx, Trimui)
    when 'cortex-a35'
      'odroid-n2'  # RG351 series (legacy 64-bit ARM)
    when 'cortex-a55'
      'odroidc4'   # RK3566 devices (Miyoo Flip, etc.)
    when 'cortex-a7'
      'arm'        # ARM32
    else
      # Generic ARM64 fallback
      @cpu_config.arch == 'aarch64' ? 'arm64' : 'unix'
    end
  end

  def special_case_args(core_name)
    case core_name
    when 'flycast-xtreme'
      flycast_xtreme_args
    else
      []
    end
  end

  def flycast_xtreme_args
    args = ['HAVE_OPENMP=1']

    case @cpu_config.family
    when 'cortex-a53', 'cortex-a35', 'cortex-a55'
      args += ['FORCE_GLES=1', 'ARCH=arm64', 'LDFLAGS=-lrt']
    when 'cortex-a7'
      args += ['FORCE_GLES=1', 'ARCH=arm', 'LDFLAGS=-lrt']
    else
      if @cpu_config.arch == 'aarch64'
        args += ['FORCE_GLES=1', 'ARCH=arm64', 'LDFLAGS=-lrt']
      end
    end

    args
  end
end
