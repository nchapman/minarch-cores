# LessUI-Cores

Build libretro emulator cores for ARM-based retro handhelds using Knulli's tested configurations.

**Ruby-based build system** - Fast, maintainable, and production-ready!

## Current Status

✅ **78/78 cores** - Recipe generation (100%)
✅ **78/78 cores** - Source fetching (100%)
✅ **64/78 cores** - Building successfully (82%)

## Quick Start

```bash
# 1. Generate recipes from Knulli
make recipes-cortex-a53

# 2. Build all cores
make build-cortex-a53

# 3. Package for distribution
make package-cortex-a53
```

**Output:** `dist/linux-cortex-a53.zip` (64 cores @ ~130-190 MB)
**Build time:** ~25-35 minutes with JOBS=4

## Supported CPU Families

| CPU Family | Devices | Market Share |
|------------|---------|--------------|
| **cortex-a53** | Anbernic RG28xx/35xx/40xx, Trimui | ~70% |
| **cortex-a55** | Miyoo Flip, RGB30, RG353, RK3566 | ~15% |
| **cortex-a7** | Miyoo Mini series | ~15% |
| **cortex-a35** | RG351 series (legacy) | Legacy |
| **cortex-a76** | Retroid Pocket 5, RK3588 | Premium |

### CPU Family Details

Each CPU family uses optimized compiler flags for best performance:

**Cortex-A53** (64-bit, ARMv8-a baseline)
- Arch: `aarch64`
- Flags: `-march=armv8-a+crc -mcpu=cortex-a53 -mtune=cortex-a53`
- Features: CRC extensions
- Devices: H700/A133 SoCs (RG35xx, RG40xx, Trimui)

**Cortex-A55** (64-bit, ARMv8.2-a advanced)
- Arch: `aarch64`
- Flags: `-march=armv8.2-a+crc+crypto+dotprod -mcpu=cortex-a55 -mtune=cortex-a55`
- Features: Crypto extensions, dot product (ML/AI)
- Devices: RK3566/RK3568 (RGB30, RG353, Miyoo Flip)

**Cortex-A7** (32-bit, ARMv7)
- Arch: `arm`
- Flags: `-march=armv7ve -mcpu=cortex-a7 -mtune=cortex-a7`
- Features: Virtualization extensions, NEON
- Devices: R16 SoC (Miyoo Mini, A30)

**Cortex-A35** (64-bit, ARMv8-a with SIMD)
- Arch: `aarch64`
- Flags: `-march=armv8-a+crc+fp+simd -mcpu=cortex-a35 -mtune=cortex-a35`
- Features: Floating point, SIMD optimizations
- Devices: RK3326 (RG351 series, GameForce)

**Cortex-A76** (64-bit big.LITTLE, ARMv8.2-a)
- Arch: `aarch64`
- Flags: `-march=armv8.2-a+crc+crypto+rcpc+dotprod -mtune=cortex-a76.cortex-a55`
- Features: Release-consistent, tuned for big.LITTLE (A76+A55)
- Devices: RK3588, Snapdragon (Retroid Pocket 5)

## How It Works

1. **Extract from Knulli**: Uses Make to evaluate Knulli's `.mk` files, extracting tested commit hashes and build configs
2. **Filter cores**: Uses CPU-specific core lists (78 cores for cortex-a53, tested by Knulli on RG35xx)
3. **Build in Docker**: Cross-compiles with CPU-optimized flags in Debian Buster (glibc 2.28) for maximum device compatibility

### Benefits

✅ **Knulli's tested commits** - Production-proven on real hardware
✅ **Auto-updates** - Re-run extraction when Knulli updates
✅ **No Buildroot complexity** - Simple recipe-based builds
✅ **Proven build system** - Uses tested fetch/build scripts
✅ **glibc 2.28 compatibility** - Works on older device firmware

## Build Commands

```bash
# Build specific CPU family
make build-cortex-a53
make build-cortex-a55
make build-cortex-a7

# Build all families
make build-all

# Package builds
make package-cortex-a53
make package-all

# Clean
make clean-cortex-a53
make clean
```

## Updating from Knulli

When Knulli updates their cores:

```bash
cd /Users/nchapman/knulli
git pull

cd /Users/nchapman/Drive/Code/LessUI-Cores
make recipes-cortex-a53
```

This regenerates recipes with updated commits.

## Build Environment

- **Docker**: Debian Buster
- **Compiler**: GCC 8.3.0
- **glibc**: 2.28 (for maximum compatibility)
- **Toolchains**: arm-linux-gnueabihf, aarch64-linux-gnu

## Architecture

```
minarch-cores/
├── config/                      # CPU family configs
│   ├── cortex-a53.config        # Compiler flags
│   ├── cores-cortex-a53.list    # Enabled cores (78 cores)
│   ├── cortex-a55.config
│   ├── cores-cortex-a55.list
│   └── ...
├── recipes/linux/               # Generated recipes (JSON)
│   ├── cortex-a53.json          # 78 cores with commit SHAs
│   └── ...
├── lib/                         # Ruby build system
│   ├── logger.rb                # Colored output
│   ├── cpu_config.rb            # Parse CPU configs
│   ├── mk_parser.rb             # Parse Knulli .mk files
│   ├── recipe_generator.rb      # Generate recipes
│   ├── source_fetcher.rb        # Fetch sources
│   ├── core_builder.rb          # Build individual cores
│   └── cores_builder.rb         # Orchestrate builds
├── scripts/                     # Entry points
│   ├── generate-recipes         # Generate JSON recipes
│   ├── build-all                # Build all cores
│   ├── build-one                # Build single core
│   └── fetch-sources            # Fetch source code
├── Dockerfile                   # Debian Buster build environment
└── Makefile                     # Build orchestration
```

## Output

Cores are built as `.so` files:
- `build/cortex-a53/*.so` - Individual cores
- `dist/linux-cortex-a53.zip` - Distribution package

## Requirements

- Docker
- ~10GB disk space
- 1-3 hours build time

## License

Individual cores have their own licenses (typically GPLv2). See upstream repositories for details.
