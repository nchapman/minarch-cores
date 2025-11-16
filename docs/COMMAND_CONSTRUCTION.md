# Command Construction Reference

This document explains exactly how build commands are constructed from recipe files, with clear specification of what gets appended vs replaced.

## Make Builds

### Command Structure

```bash
make -f <makefile> -j<parallel> <make_args...>
```

### Argument Order (All Appended)

Arguments are constructed in this order:

1. **Platform** - `platform=<value>`
   - Source: Recipe `platform` field OR CPU config default
   - Special: flycast-xtreme overrides platform per CPU family

2. **Recipe extra_args** - From YAML `extra_args` array
   - Example: `USE_BLARGG_APU=1` (snes9x2005)
   - Appended as-is from recipe

3. **Special case args** - Core-specific overrides
   - Example: flycast-xtreme adds `HAVE_OPENMP=1 FORCE_GLES=1 ARCH=arm64 LDFLAGS=-lrt`
   - Appended AFTER recipe args (can override recipe values)

### Make Variable Resolution

**Important:** Make uses **last value wins** for variables. If the same variable appears multiple times, the last occurrence takes precedence.

Example for flycast-xtreme on cortex-a53:
```bash
make -f Makefile -j4 platform=odroid-n2 HAVE_OPENMP=1 FORCE_GLES=1 ARCH=arm64 LDFLAGS=-lrt
```

### Recipe Example

```yaml
snes9x2005:
  platform: unix           # → platform=unix
  extra_args:
    - USE_BLARGG_APU=1     # → appended after platform
```

Result:
```bash
make -f Makefile -j4 platform=unix USE_BLARGG_APU=1
```

## CMake Builds

### Command Structure

```bash
cmake .. <cmake_args...>
make -j<parallel>
```

### Argument Order (Recipe First, Then Defaults)

Arguments are constructed in this order:

1. **Recipe cmake_opts** - From YAML `cmake_opts` array
   - Example: `-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=FALSE`
   - These come FIRST to allow override by later arguments

2. **Cross-compile settings** - Always added
   - `-DCMAKE_C_COMPILER=<toolchain>gcc`
   - `-DCMAKE_CXX_COMPILER=<toolchain>g++`
   - `-DCMAKE_C_FLAGS=<cpu_flags>`
   - `-DCMAKE_CXX_FLAGS=<cpu_flags>`
   - `-DCMAKE_SYSTEM_PROCESSOR=<arch>`
   - `-DTHREADS_PREFER_PTHREAD_FLAG=ON`

3. **Build type default** - Only if not in recipe
   - `-DCMAKE_BUILD_TYPE=Release`
   - **Skipped if recipe already specified CMAKE_BUILD_TYPE** (avoids duplicates)

4. **ARM32 standards** - Forced for ARM32 (overrides recipe)
   - `-DCMAKE_C_STANDARD=99`
   - `-DCMAKE_CXX_STANDARD=11`
   - Only added when `arch == 'arm'` (cortex-a7)

5. **CMAKE_PREFIX_PATH** - If environment variable set
   - `-DCMAKE_PREFIX_PATH=<path>`

### CMake Variable Resolution

**Important:** CMake uses **last value wins** for duplicate `-D` options. Our build system is careful to:
- Put recipe opts FIRST (can be overridden)
- Check for duplicates (CMAKE_BUILD_TYPE)
- Force critical values LAST (ARM32 standards)

### Recipe Example (swanstation)

```yaml
swanstation:
  build_type: cmake
  cmake_opts:
    - "-DCMAKE_BUILD_TYPE=Release"    # Already includes this
    - "-DBUILD_SHARED_LIBS=FALSE"
    - "-DUSE_WAYLAND=OFF"
```

Result (no duplicate CMAKE_BUILD_TYPE):
```bash
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \          # From recipe
  -DBUILD_SHARED_LIBS=FALSE \           # From recipe
  -DUSE_WAYLAND=OFF \                   # From recipe
  -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc \
  -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
  -DCMAKE_C_FLAGS=-O2... \
  -DCMAKE_CXX_FLAGS=-O2... \
  -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
  -DTHREADS_PREFER_PTHREAD_FLAG=ON
  # CMAKE_BUILD_TYPE NOT added again (already in recipe)
```

## Special Cases

### flycast-xtreme Platform Detection

flycast-xtreme requires CPU-specific platform values:

| CPU Family | Platform | Extra Args |
|------------|----------|------------|
| cortex-a7 | `arm` | `HAVE_OPENMP=1 FORCE_GLES=1 ARCH=arm LDFLAGS=-lrt` |
| cortex-a53 | `odroid-n2` | `HAVE_OPENMP=1 FORCE_GLES=1 ARCH=arm64 LDFLAGS=-lrt` |
| cortex-a55 | `odroidc4` | `HAVE_OPENMP=1 FORCE_GLES=1 ARCH=arm64 LDFLAGS=-lrt` |
| cortex-a76 | `arm64` | `HAVE_OPENMP=1 FORCE_GLES=1 ARCH=arm64 LDFLAGS=-lrt` |

**Note:** The platform override happens in `resolve_platform()`, BEFORE recipe `extra_args` are added.

### ARM32 C/C++ Standards

For ARM32 (cortex-a7), we force C99 and C++11 to avoid glibc Float128 issues with GCC 8.3:

```bash
-DCMAKE_C_STANDARD=99
-DCMAKE_CXX_STANDARD=11
```

These are added LAST and will override any `CMAKE_C_STANDARD` or `CMAKE_CXX_STANDARD` in the recipe.

## Tested Configurations

All recipes are validated by integration tests:

✅ **26 cores** in cortex-a7 (ARM32)
✅ **30 cores** in cortex-a53/a55 (ARM64)
✅ **31 cores** in cortex-a76 (ARM64)

Every core verified to:
- Have all required metadata fields
- Generate valid Make/CMake commands
- Not have duplicate CMAKE_BUILD_TYPE (for CMake cores)
- Include all recipe-specified arguments

## Adding New Cores

### Make-based Core

```yaml
my-new-core:
  build_type: make
  platform: unix           # or null to use CPU config default
  makefile: Makefile.libretro
  extra_args:              # Optional - any extra make variables
    - CUSTOM_FLAG=1
  # ...other fields
```

Result: `make -f Makefile.libretro -j4 platform=unix CUSTOM_FLAG=1`

### CMake-based Core

```yaml
my-cmake-core:
  build_type: cmake
  cmake_opts:              # Optional - custom CMake options
    - "-DCUSTOM_OPTION=ON"
  # ...other fields
```

Result: Custom options come FIRST, then our cross-compile settings are appended.

### Core with Platform Override

If your core needs a different platform per CPU:
1. Add special case logic to `CommandBuilder#resolve_platform`
2. Add special case args to `CommandBuilder#special_case_args`
3. Add comprehensive tests (see flycast-xtreme example)

**Prefer recipe-based configuration over code!** Only add special cases when unavoidable.
