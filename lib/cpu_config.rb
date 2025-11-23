#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'yaml'
require_relative 'logger'

# Parse CPU family configuration
# Loads recipe YAML files and extracts config section
class CpuConfig
  attr_reader :family, :arch, :target_cross, :gnu_target_name,
              :target_cpu, :target_arch, :target_optimization,
              :target_float, :target_cflags, :target_cxxflags, :target_ldflags,
              :br2_flags

  def initialize(family, recipe_file: nil, logger: nil)
    @family = family
    @recipe_file = recipe_file || "recipes/linux/#{family}.yml"
    @logger = logger || BuildLogger.new
    @variables = {}
    @br2_flags = {}

    load_config
  end

  def platform
    case @arch
    when 'arm', 'aarch64'
      'unix'
    else
      'unix'
    end
  end

  def to_env
    {
      'ARCH' => @arch,
      'CC' => "#{@target_cross}gcc",
      'CXX' => "#{@target_cross}g++",
      'AR' => "#{@target_cross}ar",
      'AS' => "#{@target_cross}as",
      'STRIP' => "#{@target_cross}strip",
      'CFLAGS' => @target_cflags,
      'CXXFLAGS' => @target_cxxflags,
      'LDFLAGS' => @target_ldflags,
      'TARGET_CROSS' => @target_cross,
      'GNU_TARGET_NAME' => @gnu_target_name,
      'TERM' => 'xterm'  # Some cores (emuscv) need TERM set
    }
  end

  private

  def load_config
    unless File.exist?(@recipe_file)
      raise "Recipe file not found: #{@recipe_file}"
    end

    @logger.detail("Loading config from: #{@recipe_file}")

    # Load YAML recipe file
    recipe_data = YAML.load_file(@recipe_file)

    # Extract config section
    config = recipe_data['config']
    unless config
      raise "No 'config' section found in #{@recipe_file}"
    end

    # Map YAML config to instance variables
    @arch = config['arch']
    @target_cross = config['target_cross']
    @gnu_target_name = config['gnu_target_name']
    @target_cpu = config['target_cpu']
    @target_arch = config['target_arch']
    @target_optimization = config['target_optimization'] || ''
    @target_float = config['target_float'] || ''

    # Build complete flags by combining base flags with optimization and float flags
    base_cflags = config['target_cflags'] || ''
    base_cxxflags = config['target_cxxflags'] || ''
    base_ldflags = config['target_ldflags'] || ''

    @target_cflags = "#{base_cflags} #{@target_optimization} #{@target_float}".strip
    @target_cxxflags = "#{base_cxxflags} #{@target_optimization} #{@target_float}".strip
    @target_ldflags = "#{base_ldflags} #{@target_optimization} #{@target_float}".strip

    # Load buildroot variables
    if config['buildroot']
      config['buildroot'].each do |key, value|
        @br2_flags[key] = value
      end
    end

    # Store all variables for compatibility
    @variables['ARCH'] = @arch
    @variables['TARGET_CROSS'] = @target_cross
    @variables['GNU_TARGET_NAME'] = @gnu_target_name
    @variables['TARGET_CPU'] = @target_cpu
    @variables['TARGET_ARCH'] = @target_arch
    @variables['TARGET_OPTIMIZATION'] = @target_optimization
    @variables['TARGET_CFLAGS'] = @target_cflags
    @variables['TARGET_CXXFLAGS'] = @target_cxxflags
    @variables['TARGET_LDFLAGS'] = @target_ldflags

    validate_config
  end

  def validate_config
    required_fields = %w[arch target_cross target_cflags target_cxxflags]
    missing = required_fields.reject { |field| instance_variable_get("@#{field}") }

    unless missing.empty?
      raise "Missing required config fields: #{missing.join(', ')}"
    end

    @logger.detail("Config loaded: #{@arch} (#{@target_cpu})")
  end
end
