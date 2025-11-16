# frozen_string_literal: true

require 'spec_helper'
require 'cpu_config'
require 'logger'
require 'tempfile'

RSpec.describe CpuConfig do
  let(:logger) { instance_double('BuildLogger', detail: nil, warn: nil) }
  let(:config_dir) { File.expand_path('../fixtures/config', __dir__) }

  before do
    # Create fixture config directory
    FileUtils.mkdir_p(config_dir)
  end

  after do
    # Clean up fixtures
    FileUtils.rm_rf(File.dirname(config_dir))
  end

  describe '#initialize' do
    context 'with valid cortex-a53 config' do
      before do
        File.write(File.join(config_dir, 'cortex-a53.config'), <<~CONFIG)
          # Cortex-A53 configuration
          ARCH := aarch64
          TARGET_CROSS := aarch64-linux-gnu-
          GNU_TARGET_NAME := aarch64-buildroot-linux-gnu
          TARGET_CPU := cortex-a53
          TARGET_OPTIMIZATION := -march=armv8-a+crc -mcpu=cortex-a53
          TARGET_CFLAGS := -O2 -pipe $(TARGET_OPTIMIZATION)
          TARGET_CXXFLAGS := -O2 -pipe $(TARGET_OPTIMIZATION)
          TARGET_LDFLAGS := -Wl,-O1 -Wl,--as-needed
        CONFIG
      end

      it 'loads configuration successfully' do
        config = described_class.new('cortex-a53', config_dir: config_dir, logger: logger)

        expect(config.family).to eq('cortex-a53')
        expect(config.arch).to eq('aarch64')
        expect(config.target_cross).to eq('aarch64-linux-gnu-')
        expect(config.gnu_target_name).to eq('aarch64-buildroot-linux-gnu')
      end

      it 'expands variables in values' do
        config = described_class.new('cortex-a53', config_dir: config_dir, logger: logger)

        expect(config.target_cflags).to include('-march=armv8-a+crc')
        expect(config.target_cflags).to include('-mcpu=cortex-a53')
      end

      it 'returns unix platform' do
        config = described_class.new('cortex-a53', config_dir: config_dir, logger: logger)

        expect(config.platform).to eq('unix')
      end
    end

    context 'with ARM32 cortex-a7 config' do
      before do
        File.write(File.join(config_dir, 'cortex-a7.config'), <<~CONFIG)
          ARCH := arm
          TARGET_CROSS := arm-linux-gnueabihf-
          GNU_TARGET_NAME := arm-buildroot-linux-gnueabihf
          TARGET_CPU := cortex-a7
          TARGET_OPTIMIZATION := -march=armv7-a -mtune=cortex-a7 -mfpu=neon-vfpv4
          TARGET_CFLAGS := -O2 -pipe $(TARGET_OPTIMIZATION)
          TARGET_CXXFLAGS := -O2 -pipe $(TARGET_OPTIMIZATION)
          TARGET_LDFLAGS := -Wl,-O1
        CONFIG
      end

      it 'loads ARM32 configuration' do
        config = described_class.new('cortex-a7', config_dir: config_dir, logger: logger)

        expect(config.arch).to eq('arm')
        expect(config.target_cross).to eq('arm-linux-gnueabihf-')
      end
    end

    context 'with missing config file' do
      it 'raises error' do
        expect {
          described_class.new('nonexistent', config_dir: config_dir, logger: logger)
        }.to raise_error(/Config file not found/)
      end
    end

    context 'with incomplete config' do
      before do
        File.write(File.join(config_dir, 'incomplete.config'), <<~CONFIG)
          ARCH := aarch64
          # Missing TARGET_CROSS
        CONFIG
      end

      it 'raises validation error' do
        expect {
          described_class.new('incomplete', config_dir: config_dir, logger: logger)
        }.to raise_error(/Missing required config variables/)
      end
    end
  end

  describe '#to_env' do
    before do
      File.write(File.join(config_dir, 'cortex-a53.config'), <<~CONFIG)
        ARCH := aarch64
        TARGET_CROSS := aarch64-linux-gnu-
        GNU_TARGET_NAME := aarch64-buildroot-linux-gnu
        TARGET_CFLAGS := -O2 -pipe
        TARGET_CXXFLAGS := -O2 -pipe
        TARGET_LDFLAGS := -Wl,-O1
      CONFIG
    end

    it 'returns hash with all environment variables' do
      config = described_class.new('cortex-a53', config_dir: config_dir, logger: logger)
      env = config.to_env

      expect(env).to be_a(Hash)
      expect(env['ARCH']).to eq('aarch64')
      expect(env['CC']).to eq('aarch64-linux-gnu-gcc')
      expect(env['CXX']).to eq('aarch64-linux-gnu-g++')
      expect(env['AR']).to eq('aarch64-linux-gnu-ar')
      expect(env['AS']).to eq('aarch64-linux-gnu-as')
      expect(env['STRIP']).to eq('aarch64-linux-gnu-strip')
      expect(env['CFLAGS']).to eq('-O2 -pipe')
      expect(env['CXXFLAGS']).to eq('-O2 -pipe')
      expect(env['LDFLAGS']).to eq('-Wl,-O1')
      expect(env['TARGET_CROSS']).to eq('aarch64-linux-gnu-')
      expect(env['GNU_TARGET_NAME']).to eq('aarch64-buildroot-linux-gnu')
      expect(env['TERM']).to eq('xterm')
    end
  end


  describe 'variable expansion' do
    before do
      File.write(File.join(config_dir, 'test.config'), <<~CONFIG)
        BASE_FLAGS := -O2 -pipe
        ARCH := aarch64
        TARGET_CROSS := aarch64-linux-gnu-
        TARGET_CFLAGS := $(BASE_FLAGS) -march=armv8-a
        TARGET_CXXFLAGS := ${BASE_FLAGS} -std=c++11
        TARGET_LDFLAGS := -Wl,-O1
      CONFIG
    end

    it 'expands $(VAR) syntax' do
      config = described_class.new('test', config_dir: config_dir, logger: logger)

      expect(config.target_cflags).to eq('-O2 -pipe -march=armv8-a')
    end

    it 'expands ${VAR} syntax' do
      config = described_class.new('test', config_dir: config_dir, logger: logger)

      expect(config.target_cxxflags).to eq('-O2 -pipe -std=c++11')
    end
  end

  describe '#platform' do
    before do
      File.write(File.join(config_dir, 'test.config'), <<~CONFIG)
        ARCH := #{arch}
        TARGET_CROSS := test-
        TARGET_CFLAGS := -O2
        TARGET_CXXFLAGS := -O2
        TARGET_LDFLAGS := -Wl,-O1
      CONFIG
    end

    context 'with ARM architecture' do
      let(:arch) { 'arm' }

      it 'returns unix platform' do
        config = described_class.new('test', config_dir: config_dir, logger: logger)
        expect(config.platform).to eq('unix')
      end
    end

    context 'with ARM64 architecture' do
      let(:arch) { 'aarch64' }

      it 'returns unix platform' do
        config = described_class.new('test', config_dir: config_dir, logger: logger)
        expect(config.platform).to eq('unix')
      end
    end

    context 'with other architecture' do
      let(:arch) { 'x86_64' }

      it 'returns unix platform' do
        config = described_class.new('test', config_dir: config_dir, logger: logger)
        expect(config.platform).to eq('unix')
      end
    end
  end
end
