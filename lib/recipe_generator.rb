#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative 'logger'
require_relative 'cpu_config'
require_relative 'mk_parser'

# Generate JSON recipes from Knulli .mk files
# Filters by enabled cores for each CPU family
class RecipeGenerator
  def initialize(package_dir:, cpu_config:, logger: nil)
    @package_dir = package_dir
    @cpu_config = cpu_config
    @logger = logger || BuildLogger.new
    @recipes = {}
  end

  def generate
    @logger.section("Generating Recipes for #{@cpu_config.family}")

    mk_files = find_mk_files
    @logger.info("Found #{mk_files.size} .mk files")

    mk_files.each do |mk_file|
      parse_mk_file(mk_file)
    end

    filter_by_cores_list if @cpu_config.cores_list

    @logger.success("Generated #{@recipes.size} recipes")
    @recipes
  end

  def save(output_file)
    FileUtils.mkdir_p(File.dirname(output_file))

    File.open(output_file, 'w') do |f|
      f.write(JSON.pretty_generate(@recipes))
    end

    @logger.success("Saved recipes to #{output_file}")
  end

  private

  def find_mk_files
    # Find all libretro-*.mk files in package directory
    pattern = File.join(@package_dir, '**/libretro-*.mk')
    Dir.glob(pattern).sort
  end

  def parse_mk_file(mk_file)
    parser = MkParser.new(mk_file, cpu_config: @cpu_config, logger: @logger)
    core_name = parser.core_name
    metadata = parser.to_h

    # Skip if no URL (incomplete package)
    unless metadata['url']
      @logger.detail("Skipping #{core_name}: no URL")
      return
    end

    @recipes[core_name] = metadata
  rescue StandardError => e
    @logger.warn("Failed to parse #{mk_file}: #{e.message}")
  end

  def filter_by_cores_list
    return unless @cpu_config.cores_list

    @logger.info("Filtering to #{@cpu_config.cores_list.size} enabled cores")

    @recipes.select! do |core_name, _metadata|
      @cpu_config.cores_list.include?(core_name)
    end
  end
end
