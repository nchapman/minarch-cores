# Test Suite

This directory contains RSpec tests for the LessUI-Cores build system.

## Running Tests

```bash
# Run all tests
make test

# Or use bundle directly
bundle exec rspec

# Run specific test file
bundle exec rspec spec/command_builder_spec.rb

# Run specific test
bundle exec rspec spec/command_builder_spec.rb:20
```

## Test Structure

### Unit Tests

- **`spec/command_builder_spec.rb`** - Tests for command construction logic
  - Make command generation (platform, extra_args, parallelism)
  - CMake command generation (cross-compile flags, standards)
  - Special case handling (flycast-xtreme platform detection)

### Integration Tests

- **`spec/integration/recipe_command_spec.rb`** - Tests using real recipe data
  - Validates all cores in `recipes/linux/cortex-a53.yml`
  - Ensures commands can be generated for all Make/CMake cores
  - Verifies required metadata fields exist

## What's Tested

### CommandBuilder

The `CommandBuilder` class centralizes all build command construction:

1. **Make builds**: Platform detection, extra_args, parallelism
2. **CMake builds**: Cross-compilation flags, C/C++ standards, optimization
3. **Special cases**: Core-specific platform overrides (e.g., flycast-xtreme)

### Coverage

- ✅ All 4 CPU families (cortex-a7, cortex-a53, cortex-a55, cortex-a76)
- ✅ Both build types (Make and CMake)
- ✅ Platform resolution (explicit, nil, variable references)
- ✅ Recipe extra_args and cmake_opts
- ✅ ARM32-specific handling (C99/C++11 standards)
- ✅ flycast-xtreme special case for all CPU families
- ✅ All cores in cortex-a53 recipe can generate valid commands

## Adding Tests

When adding new cores or build logic:

1. Add unit tests to `spec/command_builder_spec.rb`
2. Integration tests automatically validate all recipe cores
3. Run `make test` to verify

## Test Philosophy

These tests ensure:

1. **Command correctness** - Generated commands match expected structure
2. **Recipe validation** - All cores have required metadata
3. **Regression prevention** - Changes don't break existing cores
4. **Documentation** - Tests serve as examples of how commands are built

The test suite runs fast (~0.03s) and provides confidence when refactoring build logic.
