# minarch-cores

Build system for libretro cores targeting ARM devices.

## Overview

Builds libretro emulator cores for ARM-based retro handhelds using official libretro recipes via Docker. Supports both clean builds (unmodified cores) and patched builds (minarch customizations).

## Prerequisites

- Docker
- Make
- 20+ GB free disk space
- 2-3 hours for initial build

## Quick Start

```bash
# Build all cores for 64-bit ARM devices
make build-aarch64

# Build all cores for 32-bit ARM devices (NEON+hardfloat)
make build-arm7neonhf

# Build both architectures
make build-all

# Package for distribution
make package-all
```

## Build Targets

### Clean Builds (Official Unmodified Cores)
- `make build-arm7neonhf` - Build ~134 32-bit ARM cores
- `make build-aarch64` - Build ~137 64-bit ARM cores
- `make build-all` - Build both architectures

### Patched Builds (minarch Customizations)
- `make build-arm7neonhf-patched` - Build patched 32-bit cores
- `make build-aarch64-patched` - Build patched 64-bit cores
- `make build-all-patched` - Build all clean + patched

### Packaging (Distribution Zips)
- `make package-arm7neonhf` - Create `linux-arm7neonhf.zip`
- `make package-aarch64` - Create `linux-aarch64.zip`
- `make package-arm7neonhf-patched` - Create `linux-arm7neonhf-patched.zip`
- `make package-aarch64-patched` - Create `linux-aarch64-patched.zip`
- `make package-all` - Create all 4 zip files

### Utilities
- `make clean` - Remove build artifacts
- `make shell` - Open shell in build container for debugging

## Output

Built cores are placed in:
- `build/arm7neonhf/` - Clean 32-bit ARM cores
- `build/aarch64/` - Clean 64-bit ARM cores
- `build/arm7neonhf-patched/` - Patched 32-bit ARM cores
- `build/aarch64-patched/` - Patched 64-bit ARM cores

Distribution zips are created in the project root.

## Configuration

Edit `config.env`:
- `JOBS` - Parallel build jobs (default: 10)
- `PATCHED_CORES` - Space-separated list of cores to patch

## Adding Patches

1. Create patch file: `patches/<corename>-<description>.patch`
2. Add core to `PATCHED_CORES` in `config.env`
3. Run `make build-arm7neonhf-patched` or `make build-aarch64-patched`

## Architecture Support

- **arm7neonhf**: 32-bit ARMv7 with NEON SIMD + hard float (Cortex-A7+)
- **aarch64**: 64-bit ARMv8 (Cortex-A53+)

Targets modern retro handhelds (2015+). Does not support legacy ARMv6 or non-NEON devices.

## Project Structure

```
minarch-cores/
├── Dockerfile              # Build environment (Debian Buster)
├── Makefile               # Build orchestration
├── config.env             # Build configuration
├── recipes/               # Custom libretro recipes
│   └── linux/
│       ├── cores-linux-aarch64
│       ├── cores-linux-aarch64-patched
│       └── cores-linux-arm7neonhf-patched
├── patches/               # minarch-specific patches
├── libretro-super/        # Official libretro build system (submodule)
└── build/                 # Build output (gitignored)
```

## Build System

Uses official libretro-buildbot-recipe.sh with:
- Debian Buster (glibc 2.28, GCC 8.3.0)
- ARM cross-compilation toolchains
- Recipe-based core selection
- Parallel builds for speed

## License

Individual cores have their own licenses. See each core's repository for details.
