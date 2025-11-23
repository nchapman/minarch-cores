# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'cpu_config'
require 'cores_builder'
require 'tempfile'

RSpec.describe 'Recipe Loading Integration' do
  let(:fixtures_dir) { File.expand_path('../../fixtures/recipes/linux', __dir__) }
  let(:recipe_file) { File.join(fixtures_dir, 'arm64.yml') }

  before do
    FileUtils.mkdir_p(fixtures_dir)
    File.write(recipe_file, <<~YAML)
      # LessUI-Cores Recipe: arm64
      # Architecture: ARMv8-A+CRC with NEON (64-bit)
      # Target Devices: RG28xx/40xx, Trimui, CubeXX
      ---
      config:
        arch: aarch64
        target_cross: aarch64-linux-gnu-
        gnu_target_name: aarch64-buildroot-linux-gnu
        target_cpu: cortex-a53
        target_arch: armv8-a+crc
        target_optimization: "-march=armv8-a+crc -mcpu=cortex-a53 -mtune=cortex-a53"
        target_float: ""
        target_cflags: "-O2 -pipe -fsigned-char"
        target_cxxflags: "-O2 -pipe -fsigned-char"
        target_ldflags: ""
        buildroot:
          BR2_aarch64: y
          BR2_cortex_a53: y

      cores:
        gambatte:
          repo: libretro/gambatte-libretro
          commit: 47c5a2feaa9c253efc407283d9247a3c055f9efb
          build_type: make
          makefile: Makefile
          build_dir: "."
          platform: unix
          so_file: gambatte_libretro.so

        fceumm:
          repo: libretro/libretro-fceumm
          commit: abc123def456
          build_type: make
          makefile: Makefile.libretro
          build_dir: "."
          platform: unix
          so_file: fceumm_libretro.so
    YAML
  end

  after do
    FileUtils.rm_rf(File.expand_path('../../fixtures', __dir__))
  end

  describe 'Loading recipe YAML' do
    it 'loads config and cores sections separately' do
      file_content = File.read(recipe_file)
      yaml_content = file_content.split('---', 2)[1]
      data = YAML.load(yaml_content)

      expect(data).to have_key('config')
      expect(data).to have_key('cores')
      expect(data['cores']).to have_key('gambatte')
      expect(data['cores']).to have_key('fceumm')
    end

    it 'CpuConfig loads config section correctly' do
      logger = instance_double('BuildLogger', detail: nil, section: nil, info: nil)
      config = CpuConfig.new('arm64', recipe_file: recipe_file, logger: logger)

      expect(config.family).to eq('arm64')
      expect(config.arch).to eq('aarch64')
      expect(config.target_cpu).to eq('cortex-a53')
      expect(config.target_cflags).to include('-march=armv8-a+crc')
    end

    it 'extracts cores section for building' do
      file_content = File.read(recipe_file)
      yaml_content = file_content.split('---', 2)[1]
      data = YAML.load(yaml_content)
      cores = data['cores']

      expect(cores['gambatte']['repo']).to eq('libretro/gambatte-libretro')
      expect(cores['gambatte']['build_type']).to eq('make')
      expect(cores['fceumm']['so_file']).to eq('fceumm_libretro.so')
    end
  end

  describe 'Recipe file format validation' do
    it 'requires config section' do
      bad_recipe = File.join(fixtures_dir, 'bad.yml')
      File.write(bad_recipe, <<~YAML)
        ---
        cores:
          test:
            repo: test/test
      YAML

      logger = instance_double('BuildLogger', detail: nil, section: nil, info: nil)
      expect {
        CpuConfig.new('bad', recipe_file: bad_recipe, logger: logger)
      }.to raise_error(/No 'config' section found/)
    end

    it 'validates required config fields' do
      incomplete_recipe = File.join(fixtures_dir, 'incomplete.yml')
      File.write(incomplete_recipe, <<~YAML)
        ---
        config:
          arch: aarch64
          # Missing target_cross and other required fields
        cores:
          test:
            repo: test/test
      YAML

      logger = instance_double('BuildLogger', detail: nil, section: nil, info: nil)
      expect {
        CpuConfig.new('incomplete', recipe_file: incomplete_recipe, logger: logger)
      }.to raise_error(/Missing required config fields/)
    end
  end

  describe 'Different architecture configs' do
    it 'loads arm32 correctly' do
      arm32_recipe = File.join(fixtures_dir, 'arm32.yml')
      File.write(arm32_recipe, <<~YAML)
        ---
        config:
          arch: arm
          target_cross: arm-linux-gnueabihf-
          gnu_target_name: arm-buildroot-linux-gnueabihf
          target_cpu: cortex-a7
          target_arch: armv7ve
          target_optimization: "-march=armv7ve -mcpu=cortex-a7"
          target_float: "-mfloat-abi=hard -mfpu=neon-vfpv4"
          target_cflags: "-O2 -pipe"
          target_cxxflags: "-O2 -pipe"
          target_ldflags: ""
        cores:
          test:
            repo: test/test
            commit: abc123
            build_type: make
      YAML

      logger = instance_double('BuildLogger', detail: nil, section: nil, info: nil)
      config = CpuConfig.new('arm32', recipe_file: arm32_recipe, logger: logger)

      expect(config.arch).to eq('arm')
      expect(config.target_cpu).to eq('cortex-a7')
      expect(config.target_float).to eq('-mfloat-abi=hard -mfpu=neon-vfpv4')
      expect(config.target_cflags).to include('-mfloat-abi=hard')
      expect(config.target_cflags).to include('-mfpu=neon-vfpv4')
    end
  end
end
