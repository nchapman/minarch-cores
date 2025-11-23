# frozen_string_literal: true

require 'spec_helper'
require 'core_builder'
require 'cpu_config'
require 'command_builder'
require 'logger'
require 'tmpdir'

RSpec.describe CoreBuilder do
  let(:cores_dir) { Dir.mktmpdir('cores_spec') }
  let(:output_dir) { Dir.mktmpdir('output_spec') }
  let(:logger) { instance_double('BuildLogger', section: nil, info: nil, success: nil, error: nil, step: nil, detail: nil, warn: nil, summary: nil) }

  let(:cpu_config) do
    instance_double('CpuConfig',
      family: 'arm64',
      arch: 'aarch64',
      target_cross: 'aarch64-linux-gnu-',
      to_env: {
        'ARCH' => 'aarch64',
        'CC' => 'aarch64-linux-gnu-gcc',
        'CXX' => 'aarch64-linux-gnu-g++',
        'CFLAGS' => '-O2 -pipe',
        'CXXFLAGS' => '-O2 -pipe',
        'LDFLAGS' => '-Wl,-O1',
        'TERM' => 'xterm'
      }
    )
  end

  let(:builder) do
    described_class.new(
      cores_dir: cores_dir,
      output_dir: output_dir,
      cpu_config: cpu_config,
      logger: logger,
      parallel: 4
    )
  end

  after do
    FileUtils.rm_rf(cores_dir)
    FileUtils.rm_rf(output_dir)
  end

  describe '#build_one' do
    let(:core_dir) { File.join(cores_dir, 'libretro-gambatte') }

    before do
      FileUtils.mkdir_p(core_dir)
    end

    context 'with Make-based core' do
      let(:metadata) do
        {
          'repo' => 'libretro/gambatte-libretro',
          'build_type' => 'make',
          'makefile' => 'Makefile',
          'build_dir' => '.',
          'platform' => 'unix',
          'so_file' => 'gambatte_libretro.so'
        }
      end

      before do
        # Create Makefile in core directory
        FileUtils.touch(File.join(core_dir, 'Makefile'))
      end

      it 'builds successfully and returns .so path' do
        # Mock Dir.chdir to yield
        allow(Dir).to receive(:chdir).and_yield

        # Expect make build command (no clean anymore based on code comment)
        expect(builder).to receive(:run_command).with(
          hash_including('ARCH' => 'aarch64'),
          'make',
          '-f',
          'Makefile',
          '-j4',
          anything,  # CC=...
          anything,  # CXX=...
          anything,  # AR=...
          'platform=unix'
        )

        # Mock the .so file being created after build
        so_file = File.join(core_dir, 'gambatte_libretro.so')
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(so_file).and_return(true)
        allow(FileUtils).to receive(:cp)

        result = builder.build_one('gambatte', metadata)

        expect(result).to eq(File.join(output_dir, 'gambatte_libretro.so'))
      end

      it 'constructs correct Make arguments' do
        captured_args = nil

        allow(Dir).to receive(:chdir).and_yield
        allow(builder).to receive(:run_command) do |env, *args|
          captured_args = args if args.first == 'make' && args.include?('-j4')
        end

        # Mock file existence
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(File.join(core_dir, 'gambatte_libretro.so')).and_return(true)
        allow(FileUtils).to receive(:cp)

        builder.build_one('gambatte', metadata)

        expect(captured_args).to include('make')
        expect(captured_args).to include('-j4')
        expect(captured_args).to include('-f')
        expect(captured_args).to include('Makefile')
        expect(captured_args).to include('platform=unix')
        expect(captured_args.join(' ')).to match(/CC=aarch64-linux-gnu-gcc/)
      end

      it 'passes extra_args from metadata' do
        metadata['extra_args'] = ['USE_BLARGG_APU=1', 'DEBUG=0']

        captured_args = nil
        allow(Dir).to receive(:chdir).and_yield
        allow(builder).to receive(:run_command) do |env, *args|
          captured_args = args if args.first == 'make' && args.include?('-j4')
        end

        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(File.join(core_dir, 'gambatte_libretro.so')).and_return(true)
        allow(FileUtils).to receive(:cp)

        builder.build_one('gambatte', metadata)

        expect(captured_args).to include('USE_BLARGG_APU=1')
        expect(captured_args).to include('DEBUG=0')
      end
    end

    context 'with CMake-based core' do
      let(:cmake_core_dir) { File.join(cores_dir, 'libretro-cmake-test') }
      let(:metadata) do
        {
          'repo' => 'libretro/cmake-test',
          'build_type' => 'cmake',
          'cmake_opts' => ['-DBUILD_SHARED_LIBS=ON'],
          'so_file' => 'cmake_test_libretro.so'
        }
      end

      before do
        FileUtils.mkdir_p(cmake_core_dir)
      end

      it 'constructs CMake configure and build commands' do
        captured_commands = []

        # Stub prebuild and patch methods
        allow(builder).to receive(:run_prebuild_steps)
        allow(builder).to receive(:apply_patches)

        # Mock Dir.chdir to yield
        allow(Dir).to receive(:chdir).and_yield

        # Capture all run_command calls
        allow(builder).to receive(:run_command) do |env, *args|
          captured_commands << { env: env, args: args }
        end

        # Mock the .so file being created
        so_file = File.join(cmake_core_dir, 'cmake_test_libretro.so')
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(so_file).and_return(true)
        allow(FileUtils).to receive(:cp)

        result = builder.build_one('cmake-test', metadata)

        # Should have 2 commands: cmake configure + make build
        expect(captured_commands.length).to eq(2)

        # First command: cmake configure
        cmake_cmd = captured_commands[0]
        expect(cmake_cmd[:args].first).to eq('cmake')
        expect(cmake_cmd[:args]).to include('..')
        expect(cmake_cmd[:args]).to include('-DBUILD_SHARED_LIBS=ON')

        # Verify cross-compile settings are included
        cmd_str = cmake_cmd[:args].join(' ')
        expect(cmd_str).to include('-DCMAKE_C_COMPILER=')
        expect(cmd_str).to include('-DCMAKE_SYSTEM_PROCESSOR=')

        # Second command: make build
        make_cmd = captured_commands[1]
        expect(make_cmd[:args]).to eq(['make', '-j4'])

        # Verify result
        expect(result).to eq(File.join(output_dir, 'cmake_test_libretro.so'))
      end
    end

    context 'with missing .so file after build' do
      let(:metadata) do
        {
          'repo' => 'libretro/test-core',
          'build_type' => 'make',
          'makefile' => 'Makefile',
          'build_dir' => '.',
          'platform' => 'unix',
          'so_file' => 'missing_libretro.so'
        }
      end

      it 'returns nil when .so file not found' do
        allow(builder).to receive(:run_command)
        allow(File).to receive(:exist?).and_return(false)

        result = builder.build_one('test-core', metadata)

        expect(result).to be_nil
      end
    end

    context 'with build failure' do
      let(:metadata) do
        {
          'repo' => 'libretro/test-core',
          'build_type' => 'make',
          'makefile' => 'Makefile',
          'build_dir' => '.',
          'platform' => 'unix',
          'so_file' => 'test_libretro.so'
        }
      end

      it 'catches errors and returns nil' do
        allow(builder).to receive(:run_command).and_raise(StandardError, 'Build failed')

        result = builder.build_one('test-core', metadata)

        expect(result).to be_nil
      end
    end
  end

  describe '#build_all' do
    let(:recipes) do
      {
        'gambatte' => {
          'repo' => 'libretro/gambatte-libretro',
          'build_type' => 'make',
          'makefile' => 'Makefile',
          'build_dir' => '.',
          'platform' => 'unix',
          'so_file' => 'gambatte_libretro.so'
        },
        'fceumm' => {
          'repo' => 'libretro/libretro-fceumm',
          'build_type' => 'make',
          'makefile' => 'Makefile.libretro',
          'build_dir' => '.',
          'platform' => 'unix',
          'so_file' => 'fceumm_libretro.so'
        }
      }
    end

    before do
      FileUtils.mkdir_p(File.join(cores_dir, 'libretro-gambatte'))
      FileUtils.mkdir_p(File.join(cores_dir, 'libretro-fceumm'))
      # Create Makefiles
      FileUtils.touch(File.join(cores_dir, 'libretro-gambatte', 'Makefile'))
      FileUtils.touch(File.join(cores_dir, 'libretro-fceumm', 'Makefile.libretro'))
    end

    it 'builds all cores and returns success exit code' do
      allow(Dir).to receive(:chdir).and_yield
      allow(builder).to receive(:run_command)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(cores_dir, 'libretro-gambatte', 'gambatte_libretro.so')).and_return(true)
      allow(File).to receive(:exist?).with(File.join(cores_dir, 'libretro-fceumm', 'fceumm_libretro.so')).and_return(true)
      allow(FileUtils).to receive(:cp)

      exit_code = builder.build_all(recipes)

      expect(exit_code).to eq(0)  # Success
    end

    it 'tracks build statistics' do
      allow(Dir).to receive(:chdir).and_yield
      allow(builder).to receive(:run_command)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(cores_dir, 'libretro-gambatte', 'gambatte_libretro.so')).and_return(true)
      allow(File).to receive(:exist?).with(File.join(cores_dir, 'libretro-fceumm', 'fceumm_libretro.so')).and_return(true)
      allow(FileUtils).to receive(:cp)

      builder.build_all(recipes)

      # Check instance variables directly since build_all doesn't return stats hash
      expect(builder.instance_variable_get(:@built)).to eq(2)
      expect(builder.instance_variable_get(:@failed)).to eq(0)
    end

    it 'logs summary with statistics' do
      # Create Makefiles for both cores
      FileUtils.touch(File.join(cores_dir, 'libretro-gambatte', 'Makefile'))
      FileUtils.touch(File.join(cores_dir, 'libretro-fceumm', 'Makefile.libretro'))

      allow(Dir).to receive(:chdir).and_yield
      allow(builder).to receive(:run_command)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(cores_dir, 'libretro-gambatte', 'gambatte_libretro.so')).and_return(true)
      allow(File).to receive(:exist?).with(File.join(cores_dir, 'libretro-fceumm', 'fceumm_libretro.so')).and_return(true)
      allow(FileUtils).to receive(:cp)

      expect(logger).to receive(:summary).with(built: 2, failed: 0, skipped: 0)

      builder.build_all(recipes)
    end
  end

  describe 'build type selection' do
    let(:core_dir) { File.join(cores_dir, 'libretro-test') }

    before do
      FileUtils.mkdir_p(core_dir)
    end

    context 'when build_type is make' do
      let(:metadata) do
        {
          'repo' => 'libretro/test-core',
          'build_type' => 'make',
          'makefile' => 'Makefile',
          'build_dir' => '.',
          'platform' => 'unix',
          'so_file' => 'test_libretro.so'
        }
      end

      it 'uses Make build method' do
        expect(builder).to receive(:build_make).with('test', metadata, core_dir)

        allow(builder).to receive(:copy_so_file).and_return(File.join(output_dir, 'test_libretro.so'))

        builder.build_one('test', metadata)
      end
    end

    context 'when build_type is cmake' do
      let(:metadata) do
        {
          'repo' => 'libretro/test-core',
          'build_type' => 'cmake',
          'cmake_opts' => [],
          'so_file' => 'test_libretro.so'
        }
      end

      it 'uses CMake build method' do
        expect(builder).to receive(:build_cmake).with('test', metadata, core_dir)

        allow(builder).to receive(:copy_so_file).and_return(File.join(output_dir, 'test_libretro.so'))

        builder.build_one('test', metadata)
      end
    end
  end

  describe 'environment variable handling' do
    let(:core_dir) { File.join(cores_dir, 'libretro-test') }
    let(:metadata) do
      {
        'repo' => 'libretro/test-core',
        'build_type' => 'make',
        'makefile' => 'Makefile',
        'build_dir' => '.',
        'platform' => 'unix',
        'so_file' => 'test_libretro.so'
      }
    end

    before do
      FileUtils.mkdir_p(core_dir)
    end

    it 'passes CPU config environment to build commands' do
      captured_env = nil

      allow(builder).to receive(:run_command) do |env, *args|
        captured_env = env if args.first == 'make' && args.include?('-j4')
      end

      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:cp)

      builder.build_one('test', metadata)

      expect(captured_env).to include('ARCH' => 'aarch64')
      expect(captured_env).to include('CC' => 'aarch64-linux-gnu-gcc')
      expect(captured_env).to include('CXX' => 'aarch64-linux-gnu-g++')
      expect(captured_env).to include('CFLAGS' => '-O2 -pipe')
    end
  end

  describe '#copy_so_file' do
    let(:core_dir) { File.join(cores_dir, 'libretro-test') }
    let(:so_file) { File.join(core_dir, 'test_libretro.so') }
    let(:metadata) { { 'so_file' => 'test_libretro.so' } }

    before do
      FileUtils.mkdir_p(core_dir)
    end

    it 'copies .so file to output directory' do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(so_file).and_return(true)
      expect(FileUtils).to receive(:cp).with(so_file, File.join(output_dir, 'test_libretro.so'))

      result = builder.send(:copy_so_file, so_file, 'test', metadata)

      expect(result).to eq(File.join(output_dir, 'test_libretro.so'))
    end

    it 'raises error when .so file does not exist' do
      # copy_so_file doesn't check existence - it will fail on FileUtils.cp
      # The caller (build_make/build_cmake) is responsible for checking existence first
      expect {
        builder.send(:copy_so_file, '/nonexistent/file.so', 'test', metadata)
      }.to raise_error(Errno::ENOENT)
    end
  end

  describe 'dry run mode' do
    let(:dry_run_builder) do
      described_class.new(
        cores_dir: cores_dir,
        output_dir: output_dir,
        cpu_config: cpu_config,
        logger: logger,
        parallel: 4,
        dry_run: true
      )
    end

    let(:core_dir) { File.join(cores_dir, 'libretro-test') }
    let(:metadata) do
      {
        'repo' => 'libretro/test-core',
        'build_type' => 'make',
        'makefile' => 'Makefile',
        'build_dir' => '.',
        'platform' => 'unix',
        'so_file' => 'test_libretro.so'
      }
    end

    before do
      FileUtils.mkdir_p(core_dir)
    end

    it 'does not execute build commands in dry run mode' do
      expect(dry_run_builder).not_to receive(:run_command)

      dry_run_builder.build_one('test', metadata)
    end

    it 'logs what would be done' do
      expect(logger).to receive(:detail).with(/\[DRY RUN\] Would build test/)

      dry_run_builder.build_one('test', metadata)
    end
  end

  describe 'parallel builds' do
    it 'uses correct parallel flag' do
      parallel_builder = described_class.new(
        cores_dir: cores_dir,
        output_dir: output_dir,
        cpu_config: cpu_config,
        logger: logger,
        parallel: 8
      )

      core_dir = File.join(cores_dir, 'libretro-test')
      FileUtils.mkdir_p(core_dir)

      metadata = {
        'repo' => 'libretro/test-core',
        'build_type' => 'make',
        'makefile' => 'Makefile',
        'build_dir' => '.',
        'platform' => 'unix',
        'so_file' => 'test_libretro.so'
      }

      captured_args = nil
      allow(parallel_builder).to receive(:run_command) do |env, *args|
        captured_args = args if args.first == 'make' && args.include?('-j8')
      end

      allow(File).to receive(:exist?).and_return(true)
      allow(FileUtils).to receive(:cp)

      parallel_builder.build_one('test', metadata)

      expect(captured_args).to include('-j8')
    end
  end
end
