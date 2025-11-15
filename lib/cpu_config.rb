#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'set'
require_relative 'logger'

# Parse CPU family configuration files
# Loads config/{cpu-family}.config files with Make-style variable syntax
class CpuConfig
  attr_reader :family, :arch, :target_cross, :gnu_target_name,
              :target_cpu, :target_arch, :target_optimization,
              :target_cflags, :target_cxxflags, :target_ldflags,
              :br2_flags, :cores_list

  def initialize(family, config_dir: 'config', logger: nil)
    @family = family
    @config_dir = config_dir
    @logger = logger || BuildLogger.new
    @variables = {}
    @br2_flags = {}

    load_config
    load_cores_list
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
    config_file = File.join(@config_dir, "#{@family}.config")

    unless File.exist?(config_file)
      raise "Config file not found: #{config_file}"
    end

    @logger.detail("Loading config: #{config_file}")

    File.readlines(config_file).each do |line|
      line = line.strip
      next if line.empty? || line.start_with?('#')

      # Parse "VAR := value" or "VAR = value"
      if line =~ /^([A-Z_]+)\s*:?=\s*(.+)$/
        var = Regexp.last_match(1)
        value = Regexp.last_match(2)

        # Remove surrounding quotes (we'll handle quoting at use-time)
        value = value.strip.gsub(/^["']|["']$/, '')

        # Expand variables in value
        value = expand_variables(value)

        # Store variable
        @variables[var] = value

        # Map to instance variables
        case var
        when 'ARCH'
          @arch = value
        when 'TARGET_CROSS'
          @target_cross = value
        when 'GNU_TARGET_NAME'
          @gnu_target_name = value
        when 'TARGET_CPU'
          @target_cpu = value
        when 'TARGET_ARCH'
          @target_arch = value
        when 'TARGET_OPTIMIZATION'
          @target_optimization = value
        when 'TARGET_CFLAGS'
          @target_cflags = value
        when 'TARGET_CXXFLAGS'
          @target_cxxflags = value
        when 'TARGET_LDFLAGS'
          @target_ldflags = value
        when /^BR2_(.+)/
          # Store BR2 flags for conditional evaluation
          @br2_flags[var] = value
        end
      end
    end

    validate_config
  end

  def load_cores_list
    list_file = File.join(@config_dir, "cores-#{@family}.list")

    unless File.exist?(list_file)
      @logger.warn("No cores list found: #{list_file}, will use all cores")
      @cores_list = nil
      return
    end

    @cores_list = File.readlines(list_file)
                      .map(&:strip)
                      .reject { |line| line.empty? || line.start_with?('#') }
                      .to_set

    @logger.detail("Loaded #{@cores_list.size} cores for #{@family}")
  end

  def expand_variables(value)
    # Expand ${VAR} and $(VAR) references
    result = value.dup

    # Handle ${VAR} and $(VAR) syntax
    result.gsub!(/\$\{([A-Z_]+)\}|\$\(([A-Z_]+)\)/) do
      var_name = Regexp.last_match(1) || Regexp.last_match(2)
      @variables[var_name] || ENV[var_name] || ''
    end

    result
  end

  def validate_config
    required = %w[ARCH TARGET_CROSS TARGET_CFLAGS TARGET_CXXFLAGS]
    missing = required.reject { |var| @variables[var] }

    unless missing.empty?
      raise "Missing required config variables: #{missing.join(', ')}"
    end

    @logger.detail("Config loaded: #{@arch} (#{@target_cpu})")
  end
end
