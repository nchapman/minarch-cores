# frozen_string_literal: true

require 'spec_helper'
require 'command_builder'
require 'cpu_config'
require 'yaml'

RSpec.describe 'Recipe command generation integration' do
  let(:recipe_file) { File.expand_path('../../recipes/linux/cortex-a53.yml', __dir__) }
  let(:recipes) do
    content = File.read(recipe_file)
    yaml_content = content.split('---', 2)[1]
    YAML.load(yaml_content)
  end

  let(:cpu_config) do
    double('CpuConfig',
           family: 'cortex-a53',
           arch: 'aarch64',
           target_cross: 'aarch64-linux-gnu-',
           platform: 'unix',
           to_env: {
             'ARCH' => 'aarch64',
             'CC' => 'aarch64-linux-gnu-gcc',
             'CXX' => 'aarch64-linux-gnu-g++',
             'CFLAGS' => '-O2 -pipe -march=armv8-a+crc -mcpu=cortex-a53',
             'CXXFLAGS' => '-O2 -pipe -march=armv8-a+crc -mcpu=cortex-a53',
             'LDFLAGS' => '-Wl,-O1 -Wl,--as-needed'
           })
  end

  let(:builder) { CommandBuilder.new(cpu_config: cpu_config, parallel: 4) }

  describe 'Make-based cores' do
    it 'generates correct commands for gambatte' do
      metadata = recipes['gambatte']
      expect(metadata['build_type']).to eq('make')

      args = builder.make_args(metadata)

      expect(args).to include('platform=unix')
      expect(args.grep(/HAVE_OPENMP/)).to be_empty # Should not have flycast flags
    end

    it 'generates correct commands for snes9x2005' do
      metadata = recipes['snes9x2005']
      expect(metadata['build_type']).to eq('make')

      args = builder.make_args(metadata)

      expect(args).to include('platform=unix')
      # Check for extra_args if present in recipe
      if metadata['extra_args']&.any?
        metadata['extra_args'].each do |arg|
          expect(args).to include(arg)
        end
      end
    end

    it 'generates correct command for beetle-pce-fast' do
      metadata = recipes['beetle-pce-fast']
      expect(metadata['build_type']).to eq('make')

      cmd = builder.make_command(metadata, 'Makefile')

      expect(cmd).to include('make')
      expect(cmd).to include('-f')
      expect(cmd).to include('Makefile')
      expect(cmd).to include('-j4')
      expect(cmd).to include('platform=unix')
    end
  end

  describe 'CMake-based cores' do
    it 'generates correct commands for swanstation' do
      metadata = recipes['swanstation']
      expect(metadata['build_type']).to eq('cmake')

      args = builder.cmake_args(metadata)

      expect(args).to include('-DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc')
      expect(args).to include('-DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++')
      expect(args).to include('-DCMAKE_BUILD_TYPE=Release')

      # Check for recipe-specific cmake_opts
      if metadata['cmake_opts']&.any?
        metadata['cmake_opts'].each do |opt|
          expect(args).to include(opt)
        end
      end

      # Ensure no duplicate CMAKE_BUILD_TYPE (swanstation recipe includes it)
      build_type_count = args.count { |arg| arg.start_with?('-DCMAKE_BUILD_TYPE=') }
      expect(build_type_count).to eq(1), "swanstation should have exactly 1 CMAKE_BUILD_TYPE"
    end
  end

  describe 'Special case: flycast-xtreme' do
    it 'generates correct platform-specific commands' do
      metadata = recipes['flycast-xtreme']

      args = builder.make_args(metadata)

      # Should override platform to odroid-n2 for cortex-a53
      expect(args).to include('platform=odroid-n2')
      expect(args).to include('HAVE_OPENMP=1')
      expect(args).to include('FORCE_GLES=1')
      expect(args).to include('ARCH=arm64')
      expect(args).to include('LDFLAGS=-lrt')
    end
  end

  describe 'All cores validation' do
    it 'all cores have required metadata fields' do
      recipes.each do |name, metadata|
        expect(metadata).to have_key('name'), "#{name} missing 'name'"
        expect(metadata).to have_key('build_type'), "#{name} missing 'build_type'"
        expect(metadata).to have_key('platform'), "#{name} missing 'platform'"
        expect(metadata).to have_key('repo'), "#{name} missing 'repo'"
      end
    end

    it 'can generate make_args for all Make-based cores' do
      recipes.select { |_, m| m['build_type'] == 'make' }.each do |name, metadata|
        expect { builder.make_args(metadata) }.not_to raise_error,
                                                                   "Failed to generate make_args for #{name}"

        args = builder.make_args(metadata)
        expect(args).to be_an(Array), "#{name} make_args should return Array"
      end
    end

    it 'can generate cmake_args for all CMake-based cores' do
      recipes.select { |_, m| m['build_type'] == 'cmake' }.each do |name, metadata|
        expect { builder.cmake_args(metadata) }.not_to raise_error,
                                                                    "Failed to generate cmake_args for #{name}"

        args = builder.cmake_args(metadata)
        expect(args).to be_an(Array), "#{name} cmake_args should return Array"
      end
    end

    it 'all make commands include required arguments' do
      recipes.select { |_, m| m['build_type'] == 'make' }.each do |name, metadata|
        makefile = metadata['makefile'] || 'Makefile'
        cmd = builder.make_command(metadata, makefile)

        expect(cmd).to include('make'), "#{name} missing 'make'"
        expect(cmd).to include('-f'), "#{name} missing '-f'"
        expect(cmd).to include(makefile), "#{name} missing makefile"
        expect(cmd).to include('-j4'), "#{name} missing parallelism"
      end
    end

    it 'all cmake commands include required arguments' do
      recipes.select { |_, m| m['build_type'] == 'cmake' }.each do |name, metadata|
        cmd = builder.cmake_configure_command(metadata)

        expect(cmd).to include('cmake'), "#{name} missing 'cmake'"
        expect(cmd).to include('..'), "#{name} missing parent dir reference"
        expect(cmd.grep(/-DCMAKE_BUILD_TYPE=/)).not_to be_empty, "#{name} missing build type"
      end
    end
  end
end
