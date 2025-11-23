# frozen_string_literal: true

require 'spec_helper'
require 'cpu_config'
require 'logger'
require 'tempfile'

RSpec.describe CpuConfig do
  let(:logger) { instance_double('BuildLogger', detail: nil, warn: nil, section: nil, info: nil) }
  let(:fixtures_dir) { File.expand_path('../fixtures/recipes/linux', __dir__) }

  before do
    # Create fixture recipe directory
    FileUtils.mkdir_p(fixtures_dir)
  end

  after do
    # Clean up fixtures
    FileUtils.rm_rf(File.expand_path('../fixtures', __dir__))
  end

  describe '#initialize' do
    context 'with valid arm64 recipe' do
      let(:recipe_file) { File.join(fixtures_dir, 'arm64.yml') }

      before do
        File.write(recipe_file, <<~YAML)
          # Test Recipe
          ---
          config:
            arch: aarch64
            target_cross: aarch64-linux-gnu-
            gnu_target_name: aarch64-buildroot-linux-gnu
            target_cpu: cortex-a53
            target_arch: armv8-a+crc
            target_optimization: "-march=armv8-a+crc -mcpu=cortex-a53"
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
              commit: abc123
              build_type: make
        YAML
      end

      it 'loads configuration successfully' do
        config = described_class.new('arm64', recipe_file: recipe_file, logger: logger)

        expect(config.family).to eq('arm64')
        expect(config.arch).to eq('aarch64')
        expect(config.target_cross).to eq('aarch64-linux-gnu-')
        expect(config.gnu_target_name).to eq('aarch64-buildroot-linux-gnu')
        expect(config.target_cpu).to eq('cortex-a53')
      end

      it 'combines optimization and float flags into cflags' do
        config = described_class.new('arm64', recipe_file: recipe_file, logger: logger)

        expect(config.target_cflags).to include('-march=armv8-a+crc')
        expect(config.target_cflags).to include('-mcpu=cortex-a53')
        expect(config.target_cflags).to include('-O2 -pipe')
      end

      it 'returns unix platform' do
        config = described_class.new('arm64', recipe_file: recipe_file, logger: logger)

        expect(config.platform).to eq('unix')
      end
    end

    context 'with ARM32 arm32 recipe' do
      let(:recipe_file) { File.join(fixtures_dir, 'arm32.yml') }

      before do
        File.write(recipe_file, <<~YAML)
          # Test Recipe
          ---
          config:
            arch: arm
            target_cross: arm-linux-gnueabihf-
            gnu_target_name: arm-buildroot-linux-gnueabihf
            target_cpu: cortex-a7
            target_arch: armv7ve
            target_optimization: "-march=armv7ve -mcpu=cortex-a7"
            target_float: "-mfloat-abi=hard -mfpu=neon-vfpv4"
            target_cflags: "-O2 -pipe -fsigned-char"
            target_cxxflags: "-O2 -pipe -fsigned-char"
            target_ldflags: ""

          cores:
            fceumm:
              repo: libretro/libretro-fceumm
              commit: def456
              build_type: make
        YAML
      end

      it 'loads ARM32 configuration' do
        config = described_class.new('arm32', recipe_file: recipe_file, logger: logger)

        expect(config.arch).to eq('arm')
        expect(config.target_cross).to eq('arm-linux-gnueabihf-')
        expect(config.target_cpu).to eq('cortex-a7')
      end

      it 'includes float ABI in flags' do
        config = described_class.new('arm32', recipe_file: recipe_file, logger: logger)

        expect(config.target_cflags).to include('-mfloat-abi=hard')
        expect(config.target_cflags).to include('-mfpu=neon-vfpv4')
      end
    end

    context 'with missing recipe file' do
      it 'raises error' do
        expect {
          described_class.new('nonexistent', logger: logger)
        }.to raise_error(/Recipe file not found/)
      end
    end

    context 'with missing config section' do
      let(:recipe_file) { File.join(fixtures_dir, 'incomplete.yml') }

      before do
        File.write(recipe_file, <<~YAML)
          # Test Recipe with no config
          ---
          cores:
            gambatte:
              repo: libretro/gambatte-libretro
        YAML
      end

      it 'raises validation error' do
        expect {
          described_class.new('incomplete', recipe_file: recipe_file, logger: logger)
        }.to raise_error(/No 'config' section found/)
      end
    end

    context 'with incomplete config section' do
      let(:recipe_file) { File.join(fixtures_dir, 'incomplete2.yml') }

      before do
        File.write(recipe_file, <<~YAML)
          ---
          config:
            arch: aarch64
            # Missing target_cross
        YAML
      end

      it 'raises validation error' do
        expect {
          described_class.new('incomplete2', recipe_file: recipe_file, logger: logger)
        }.to raise_error(/Missing required config fields/)
      end
    end
  end

  describe '#to_env' do
    let(:recipe_file) { File.join(fixtures_dir, 'arm64.yml') }

    before do
      File.write(recipe_file, <<~YAML)
        ---
        config:
          arch: aarch64
          target_cross: aarch64-linux-gnu-
          gnu_target_name: aarch64-buildroot-linux-gnu
          target_cpu: cortex-a53
          target_optimization: "-march=armv8-a+crc"
          target_float: ""
          target_cflags: "-O2 -pipe"
          target_cxxflags: "-O2 -pipe"
          target_ldflags: "-Wl,-O1"
      YAML
    end

    it 'returns hash with all environment variables' do
      config = described_class.new('arm64', recipe_file: recipe_file, logger: logger)
      env = config.to_env

      expect(env).to be_a(Hash)
      expect(env['ARCH']).to eq('aarch64')
      expect(env['CC']).to eq('aarch64-linux-gnu-gcc')
      expect(env['CXX']).to eq('aarch64-linux-gnu-g++')
      expect(env['AR']).to eq('aarch64-linux-gnu-ar')
      expect(env['AS']).to eq('aarch64-linux-gnu-as')
      expect(env['STRIP']).to eq('aarch64-linux-gnu-strip')
      expect(env['CFLAGS']).to include('-O2 -pipe')
      expect(env['CFLAGS']).to include('-march=armv8-a+crc')
      expect(env['TARGET_CROSS']).to eq('aarch64-linux-gnu-')
      expect(env['GNU_TARGET_NAME']).to eq('aarch64-buildroot-linux-gnu')
      expect(env['TERM']).to eq('xterm')
    end
  end

  describe '#platform' do
    let(:recipe_file) { File.join(fixtures_dir, 'test.yml') }

    before do
      File.write(recipe_file, <<~YAML)
        ---
        config:
          arch: #{arch}
          target_cross: test-
          target_cflags: "-O2"
          target_cxxflags: "-O2"
          target_ldflags: ""
      YAML
    end

    context 'with ARM architecture' do
      let(:arch) { 'arm' }

      it 'returns unix platform' do
        config = described_class.new('test', recipe_file: recipe_file, logger: logger)
        expect(config.platform).to eq('unix')
      end
    end

    context 'with ARM64 architecture' do
      let(:arch) { 'aarch64' }

      it 'returns unix platform' do
        config = described_class.new('test', recipe_file: recipe_file, logger: logger)
        expect(config.platform).to eq('unix')
      end
    end
  end
end
