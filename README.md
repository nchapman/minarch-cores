# LessUI-Cores

Build libretro emulator cores for ARM-based retro handhelds running MinUI.

**Simple 2-architecture build system** - ARM32 and ARM64!

## Current Status

✅ **~30 cores per architecture** - All MinUI required cores plus extras
✅ **2 architectures** - arm32, arm64
✅ **YAML-based recipes** - Single source of truth with embedded CPU configs
✅ **Easily extensible** - Add cores by editing recipe YAML files

## Quick Start

```bash
# Build cores for all architectures
make build-all

# Or build individually:
make build-arm32  # All ARM32 devices
make build-arm64  # All ARM64 devices

# Package for distribution:
make package-all
```

## Supported Systems

Includes all 13 MinUI required cores plus 15-20 additional systems:

**Core Systems (MinUI Required):** NES, SNES, GB/GBC, GBA, Genesis, PS1, PCE, Neo Geo Pocket, Virtual Boy, Pokemon Mini, PICO-8
**Additional Systems:** Atari 2600/5200/7800, Lynx, Game Gear, Sega CD, N64, Dreamcast, PSP, and more


## Supported Devices

| Package | Devices | Architecture |
|---------|---------|--------------|
| **arm32** | Miyoo Mini, RG35XX, Trimui Smart | ARMv7VE + NEON-VFPv4 (Cortex-A7) |
| **arm64** | RG28xx/40xx, CubeXX, Trimui | ARMv8-A + NEON (Cortex-A53) |

### Architecture Details

**arm32**
- 32-bit ARM (armhf)
- Cortex-A7 baseline: `-march=armv7ve -mcpu=cortex-a7 -mfpu=neon-vfpv4`
- Compatible with all ARM32 retro handhelds

**arm64**
- 64-bit ARM (aarch64)
- Cortex-A53 baseline: `-march=armv8-a+crc -mcpu=cortex-a53`
- Compatible with all ARM64 retro handhelds

## How It Works

### Build Flow

1. **Edit recipes** (`recipes/linux/{arch}.yml`)
   - Manually maintained YAML files define which cores to build
   - Each recipe contains both CPU config and core definitions
   - Single source of truth for each architecture

2. **Build cores** (`scripts/build-all`)
   ```bash
   make build-arm64
   ```
   - Fetches source code from GitHub
   - Cross-compiles with architecture-optimized flags
   - Outputs `.so` files to `output/{arch}/`

### Benefits

✅ **Simple YAML format** - Config and cores in one file
✅ **Architecture-based** - Clear ARM32 vs ARM64 separation
✅ **Tested commits** - Stable releases from upstream
✅ **No Buildroot** - Direct cross-compilation
✅ **glibc 2.28** - Maximum device compatibility

## Adding New Cores

1. **Find the commit** from libretro:
   ```bash
   git ls-remote --heads https://github.com/libretro/gambatte-libretro.git | grep master
   ```

2. **Add to recipe** (edit `recipes/linux/arm64.yml`):
   ```yaml
   cores:
     gambatte:
       repo: libretro/gambatte-libretro
       commit: 47c5a2feaa9c253efc407283d9247a3c055f9efb
       build_type: make
       makefile: Makefile
       build_dir: "."
       platform: unix
       so_file: gambatte_libretro.so
   ```

3. **Test build**:
   ```bash
   make core-arm64-gambatte
   ```

4. **Replicate to other architectures** and rebuild

See `CLAUDE.md` for detailed instructions.

## Build Commands

```bash
# Build specific architecture
make build-arm32
make build-arm64

# Build all architectures
make build-all

# Build single core (for testing)
make core-arm64-gambatte

# Package builds
make package-arm64
make package-all

# Clean
make clean-arm64
make clean
```

## Updating Cores

To update a core to a newer commit:

```bash
# 1. Find latest commit
git ls-remote --heads https://github.com/libretro/gambatte-libretro.git | grep master

# 2. Edit recipe YAML (recipes/linux/arm64.yml)
#    Update just the commit field

# 3. Clean and rebuild
rm -rf output/cores-arm64/libretro-gambatte
make core-arm64-gambatte

# 4. If successful, update other architectures
```

Check the core's GitHub repository for stable releases and commits.

## Build Environment

- **Docker**: Debian Buster
- **Compiler**: GCC 8.3.0
- **glibc**: 2.28 (for maximum compatibility)
- **Toolchains**: arm-linux-gnueabihf, aarch64-linux-gnu

## Project Structure

```
LessUI-Cores/
├── recipes/linux/               # Manual YAML recipes (source of truth)
│   ├── arm32.yml                # ARM32 config + cores
│   └── arm64.yml                # ARM64 config + cores
├── lib/                         # Ruby build system
│   ├── cpu_config.rb            # Extract config from YAML recipes
│   ├── source_fetcher.rb        # Fetch git repos/tarballs
│   ├── core_builder.rb          # Build individual cores
│   ├── cores_builder.rb         # Orchestrate builds
│   └── command_builder.rb       # Construct Make/CMake commands
├── scripts/
│   ├── build-all                # Build all cores for architecture
│   ├── build-one                # Build single core (testing)
│   └── release                  # Create git flow release
├── output/                      # Build artifacts (not in git)
│   ├── cores-arm64/             # Fetched source code
│   ├── logs/                    # Build logs
│   ├── dist/                    # Packaged zips
│   └── arm64/*.so               # Built cores
├── Dockerfile                   # Debian Buster (GCC 8.3, glibc 2.28)
└── Makefile                     # Build orchestration
```

### Key Files

- **`recipes/linux/{arch}.yml`** - Single source of truth (config + cores)
- **`CLAUDE.md`** - Detailed guide for working with this codebase
- **`Makefile`** - All build commands

## Output

Cores are built as `.so` files:
- `output/arm64/*.so` - Individual cores
- `output/dist/linux-arm64.zip` - Distribution package
- `output/cores-arm64/` - Fetched source code
- `output/logs/` - Build logs

## Requirements

- Docker
- ~5GB disk space per architecture
- 1-3 hours build time per architecture

## Documentation

- **`CLAUDE.md`** - Complete guide to working with this codebase (start here!)
- **`docs/adding-cores.md`** - Detailed guide for adding new cores
- **`spec/`** - Test suite (81 examples)

## License

Individual cores have their own licenses (typically GPLv2). See upstream repositories for details.
