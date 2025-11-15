#!/usr/bin/env ruby
# frozen_string_literal: true

require 'uri'
require 'set'
require 'tempfile'
require 'open3'
require_relative 'logger'
require_relative 'cpu_config'

# Parse Knulli .mk files using Make evaluation
# This leverages Make's own logic for conditionals and variable expansion
class MkParser
  attr_reader :core_name, :metadata

  def initialize(mk_file, cpu_config:, logger: nil)
    @mk_file = mk_file
    @cpu_config = cpu_config
    @logger = logger || BuildLogger.new
    @core_name = derive_core_name(mk_file)
    @metadata = {}

    parse
  end

  def to_h
    @metadata
  end

  private

  def derive_core_name(path)
    # Extract core name from path like "libretro-cap32/libretro-cap32.mk"
    basename = File.basename(path, '.mk')
    basename.sub(/^libretro-/, '')
  end

  def parse
    # Use Make to evaluate variables - this handles all conditionals properly
    evaluate_with_make

    # Parse BUILD_CMDS for additional metadata
    parse_build_commands

    # Finalize and set defaults
    finalize_metadata
  end

  def evaluate_with_make
    # Create a temporary Makefile that sets up environment and includes the .mk file
    Tempfile.create(['mk_eval', '.mk']) do |f|
      write_evaluation_makefile(f)
      f.flush

      # Extract variables we need
      @metadata['version'] = make_eval(f.path, variable_name('VERSION'))
      @metadata['commit'] = @metadata['version']

      site = make_eval(f.path, variable_name('SITE'))
      @metadata['url'] = expand_site_url(site, @metadata['version'])

      @metadata['license'] = make_eval(f.path, variable_name('LICENSE'))

      # Try to get platform (may be variable reference)
      platform_var = variable_name('PLATFORM')
      @metadata['platform'] = make_eval(f.path, platform_var)

      # Check for git submodules
      git_submodules = make_eval(f.path, variable_name('GIT_SUBMODULES'))
      @metadata['submodules'] = (git_submodules.to_s.upcase == 'YES')

      # Detect package type
      detect_package_type(f.path)
    end
  rescue StandardError => e
    @logger.warn("Make evaluation failed for #{@core_name}: #{e.message}")
  end

  def write_evaluation_makefile(file)
    # Set up Buildroot-like environment
    env = @cpu_config.br2_flags

    file.puts "# Simulated Buildroot environment"
    env.each do |var, value|
      file.puts "#{var} := #{value}"
    end

    # Add common Buildroot functions
    file.puts ""
    file.puts "# Buildroot helper functions"
    file.puts "github = https://github.com/$(1)/$(2)/archive/$(3).tar.gz"
    file.puts "gitlab = https://gitlab.com/$(1)/$(2)/-/archive/$(3)/$(2)-$(3).tar.gz"
    file.puts "LIBRETRO_PLATFORM := unix"
    file.puts "TARGET_CC := #{@cpu_config.target_cross}gcc"
    file.puts "TARGET_CXX := #{@cpu_config.target_cross}g++"
    file.puts "TARGET_CFLAGS := #{@cpu_config.target_cflags}"
    file.puts ""

    # Include the actual .mk file
    file.puts "include #{@mk_file}"
    file.puts ""

    # Add print targets for variables we need
    file.puts "print-%:"
    file.puts "\t@echo '$($*)'"
  end

  def make_eval(makefile_path, var)
    # Use Make to print the variable value
    stdout, stderr, status = Open3.capture3("make", "-f", makefile_path, "print-#{var}")

    return nil unless status.success?

    result = stdout.strip
    result.empty? ? nil : result
  end

  def variable_name(suffix)
    # Construct variable name like LIBRETRO_CAP32_VERSION
    "LIBRETRO_#{@core_name.upcase.tr('-', '_')}_#{suffix}"
  end

  def expand_site_url(site, version)
    return nil if site.nil? || site.empty?

    # Site is already expanded by Make, but might need version substitution
    # Make's $(call github,...) and $(call gitlab,...) are already expanded
    site
  end

  def detect_package_type(makefile_path)
    # Check if it's a cmake-package or generic-package
    content = File.read(@mk_file)

    if content.include?('$(eval $(cmake-package))')
      @metadata['build_type'] = 'cmake'
      parse_cmake_opts(makefile_path)
    else
      @metadata['build_type'] = 'make'
    end
  end

  def parse_cmake_opts(makefile_path)
    # Get CMake options
    conf_opts_var = variable_name('CONF_OPTS')
    conf_opts = make_eval(makefile_path, conf_opts_var)

    if conf_opts && !conf_opts.empty?
      @metadata['cmake_opts'] = conf_opts.split.grep(/^-D/)
    else
      @metadata['cmake_opts'] = []
    end
  end

  def parse_build_commands
    # Read the .mk file to extract BUILD_CMDS
    content = File.read(@mk_file)

    # Find define LIBRETRO_*_BUILD_CMDS block
    build_cmds_pattern = /define\s+#{variable_name('BUILD_CMDS')}\s*\n(.*?)\nendef/m
    match = content.match(build_cmds_pattern)

    return unless match

    build_cmds = match[1]

    # Handle line continuations and multiple spaces
    clean_cmds = build_cmds.gsub(/\\\s*\n\s*/, ' ')

    # Extract -f makefile first (from any line)
    makefile = nil
    if clean_cmds =~ /-f\s+([^\s]+)/
      makefile = Regexp.last_match(1)
      @metadata['makefile'] = makefile
    end

    # Extract -C directory (build subdirectory)
    # Split into individual command lines to avoid matching across commands
    cmd_lines = clean_cmds.split(/\n/)

    if makefile
      # Find the line that has the makefile and extract -C from THAT line only
      makefile_line = cmd_lines.find { |line| line.include?("-f #{makefile}") || line.include?("-f\t#{makefile}") }

      if makefile_line
        if makefile_line =~ /-C\s+\$\(@D\)\/([^\s]+)/
          @metadata['build_dir'] = Regexp.last_match(1)
        elsif makefile_line =~ /-C\s+\$\(@D\)\s/  || makefile_line =~ /-C\s+\$\(@D\)$/
          @metadata['build_dir'] = '.'
        end
      end
    end

    # Fallback: if no build_dir found yet, use the LAST -C (most likely the main build)
    unless @metadata['build_dir']
      # Reverse to get last occurrence
      cmd_lines.reverse.each do |line|
        if line =~ /-C\s+\$\(@D\)\/([^\s]+)/
          @metadata['build_dir'] = Regexp.last_match(1)
          break
        elsif line =~ /-C\s+\$\(@D\)\s/ || line =~ /-C\s+\$\(@D\)$/
          @metadata['build_dir'] = '.'
          break
        end
      end
    end

    # Extract platform= argument
    if build_cmds =~ /platform="([^"]+)"/
      @metadata['platform'] = Regexp.last_match(1) unless Regexp.last_match(1).include?('$')
    elsif build_cmds =~ /platform=([^\s]+)/
      platform_value = Regexp.last_match(1)
      @metadata['platform'] = platform_value unless platform_value.include?('$')
    end

    # Detect submodules (only if not already set by GIT_SUBMODULES variable)
    unless @metadata.key?('submodules')
      @metadata['submodules'] = build_cmds.include?('submodule') ||
                                 build_cmds.include?('--recursive')
    end
  end

  def finalize_metadata
    # Set defaults
    @metadata['name'] = @core_name
    @metadata['repo'] = "libretro-#{@core_name}"

    # Defaults for missing values
    @metadata['build_type'] ||= 'make'
    @metadata['build_dir'] ||= '.'
    @metadata['makefile'] ||= detect_makefile
    @metadata['submodules'] ||= false
    @metadata['extra_args'] ||= []
    @metadata['cmake_opts'] ||= []
    @metadata['so_file'] ||= detect_so_file

    # Clean up platform (remove variable references, fallback to null)
    if @metadata['platform'] && @metadata['platform'].include?('$')
      @metadata['platform'] = nil
    end

    @logger.detail("Parsed #{@core_name}: #{@metadata['build_type']} build, url=#{@metadata['url'] ? 'yes' : 'no'}")
  end

  def detect_makefile
    if @metadata['build_type'] == 'cmake'
      'Makefile.libretro'
    else
      'Makefile'
    end
  end

  def detect_so_file
    # Default location based on build type and subdir
    if @metadata['build_dir'] && @metadata['build_dir'] != '.'
      "#{@metadata['build_dir']}/#{@core_name}_libretro.so"
    else
      "#{@core_name}_libretro.so"
    end
  end
end
