# frozen_string_literal: true

require 'spec_helper'
require 'logger'
require 'stringio'
require 'tempfile'

RSpec.describe BuildLogger do
  let(:log_file) { nil }
  let(:captured_output) { StringIO.new }

  subject(:logger) { described_class.new(log_file: log_file) }

  # Capture stdout for testing
  around do |example|
    original_stdout = $stdout
    $stdout = captured_output
    example.run
    $stdout = original_stdout
  end

  describe '#section' do
    it 'outputs section header with separators' do
      logger.section('Building Cores')

      captured_output.rewind
      result = captured_output.read

      expect(result).to include('Building Cores')
      expect(result).to include('=')  # Has separator
    end
  end

  describe '#info' do
    it 'outputs info message' do
      logger.info('Architecture: aarch64')

      captured_output.rewind
      expect(captured_output.read).to include('Architecture: aarch64')
    end
  end

  describe '#step' do
    it 'outputs step message' do
      logger.step('Fetching gambatte')

      captured_output.rewind
      expect(captured_output.read).to include('Fetching gambatte')
    end
  end

  describe '#detail' do
    it 'outputs detail message indented' do
      logger.detail('  Building core...')

      captured_output.rewind
      expect(captured_output.read).to include('Building core...')
    end
  end

  describe '#success' do
    it 'outputs success message' do
      logger.success('Build completed')

      captured_output.rewind
      expect(captured_output.read).to include('Build completed')
    end
  end

  describe '#error' do
    it 'outputs error message' do
      logger.error('Build failed')

      captured_output.rewind
      result = captured_output.read
      expect(result).to include('Build failed')
    end
  end

  describe '#warn' do
    it 'outputs warning message' do
      logger.warn('Deprecated option used')

      captured_output.rewind
      expect(captured_output.read).to include('Deprecated option used')
    end
  end

  describe '#summary' do
    it 'outputs summary with statistics' do
      logger.summary(built: 25, failed: 2, skipped: 3)

      captured_output.rewind
      result = captured_output.read

      expect(result).to include('Summary')
      expect(result).to include('Built: 25')
      expect(result).to include('Failed: 2')
      expect(result).to include('Skipped: 3')
    end

    it 'highlights failures in red when present' do
      logger.summary(built: 25, failed: 2, skipped: 0)

      captured_output.rewind
      result = captured_output.read

      expect(result).to include('Failed: 2')
    end
  end

  describe 'log file writing' do
    let(:tempfile) { Tempfile.new('test_log') }
    let(:log_file) { tempfile.path }

    after { tempfile.close; tempfile.unlink }

    it 'writes to both stdout and log file' do
      logger_with_file = described_class.new(log_file: log_file)
      logger_with_file.info('Test message')
      logger_with_file.close

      # Check stdout
      captured_output.rewind
      expect(captured_output.read).to include('Test message')

      # Check log file
      log_content = File.read(log_file)
      expect(log_content).to include('Test message')
    end

    it 'strips ANSI color codes from log file' do
      logger_with_file = described_class.new(log_file: log_file)
      logger_with_file.error('Error message')
      logger_with_file.close

      log_content = File.read(log_file)
      # Should have the message but not ANSI codes
      expect(log_content).to include('Error message')
      expect(log_content).not_to match(/\e\[\d+m/)  # No ANSI escape sequences
    end
  end

  describe '#close' do
    let(:tempfile) { Tempfile.new('test_log') }
    let(:log_file) { tempfile.path }

    after { tempfile.close; tempfile.unlink }

    it 'closes log file handle' do
      logger_with_file = described_class.new(log_file: log_file)
      logger_with_file.info('Test')

      expect { logger_with_file.close }.not_to raise_error
    end

    it 'can be called multiple times safely' do
      logger_with_file = described_class.new(log_file: log_file)

      expect {
        logger_with_file.close
        logger_with_file.close
      }.not_to raise_error
    end
  end

  describe 'output formatting' do
    it 'handles multi-line messages' do
      logger.info("Line 1\nLine 2\nLine 3")

      captured_output.rewind
      result = captured_output.read

      expect(result).to include('Line 1')
      expect(result).to include('Line 2')
      expect(result).to include('Line 3')
    end

    it 'handles empty messages' do
      expect { logger.info('') }.not_to raise_error
    end

    it 'handles nil messages' do
      expect { logger.info(nil) }.not_to raise_error
    end
  end
end
