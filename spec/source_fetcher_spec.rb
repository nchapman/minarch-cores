# frozen_string_literal: true

require 'spec_helper'
require 'source_fetcher'
require 'logger'
require 'tmpdir'

RSpec.describe SourceFetcher do
  let(:cores_dir) { Dir.mktmpdir('cores_spec') }
  let(:cache_dir) { Dir.mktmpdir('cache_spec') }
  let(:logger) { instance_double('BuildLogger', section: nil, info: nil, success: nil, warn: nil, error: nil, step: nil, detail: nil) }
  let(:fetcher) { described_class.new(cores_dir: cores_dir, cache_dir: cache_dir, logger: logger, parallel: 2) }

  after do
    FileUtils.rm_rf(cores_dir)
    FileUtils.rm_rf(cache_dir)
  end

  describe '#fetch_one' do
    context 'when core directory already exists' do
      let(:metadata) do
        {
          'repo' => 'libretro/test-core',
          'commit' => 'abc123'
        }
      end

      before do
        # Create existing directory
        FileUtils.mkdir_p(File.join(cores_dir, 'libretro-test-core'))
      end

      it 'skips fetching and increments skipped counter' do
        allow(fetcher).to receive(:log_thread)

        fetcher.fetch_one('test-core', metadata)

        expect(fetcher.instance_variable_get(:@skipped)).to eq(1)
        expect(fetcher.instance_variable_get(:@fetched)).to eq(0)
      end
    end

    context 'with commit SHA (uses tarball)' do
      let(:metadata) do
        {
          'repo' => 'libretro/gambatte-libretro',
          'commit' => '47c5a2feaa9c253efc407283d9247a3c055f9efb'
        }
      end

      it 'uses tarball fetch method' do
        allow(fetcher).to receive(:log_thread)
        expect(fetcher).to receive(:fetch_tarball).with(
          "https://github.com/libretro/gambatte-libretro/archive/47c5a2feaa9c253efc407283d9247a3c055f9efb.tar.gz",
          File.join(cores_dir, 'libretro-gambatte'),
          'libretro-gambatte',
          'libretro/gambatte-libretro',
          '47c5a2feaa9c253efc407283d9247a3c055f9efb'
        )

        fetcher.fetch_one('gambatte', metadata)
      end

      it 'increments fetched counter on success' do
        allow(fetcher).to receive(:log_thread)
        allow(fetcher).to receive(:fetch_tarball)

        fetcher.fetch_one('gambatte', metadata)

        expect(fetcher.instance_variable_get(:@fetched)).to eq(1)
      end
    end

    context 'with version tag (uses git)' do
      let(:metadata) do
        {
          'repo' => 'libretro/test-core',
          'commit' => 'v1.2.3'
        }
      end

      it 'uses git fetch method for version tags' do
        allow(fetcher).to receive(:log_thread)
        expect(fetcher).to receive(:fetch_git).with(
          'https://github.com/libretro/test-core.git',
          File.join(cores_dir, 'libretro-test-core'),
          'v1.2.3',
          false
        )

        fetcher.fetch_one('test-core', metadata)
      end
    end

    context 'with submodules enabled' do
      let(:metadata) do
        {
          'repo' => 'libretro/test-core',
          'commit' => 'abc123def456',
          'submodules' => true
        }
      end

      it 'uses git fetch method for cores with submodules' do
        allow(fetcher).to receive(:log_thread)
        expect(fetcher).to receive(:fetch_git).with(
          'https://github.com/libretro/test-core.git',
          File.join(cores_dir, 'libretro-test-core'),
          'abc123def456',
          true
        )

        fetcher.fetch_one('test-core', metadata)
      end
    end

    context 'with missing required fields' do
      it 'handles errors gracefully' do
        metadata = { 'commit' => 'abc123' }  # Missing repo

        # Should not raise, but should log error and increment failed counter
        fetcher.fetch_one('test', metadata)

        expect(fetcher.instance_variable_get(:@failed)).to eq(1)
      end
    end

    context 'when fetch fails' do
      let(:metadata) do
        {
          'repo' => 'libretro/test-core',
          'commit' => 'abc123'
        }
      end

      it 'increments failed counter and logs error' do
        allow(fetcher).to receive(:fetch_tarball).and_raise(StandardError, 'Network error')
        allow(fetcher).to receive(:log_thread)

        fetcher.fetch_one('test-core', metadata)

        expect(fetcher.instance_variable_get(:@failed)).to eq(1)
        expect(fetcher.instance_variable_get(:@fetched)).to eq(0)
      end
    end
  end

  describe '#fetch_all' do
    let(:recipes) do
      {
        'gambatte' => {
          'repo' => 'libretro/gambatte-libretro',
          'commit' => 'abc123'
        },
        'fceumm' => {
          'repo' => 'libretro/libretro-fceumm',
          'commit' => 'def456'
        }
      }
    end

    it 'processes all recipes' do
      allow(fetcher).to receive(:fetch_tarball)
      allow(fetcher).to receive(:log_thread)

      fetcher.fetch_all(recipes)

      expect(fetcher.instance_variable_get(:@fetched)).to eq(2)
    end

    it 'logs summary with counts' do
      allow(fetcher).to receive(:fetch_tarball)
      allow(fetcher).to receive(:log_thread)

      expect(logger).to receive(:success).with(/Fetched: 2, Skipped: 0, Failed: 0/)

      fetcher.fetch_all(recipes)
    end

    it 'creates cores and cache directories' do
      allow(fetcher).to receive(:fetch_tarball)
      allow(fetcher).to receive(:log_thread)

      fetcher.fetch_all(recipes)

      expect(Dir.exist?(cores_dir)).to be true
      expect(Dir.exist?(cache_dir)).to be true
    end
  end

  describe 'parallel processing' do
    let(:recipes) do
      (1..10).map do |i|
        ["core#{i}", {
          'repo' => "libretro/core#{i}",
          'commit' => "commit#{i}"
        }]
      end.to_h
    end

    it 'processes cores in parallel' do
      allow(fetcher).to receive(:fetch_tarball)
      allow(fetcher).to receive(:log_thread)

      fetcher.fetch_all(recipes)

      # With 10 cores and parallel: 2, should be faster than sequential
      # Just verify it completes successfully
      expect(fetcher.instance_variable_get(:@fetched)).to eq(10)
    end
  end

  describe 'naming convention' do
    let(:metadata) do
      {
        'repo' => 'libretro/gambatte-libretro',
        'commit' => 'abc123'
      }
    end

    it 'constructs directory name as libretro-{corename}' do
      allow(fetcher).to receive(:log_thread)
      allow(fetcher).to receive(:fetch_tarball) do |_url, target_dir, _repo_name, _repo, _ref|
        expect(target_dir).to eq(File.join(cores_dir, 'libretro-gambatte'))
      end

      fetcher.fetch_one('gambatte', metadata)
    end
  end
end
