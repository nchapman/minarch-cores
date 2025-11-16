# frozen_string_literal: true

require 'spec_helper'
require 'command_builder'
require 'cpu_config'

RSpec.describe CommandBuilder do
  # Create a minimal CPU config mock
  let(:cpu_config_data) do
    {
      family: cpu_family,
      arch: arch,
      target_cross: target_cross,
      target_cflags: '-O2 -pipe',
      target_cxxflags: '-O2 -pipe',
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
    context 'with basic metadata' do
      let(:cpu_family) { 'cortex-a53' }
      let(:arch) { 'aarch64' }
      let(:target_cross) { 'aarch64-linux-gnu-' }

      let(:metadata) do
        {
          'name' => 'gambatte',
          'platform' => 'unix',
          'extra_args' => []
        }
      end

      it 'includes platform argument' do
        args = builder.make_args(metadata)
        expect(args).to include('platform=unix')
      end

      it 'returns array of arguments' do
        args = builder.make_args(metadata)
        expect(args).to be_an(Array)
      end
    end

    context 'with extra_args from recipe' do
      let(:cpu_family) { 'cortex-a53' }
      let(:arch) { 'aarch64' }
      let(:target_cross) { 'aarch64-linux-gnu-' }

      let(:metadata) do
        {
          'name' => 'snes9x2005',
          'platform' => 'unix',
          'extra_args' => ['USE_BLARGG_APU=1']
        }
      end

      it 'includes recipe extra_args' do
        args = builder.make_args(metadata)
        expect(args).to include('USE_BLARGG_APU=1')
        expect(args).to include('platform=unix')
      end
    end

    context 'with nil platform' do
      let(:cpu_family) { 'cortex-a53' }
      let(:arch) { 'aarch64' }
      let(:target_cross) { 'aarch64-linux-gnu-' }

      let(:metadata) do
        {
          'name' => 'test-core',
          'platform' => nil,
          'extra_args' => []
        }
      end

      it 'uses cpu_config platform as fallback' do
        args = builder.make_args(metadata)
        expect(args).to include('platform=unix')
      end
    end

    context 'with variable reference in platform' do
      let(:cpu_family) { 'cortex-a53' }
      let(:arch) { 'aarch64' }
      let(:target_cross) { 'aarch64-linux-gnu-' }

      let(:metadata) do
        {
          'name' => 'test-core',
          'platform' => '$(PLATFORM)',
          'extra_args' => []
        }
      end

      it 'uses cpu_config platform as fallback' do
        args = builder.make_args(metadata)
        expect(args).to include('platform=unix')
      end
    end
  end

  describe '#make_command' do
    let(:cpu_family) { 'cortex-a53' }
    let(:arch) { 'aarch64' }
    let(:target_cross) { 'aarch64-linux-gnu-' }

    let(:metadata) do
      {
        'name' => 'gambatte',
        'platform' => 'unix',
        'extra_args' => []
      }
    end

    it 'includes make, makefile, and parallelism' do
      cmd = builder.make_command(metadata, 'Makefile.libretro')
      expect(cmd).to include('make')
      expect(cmd).to include('-f')
      expect(cmd).to include('Makefile.libretro')
      expect(cmd).to include('-j4')
    end

    it 'includes make args' do
      cmd = builder.make_command(metadata, 'Makefile.libretro')
      expect(cmd).to include('platform=unix')
    end

    context 'when clean: true' do
      it 'includes clean target' do
        cmd = builder.make_command(metadata, 'Makefile.libretro', clean: true)
        expect(cmd).to include('make')
        expect(cmd).to include('-f')
        expect(cmd).to include('Makefile.libretro')
        expect(cmd).to include('clean')
        expect(cmd).not_to include('-j4')
      end
    end
  end

  describe '#cmake_args' do
    let(:cpu_family) { 'cortex-a53' }
    let(:arch) { 'aarch64' }
    let(:target_cross) { 'aarch64-linux-gnu-' }

    let(:metadata) do
      {
        'name' => 'swanstation',
        'cmake_opts' => []
      }
    end

    it 'includes cross-compile settings' do
      args = builder.cmake_args(metadata)

      expect(args).to include('-DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc')
      expect(args).to include('-DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++')
      expect(args).to include('-DCMAKE_C_FLAGS=-O2 -pipe')
      expect(args).to include('-DCMAKE_CXX_FLAGS=-O2 -pipe')
      expect(args).to include('-DCMAKE_SYSTEM_PROCESSOR=aarch64')
    end

    it 'includes standard cmake settings' do
      args = builder.cmake_args(metadata)

      expect(args).to include('-DTHREADS_PREFER_PTHREAD_FLAG=ON')
      expect(args).to include('-DCMAKE_BUILD_TYPE=Release')
    end

    context 'with recipe-specific cmake_opts' do
      let(:metadata) do
        {
          'name' => 'swanstation',
          'cmake_opts' => ['-DBUILD_LIBRETRO_CORE=ON']
        }
      end

      it 'includes recipe cmake_opts' do
        args = builder.cmake_args(metadata)

        expect(args).to include('-DBUILD_LIBRETRO_CORE=ON')
      end
    end

    context 'when recipe specifies CMAKE_BUILD_TYPE' do
      let(:metadata) do
        {
          'name' => 'swanstation',
          'cmake_opts' => ['-DCMAKE_BUILD_TYPE=Release', '-DBUILD_SHARED_LIBS=FALSE']
        }
      end

      it 'does not duplicate CMAKE_BUILD_TYPE' do
        args = builder.cmake_args(metadata)

        # Count occurrences of CMAKE_BUILD_TYPE
        build_type_count = args.count { |arg| arg.start_with?('-DCMAKE_BUILD_TYPE=') }
        expect(build_type_count).to eq(1), "Expected 1 CMAKE_BUILD_TYPE, got #{build_type_count}: #{args.grep(/CMAKE_BUILD_TYPE/)}"
      end

      it 'preserves recipe CMAKE_BUILD_TYPE value' do
        args = builder.cmake_args(metadata)

        expect(args).to include('-DCMAKE_BUILD_TYPE=Release')
      end
    end

    context 'when recipe does not specify CMAKE_BUILD_TYPE' do
      let(:metadata) do
        {
          'name' => 'test-core',
          'cmake_opts' => ['-DBUILD_SHARED_LIBS=FALSE']
        }
      end

      it 'adds default CMAKE_BUILD_TYPE=Release' do
        args = builder.cmake_args(metadata)

        expect(args).to include('-DCMAKE_BUILD_TYPE=Release')
      end
    end

    context 'with ARM32 architecture' do
      let(:cpu_family) { 'cortex-a7' }
      let(:arch) { 'arm' }
      let(:target_cross) { 'arm-linux-gnueabihf-' }

      it 'forces C99 and C++11 standards' do
        args = builder.cmake_args(metadata)

        expect(args).to include('-DCMAKE_C_STANDARD=99')
        expect(args).to include('-DCMAKE_CXX_STANDARD=11')
      end
    end

    context 'with CMAKE_PREFIX_PATH environment variable' do
      before { ENV['CMAKE_PREFIX_PATH'] = '/opt/deps' }
      after { ENV.delete('CMAKE_PREFIX_PATH') }

      it 'includes CMAKE_PREFIX_PATH' do
        args = builder.cmake_args(metadata)
        expect(args).to include('-DCMAKE_PREFIX_PATH=/opt/deps')
      end
    end
  end

  describe '#cmake_configure_command' do
    let(:cpu_family) { 'cortex-a53' }
    let(:arch) { 'aarch64' }
    let(:target_cross) { 'aarch64-linux-gnu-' }

    let(:metadata) do
      { 'name' => 'swanstation', 'cmake_opts' => [] }
    end

    it 'returns cmake command with args' do
      cmd = builder.cmake_configure_command(metadata)

      expect(cmd.first).to eq('cmake')
      expect(cmd).to include('..')
      expect(cmd).to include('-DCMAKE_BUILD_TYPE=Release')
    end
  end

  describe '#cmake_build_command' do
    let(:cpu_family) { 'cortex-a53' }
    let(:arch) { 'aarch64' }
    let(:target_cross) { 'aarch64-linux-gnu-' }

    it 'returns make command with parallelism' do
      cmd = builder.cmake_build_command

      expect(cmd).to eq(['make', '-j4'])
    end
  end

  describe 'flycast-xtreme special case handling' do
    let(:metadata) do
      {
        'name' => 'flycast-xtreme',
        'platform' => 'unix',
        'extra_args' => []
      }
    end

    context 'cortex-a53' do
      let(:cpu_family) { 'cortex-a53' }
      let(:arch) { 'aarch64' }
      let(:target_cross) { 'aarch64-linux-gnu-' }

      it 'uses odroid-n2 platform with correct flags' do
        args = builder.make_args(metadata)

        expect(args).to include('platform=odroid-n2')
        expect(args).to include('HAVE_OPENMP=1')
        expect(args).to include('FORCE_GLES=1')
        expect(args).to include('ARCH=arm64')
        expect(args).to include('LDFLAGS=-lrt')
      end
    end

    context 'cortex-a55' do
      let(:cpu_family) { 'cortex-a55' }
      let(:arch) { 'aarch64' }
      let(:target_cross) { 'aarch64-linux-gnu-' }

      it 'uses odroidc4 platform with correct flags' do
        args = builder.make_args(metadata)

        expect(args).to include('platform=odroidc4')
        expect(args).to include('HAVE_OPENMP=1')
        expect(args).to include('FORCE_GLES=1')
        expect(args).to include('ARCH=arm64')
        expect(args).to include('LDFLAGS=-lrt')
      end
    end

    context 'cortex-a7' do
      let(:cpu_family) { 'cortex-a7' }
      let(:arch) { 'arm' }
      let(:target_cross) { 'arm-linux-gnueabihf-' }

      it 'uses arm platform with correct flags' do
        args = builder.make_args(metadata)

        expect(args).to include('platform=arm')
        expect(args).to include('HAVE_OPENMP=1')
        expect(args).to include('FORCE_GLES=1')
        expect(args).to include('ARCH=arm')
        expect(args).to include('LDFLAGS=-lrt')
      end
    end

    context 'cortex-a76' do
      let(:cpu_family) { 'cortex-a76' }
      let(:arch) { 'aarch64' }
      let(:target_cross) { 'aarch64-linux-gnu-' }

      it 'uses arm64 platform with correct flags' do
        args = builder.make_args(metadata)

        expect(args).to include('platform=arm64')
        expect(args).to include('HAVE_OPENMP=1')
        expect(args).to include('FORCE_GLES=1')
        expect(args).to include('ARCH=arm64')
        expect(args).to include('LDFLAGS=-lrt')
      end
    end
  end

  describe 'argument ordering' do
    let(:cpu_family) { 'cortex-a53' }
    let(:arch) { 'aarch64' }
    let(:target_cross) { 'aarch64-linux-gnu-' }

    context 'for make_args' do
      let(:metadata) do
        {
          'name' => 'snes9x2005',
          'platform' => 'unix',
          'extra_args' => ['USE_BLARGG_APU=1', 'FOO=bar']
        }
      end

      it 'orders: platform, recipe extra_args, special case args' do
        args = builder.make_args(metadata)

        # Platform should be first
        expect(args.first).to eq('platform=unix')

        # Recipe extra_args should come after platform
        expect(args).to include('USE_BLARGG_APU=1')
        expect(args).to include('FOO=bar')

        # Verify order
        platform_idx = args.index('platform=unix')
        blargg_idx = args.index('USE_BLARGG_APU=1')
        expect(blargg_idx).to be > platform_idx
      end
    end

    context 'for cmake_args' do
      let(:metadata) do
        {
          'name' => 'test-core',
          'cmake_opts' => ['-DCUSTOM=value']
        }
      end

      it 'orders: recipe opts, cross-compile, build type, standards' do
        args = builder.cmake_args(metadata)

        # Recipe opts should be first
        custom_idx = args.index('-DCUSTOM=value')
        expect(custom_idx).to eq(0)

        # Cross-compile settings should come after recipe opts
        compiler_idx = args.index { |a| a.start_with?('-DCMAKE_C_COMPILER=') }
        expect(compiler_idx).to be > custom_idx

        # Build type should come after cross-compile settings
        build_type_idx = args.index('-DCMAKE_BUILD_TYPE=Release')
        expect(build_type_idx).to be > compiler_idx
      end
    end
  end

  describe 'regular cores do not get flycast special handling' do
    let(:cpu_family) { 'cortex-a53' }
    let(:arch) { 'aarch64' }
    let(:target_cross) { 'aarch64-linux-gnu-' }

    let(:metadata) do
      {
        'name' => 'gambatte',
        'platform' => 'unix',
        'extra_args' => []
      }
    end

    it 'does not include flycast-specific flags' do
      args = builder.make_args(metadata)

      expect(args).to include('platform=unix')
      expect(args).not_to include('HAVE_OPENMP=1')
      expect(args).not_to include('FORCE_GLES=1')
    end
  end
end
