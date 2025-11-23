#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require_relative 'logger'
require_relative 'cpu_config'
require_relative 'source_fetcher'
require_relative 'core_builder'

# Main orchestrator for the build system
# Coordinates recipe loading, source fetching, and building
class CoresBuilder
  def initialize(
    cpu_family:,
    cores_dir: nil,
    cache_dir: 'output/cache',
    output_dir: nil,
    recipe_file: nil,
    log_file: nil,
    parallel_fetch: 4,
    parallel_build: 1,
    dry_run: false,
    skip_fetch: false,
    skip_build: false
  )
    @cpu_family = cpu_family
    # CPU-specific cores directory to prevent contamination across builds
    @cores_dir = File.expand_path(cores_dir || "output/cores-#{cpu_family}")
    # Shared cache directory for downloaded tarballs
    @cache_dir = File.expand_path(cache_dir)
    @output_dir = File.expand_path(output_dir || "output/#{cpu_family}")
    @recipe_file = recipe_file || "recipes/linux/#{cpu_family}.yml"
    @parallel_fetch = parallel_fetch
    @parallel_build = parallel_build
    @dry_run = dry_run
    @skip_fetch = skip_fetch
    @skip_build = skip_build

    # Setup logging
    @logger = BuildLogger.new(log_file: log_file)

    # Load CPU configuration
    @cpu_config = CpuConfig.new(@cpu_family, recipe_file: @recipe_file, logger: @logger)
  end

  def run
    @logger.section("LessUI Cores Build System")
    @logger.info("CPU Family: #{@cpu_family}")
    @logger.info("Architecture: #{@cpu_config.arch}")

    # Load recipes from YAML file
    recipes = load_recipes_from_yaml

    # Fetch sources
    unless @skip_fetch
      fetcher = SourceFetcher.new(
        cores_dir: @cores_dir,
        cache_dir: @cache_dir,
        logger: @logger,
        parallel: @parallel_fetch
      )
      fetcher.fetch_all(recipes)
    end

    # Build cores
    unless @skip_build
      builder = CoreBuilder.new(
        cores_dir: @cores_dir,
        output_dir: @output_dir,
        cpu_config: @cpu_config,
        logger: @logger,
        parallel: @parallel_build,
        dry_run: @dry_run
      )
      exit_code = builder.build_all(recipes)
      return exit_code
    end

    0
  ensure
    @logger.close
  end

  private

  def load_recipes_from_yaml
    unless File.exist?(@recipe_file)
      raise "Recipe file not found: #{@recipe_file}"
    end

    @logger.info("Loading recipes from #{@recipe_file}")

    # Parse YAML (skip header comments before ---)
    file_content = File.read(@recipe_file)
    yaml_content = file_content.split('---', 2)[1]
    data = YAML.load(yaml_content)

    # Extract cores section (config section loaded separately by CpuConfig)
    data['cores'] || raise("No 'cores' section in #{@recipe_file}")
  end
end
