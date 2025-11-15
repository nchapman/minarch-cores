#!/usr/bin/env ruby
# frozen_string_literal: true

# Structured logging for build system
# Provides colored output and log file capture
class BuildLogger
  COLORS = {
    reset: "\e[0m",
    red: "\e[31m",
    green: "\e[32m",
    yellow: "\e[33m",
    blue: "\e[34m",
    magenta: "\e[35m",
    cyan: "\e[36m",
    bold: "\e[1m"
  }.freeze

  attr_reader :log_file, :quiet

  def initialize(log_file: nil, quiet: false)
    @log_file = log_file
    @quiet = quiet
    @start_time = Time.now
    @use_color = $stdout.isatty && !ENV['NO_COLOR']

    # Create log file if specified
    if @log_file
      FileUtils.mkdir_p(File.dirname(@log_file))
      @file_handle = File.open(@log_file, 'w')
      @file_handle.sync = true
    end
  end

  def info(message, prefix: nil)
    log(:info, message, prefix: prefix, color: :cyan)
  end

  def success(message, prefix: nil)
    log(:success, message, prefix: prefix, color: :green)
  end

  def warn(message, prefix: nil)
    log(:warn, message, prefix: prefix, color: :yellow)
  end

  def error(message, prefix: nil)
    log(:error, message, prefix: prefix, color: :red)
  end

  def section(title)
    separator = "=" * 60
    log(:section, "\n#{separator}", color: :bold)
    log(:section, title, color: :bold)
    log(:section, separator, color: :bold)
  end

  def step(message)
    log(:step, message, prefix: "→", color: :blue)
  end

  def detail(message)
    log(:detail, message, prefix: "  ", color: :reset) unless @quiet
  end

  def summary(built:, failed:, skipped: 0)
    section("Build Summary")
    success("Built: #{built} cores") if built > 0
    error("Failed: #{failed} cores") if failed > 0
    warn("Skipped: #{skipped} cores") if skipped > 0

    duration = Time.now - @start_time
    info("Duration: #{format_duration(duration)}")
  end

  def close
    @file_handle&.close
  end

  private

  def log(level, message, prefix: nil, color: :reset)
    # Format message
    formatted = prefix ? "#{prefix} #{message}" : message

    # Console output with color
    unless @quiet && level == :detail
      console_msg = @use_color ? colorize(formatted, color) : formatted
      puts console_msg
    end

    # File output without color
    @file_handle&.puts("[#{timestamp}] [#{level.upcase}] #{formatted}")
  end

  def colorize(text, color)
    return text unless @use_color
    "#{COLORS[color]}#{text}#{COLORS[:reset]}"
  end

  def timestamp
    Time.now.strftime("%Y-%m-%d %H:%M:%S")
  end

  def format_duration(seconds)
    if seconds < 60
      "#{seconds.round}s"
    elsif seconds < 3600
      minutes = (seconds / 60).floor
      secs = (seconds % 60).round
      "#{minutes}m #{secs}s"
    else
      hours = (seconds / 3600).floor
      minutes = ((seconds % 3600) / 60).floor
      "#{hours}h #{minutes}m"
    end
  end
end
