#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative 'logger'
require_relative 'cpu_config'
require_relative 'recipe_generator'
require_relative 'source_fetcher'
require_relative 'core_builder'

# Main orchestrator for the build system
# Coordinates recipe generation, source fetching, and building
class CoresBuilder
  def initialize(
    cpu_family:,
    package_dir: 'package/batocera/emulators/retroarch/libretro',
    config_dir: 'config',
    cores_dir: 'cores',
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
    @package_dir = package_dir
    @config_dir = config_dir
    @cores_dir = cores_dir
    @output_dir = output_dir || "build/#{cpu_family}"
    @recipe_file = recipe_file || "recipes/linux/#{cpu_family}.json"
    @parallel_fetch = parallel_fetch
    @parallel_build = parallel_build
    @dry_run = dry_run
    @skip_fetch = skip_fetch
    @skip_build = skip_build

    # Setup logging
    @logger = BuildLogger.new(log_file: log_file)

    # Load CPU configuration
    @cpu_config = CpuConfig.new(@cpu_family, config_dir: @config_dir, logger: @logger)
  end

  def run
    @logger.section("LessUI Cores Build System")
    @logger.info("CPU Family: #{@cpu_family}")
    @logger.info("Architecture: #{@cpu_config.arch}")

    # Phase 1: Generate or load recipes
    recipes = load_or_generate_recipes

    # Phase 2: Fetch sources
    unless @skip_fetch
      fetcher = SourceFetcher.new(
        cores_dir: @cores_dir,
        logger: @logger,
        parallel: @parallel_fetch
      )
      fetcher.fetch_all(recipes)
    end

    # Phase 3: Build cores
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

  def load_or_generate_recipes
    # Use existing recipe if available and fresh
    if File.exist?(@recipe_file) && !should_regenerate?
      @logger.info("Loading existing recipes from #{@recipe_file}")
      return load_recipes
    end

    # Generate new recipes
    generate_recipes
  end

  def should_regenerate?
    # Regenerate if recipe is older than any .mk file
    return true unless File.exist?(@recipe_file)

    recipe_mtime = File.mtime(@recipe_file)
    mk_files = Dir.glob(File.join(@package_dir, '**/libretro-*.mk'))

    mk_files.any? { |mk| File.mtime(mk) > recipe_mtime }
  end

  def load_recipes
    JSON.parse(File.read(@recipe_file))
  end

  def generate_recipes
    generator = RecipeGenerator.new(
      package_dir: @package_dir,
      cpu_config: @cpu_config,
      logger: @logger
    )

    recipes = generator.generate
    generator.save(@recipe_file)
    recipes
  end
end
