# frozen_string_literal: true

require 'spec_helper'
require 'command_builder'
require 'cpu_config'
require 'tmpdir'

RSpec.describe CommandBuilder do
  # Create a minimal CPU config mock
  let(:cpu_config_data) do
    {
      family: cpu_family,
      arch: arch,
      target_cross: target_cross,
      target_cflags: '-O2 -pipe -march=armv8-a+crc',
      target_cxxflags: '-O2 -pipe -march=armv8-a+crc',
      target_ldflags: '-Wl,-O1',
      platform: 'unix'
    }
  end

  let(:cpu_config) do
    double('CpuConfig',
           family: cpu_config_data[:family],
           arch: cpu_config_data[:arch],
           target_cross: cpu_config_data[:target_cross],
           platform: cpu_config_data[:platform],
           to_env: {
             'ARCH' => cpu_config_data[:arch],
             'CC' => "#{cpu_config_data[:target_cross]}gcc",
             'CXX' => "#{cpu_config_data[:target_cross]}g++",
             'CFLAGS' => cpu_config_data[:target_cflags],
             'CXXFLAGS' => cpu_config_data[:target_cxxflags],
             'LDFLAGS' => cpu_config_data[:target_ldflags]
           })
  end

  let(:parallel) { 4 }
  let(:builder) { described_class.new(cpu_config: cpu_config, parallel: parallel) }

  describe '#make_args' do
    context 'with arm64 architecture' do
      let(:cpu_family) { 'arm64' }
      let(:arch) { 'aarch64' }
      let(:target_cross) { 'aarch64-linux-gnu-' }

      let(:metadata) do
        {
          'name' => 'gambatte',
          'platform' => 'unix',
          'extra_args' => []
        }
      end

      it 'includes toolchain variables' do
        args = builder.make_args(metadata)
        expect(args).to include('CC=aarch64-linux-gnu-gcc')
        expect(args).to include('CXX=aarch64-linux-gnu-g++')
      end

      it 'includes platform from metadata' do
        args = builder.make_args(metadata)
        expect(args).to include('platform=unix')
      end

      it 'includes extra args from metadata' do
        metadata['extra_args'] = ['EXTRA_FLAG=1', 'DEBUG=yes']
        args = builder.make_args(metadata)

        expect(args).to include('EXTRA_FLAG=1')
        expect(args).to include('DEBUG=yes')
      end
    end

    context 'with arm32 architecture' do
      let(:cpu_family) { 'arm32' }
      let(:arch) { 'arm' }
      let(:target_cross) { 'arm-linux-gnueabihf-' }

      let(:metadata) do
        {
          'name' => 'fceumm',
          'platform' => 'classic_armv7_a7'
        }
      end

      it 'uses correct platform from metadata' do
        args = builder.make_args(metadata)
        expect(args).to include('platform=classic_armv7_a7')
      end
    end
  end

  describe '#cmake_args' do
    let(:cpu_family) { 'arm64' }
    let(:arch) { 'aarch64' }
    let(:target_cross) { 'aarch64-linux-gnu-' }

    context 'with basic cmake metadata' do
      let(:metadata) do
        {
          'cmake_opts' => ['-DBUILD_SHARED_LIBS=ON']
        }
      end

      it 'includes recipe cmake options' do
        args = builder.cmake_args(metadata)
        expect(args).to include('-DBUILD_SHARED_LIBS=ON')
      end

      it 'includes compiler flags' do
        args = builder.cmake_args(metadata)
        expect(args.join(' ')).to include('-DCMAKE_C_FLAGS=')
        expect(args.join(' ')).to include('-DCMAKE_CXX_FLAGS=')
      end

      it 'includes pthread flag' do
        args = builder.cmake_args(metadata)
        expect(args).to include('-DTHREADS_PREFER_PTHREAD_FLAG=ON')
      end

      it 'includes Release build type by default' do
        args = builder.cmake_args(metadata)
        expect(args).to include('-DCMAKE_BUILD_TYPE=Release')
      end

      it 'does not override existing CMAKE_BUILD_TYPE' do
        metadata['cmake_opts'] = ['-DCMAKE_BUILD_TYPE=Debug']
        args = builder.cmake_args(metadata)

        # Should only have one BUILD_TYPE (the Debug one from metadata)
        build_types = args.select { |arg| arg.include?('CMAKE_BUILD_TYPE') }
        expect(build_types.length).to eq(1)
        expect(build_types.first).to include('Debug')
      end
    end

    context 'with ARM32 architecture' do
      let(:cpu_family) { 'arm32' }
      let(:arch) { 'arm' }
      let(:target_cross) { 'arm-linux-gnueabihf-' }

      let(:metadata) do
        {
          'cmake_opts' => []
        }
      end

      it 'forces C99 standard for ARM32' do
        args = builder.cmake_args(metadata)
        expect(args).to include('-DCMAKE_C_STANDARD=99')
      end

      it 'forces C++11 standard for ARM32' do
        args = builder.cmake_args(metadata)
        expect(args).to include('-DCMAKE_CXX_STANDARD=11')
      end
    end
  end

  describe '#cmake_configure_command' do
    let(:cpu_family) { 'arm64' }
    let(:arch) { 'aarch64' }
    let(:target_cross) { 'aarch64-linux-gnu-' }
    let(:build_dir) { Dir.mktmpdir }

    let(:metadata) do
      {
        'cmake_opts' => ['-DFOO=bar']
      }
    end

    after do
      FileUtils.rm_rf(build_dir)
    end

    it 'includes cmake command' do
      cmd = builder.cmake_configure_command(metadata, build_dir: build_dir)
      expect(cmd.first).to eq('cmake')
    end

    it 'targets parent directory' do
      cmd = builder.cmake_configure_command(metadata, build_dir: build_dir)
      expect(cmd).to include('..')
    end

    it 'includes cross-compile settings' do
      cmd = builder.cmake_configure_command(metadata, build_dir: build_dir)
      cmd_str = cmd.join(' ')
      expect(cmd_str).to include('-DCMAKE_C_COMPILER=')
      expect(cmd_str).to include('-DCMAKE_CXX_COMPILER=')
      expect(cmd_str).to include('-DCMAKE_SYSTEM_PROCESSOR=')
    end

    it 'includes cmake args from metadata' do
      cmd = builder.cmake_configure_command(metadata, build_dir: build_dir)
      expect(cmd).to include('-DFOO=bar')
    end
  end

  describe '#cmake_build_command' do
    let(:cpu_family) { 'arm64' }
    let(:arch) { 'aarch64' }
    let(:target_cross) { 'aarch64-linux-gnu-' }

    it 'uses make with parallel jobs' do
      cmd = builder.cmake_build_command
      expect(cmd).to eq(['make', '-j4'])
    end
  end

end
