# frozen_string_literal: true

require 'spec_helper'
require 'source_fetcher'
require 'logger'
require 'tempfile'
require 'fileutils'

RSpec.describe SourceFetcher do
  let(:cores_dir) { Dir.mktmpdir('cores_spec') }
  let(:logger) { instance_double('BuildLogger', section: nil, info: nil, step: nil, error: nil, success: nil) }
  let(:parallel) { 2 }

  subject(:fetcher) { described_class.new(cores_dir: cores_dir, logger: logger, parallel: parallel) }

  after do
    FileUtils.rm_rf(cores_dir)
  end

  describe '#fetch_one' do
    let(:metadata) do
      {
        'name' => 'test-core',
        'repo' => 'libretro-test',
        'url' => url,
        'commit' => commit,
        'submodules' => false
      }
    end

    context 'when core directory already exists' do
      let(:url) { 'https://github.com/test/repo/archive/abc123.tar.gz' }
      let(:commit) { 'abc123' }

      before do
        FileUtils.mkdir_p(File.join(cores_dir, 'libretro-test'))
      end

      it 'skips fetching' do
        expect(logger).to receive(:step).with(/Skipping/)

        fetcher.fetch_one('test-core', metadata)
      end

      it 'increments skipped counter' do
        fetcher.fetch_one('test-core', metadata)

        # Access the internal counter via instance variable
        skipped = fetcher.instance_variable_get(:@skipped)
        expect(skipped).to eq(1)
      end
    end

    context 'with tarball URL' do
      let(:url) { 'https://github.com/test/repo/archive/abc123.tar.gz' }
      let(:commit) { 'abc123' }

      it 'attempts to fetch tarball' do
        allow(fetcher).to receive(:run_command)

        expect(fetcher).to receive(:fetch_tarball).with(
          url,
          File.join(cores_dir, 'libretro-test'),
          'libretro-test'
        )

        fetcher.fetch_one('test-core', metadata)
      end
    end

    context 'with git URL' do
      let(:url) { 'https://github.com/test/repo.git' }
      let(:commit) { 'abc123' * 2 }  # 40 char SHA

      it 'attempts to fetch via git' do
        allow(fetcher).to receive(:run_command)

        expect(fetcher).to receive(:fetch_git).with(
          url,
          File.join(cores_dir, 'libretro-test'),
          commit,
          false
        )

        fetcher.fetch_one('test-core', metadata)
      end
    end
  end

  describe '#fetch_all' do
    let(:recipes) do
      {
        'core1' => {
          'name' => 'core1',
          'repo' => 'libretro-core1',
          'url' => 'https://github.com/test/core1/archive/abc.tar.gz',
          'commit' => 'abc123',
          'submodules' => false
        },
        'core2' => {
          'name' => 'core2',
          'repo' => 'libretro-core2',
          'url' => 'https://github.com/test/core2/archive/def.tar.gz',
          'commit' => 'def456',
          'submodules' => false
        }
      }
    end

    it 'processes all recipes' do
      allow(fetcher).to receive(:fetch_one)

      expect(fetcher).to receive(:fetch_one).with('core1', recipes['core1'])
      expect(fetcher).to receive(:fetch_one).with('core2', recipes['core2'])

      fetcher.fetch_all(recipes)
    end

    it 'logs summary' do
      allow(fetcher).to receive(:fetch_one)

      expect(logger).to receive(:success).with(/Fetched/)

      fetcher.fetch_all(recipes)
    end
  end

  describe 'error handling' do
    let(:metadata) do
      {
        'name' => 'test-core',
        'repo' => 'libretro-test',
        'url' => 'https://invalid-url.com/archive.tar.gz',
        'commit' => 'abc123',
        'submodules' => false
      }
    end

    it 'catches and logs fetch errors' do
      allow(fetcher).to receive(:run_command).and_raise(StandardError.new('Network error'))
      allow(logger).to receive(:step) # Allow any logging

      # Should not raise, just increment failed counter
      expect { fetcher.fetch_one('test-core', metadata) }.not_to raise_error

      failed = fetcher.instance_variable_get(:@failed)
      expect(failed).to eq(1)
    end
  end
end
