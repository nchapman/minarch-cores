# Test Suite

RSpec test suite for the minarch-cores build system.

## Running Tests

```bash
# Run all tests
make test

# Or use bundle directly
bundle exec rspec

# Run specific test file
bundle exec rspec spec/cpu_config_spec.rb

# Run with documentation format
bundle exec rspec --format documentation
```

## Test Coverage (81 examples, 0 failures)

### Unit Tests

- **`cpu_config_spec.rb`** (11 examples) - YAML config loading
  - Tests both architectures: arm32, arm64
  - Validates config section parsing from recipe YAML
  - Tests flag combination (optimization + float flags)

- **`command_builder_spec.rb`** (23 examples) - Command construction
  - Make command generation (platform, extra_args, toolchain vars)
  - CMake command generation (toolchain files, cross-compile flags)
  - ARM32-specific handling (C99/C++11 standards, library paths)

- **`source_fetcher_spec.rb`** (13 examples) - Source fetching logic
  - Tarball vs git clone selection
  - Parallel fetching with thread pool
  - Cache management and error handling

- **`core_builder_spec.rb`** (17 examples) - Build execution
  - Make/CMake build workflows
  - Command interception and validation
  - Dry-run mode, parallel builds, error handling

- **`logger_spec.rb`** (10 examples) - Logging functionality
  - Console output formatting
  - Log file writing with ANSI stripping

### Integration Tests

- **`integration/recipe_loading_spec.rb`** (7 examples) - Recipe format validation
  - Tests complete YAML recipe format (config + cores sections)
  - Validates both architectures load correctly
  - Tests error handling for malformed recipes

## What's Tested

### Full Build Pipeline

1. **Recipe Loading** - YAML parsing, config + cores extraction
2. **CPU Configuration** - Architecture settings, compiler flags
3. **Command Construction** - Make/CMake args with proper cross-compilation
4. **Source Fetching** - GitHub tarballs/repos with caching
5. **Core Building** - Build execution with command validation
6. **Logging** - Output formatting and file logging

### Coverage

- ✅ Both architectures (arm32, arm64)
- ✅ Both build types (Make and CMake)
- ✅ YAML recipe format validation
- ✅ ARM32 vs ARM64 differences (flags, standards, toolchains)
- ✅ Parallel builds and dry-run mode
- ✅ Error handling and statistics tracking

## Test Philosophy

These tests:

1. **Intercept commands** - Validate what gets executed without running builds
2. **Use minimal mocks** - Test real logic with stubbed I/O
3. **Run fast** - Complete suite in ~0.03 seconds
4. **Prevent regressions** - Ensure architecture changes don't break builds
5. **Document behavior** - Tests serve as executable documentation

Perfect for refactoring the build system with confidence!
