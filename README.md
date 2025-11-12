# minarch-cores

Pre-compiled libretro emulator cores for ARM-based retro handhelds.

## Downloads

We provide four different core packages optimized for ARM Linux devices:

### Standard Builds

**linux-arm7neonhf.zip** - 32-bit ARM cores
- For ARMv7 devices with NEON (Cortex-A7 and newer)
- Examples: Anbernic RG35XX (original), Miyoo Mini Plus, Trimui Smart Pro
- 130+ cores including NES, SNES, Genesis, PlayStation, GBA, and more

**linux-aarch64.zip** - 64-bit ARM cores
- For ARMv8 64-bit devices (Cortex-A53 and newer)
- Examples: Anbernic RG35XX-H/Plus/SP, Retroid Pocket, Powkiddy devices
- 130+ cores with better performance for demanding systems
- Includes N64 (mupen64plus_next) with dynarec

### Custom Builds

**linux-arm7neonhf-custom.zip** - 32-bit ARM cores with minarch customizations
- Same as standard 32-bit build, plus cores with custom patches
- Currently includes: Gambatte (Game Boy/Color) with enhanced features

**linux-aarch64-custom.zip** - 64-bit ARM cores with minarch customizations
- Same as standard 64-bit build, plus cores with custom patches
- Currently includes: Gambatte (Game Boy/Color) with enhanced features

## Which Package Do I Need?

1. **Check your device's CPU architecture**:
   - If your device runs a 64-bit OS → use `aarch64` (better performance)
   - If your device runs a 32-bit OS → use `arm7neonhf`

2. **Choose standard or custom**:
   - Most users want the standard builds
   - Use custom builds if you want the minarch-specific enhancements

If unsure, try the standard 64-bit build first (`linux-aarch64.zip`). Most modern retro handhelds support it.

## What's Included

Standard packages contain 130+ libretro cores covering systems like:
- Nintendo: NES, SNES, N64, GB/GBC, GBA, DS
- Sega: Genesis/MD, Master System, Game Gear, Saturn, Dreamcast
- Sony: PlayStation, PSP
- Arcade: MAME, FBNeo, CPS1/2/3
- And many more retro systems

See the recipe files in `recipes/linux/` for the complete list.

## Build Information

All cores are built using:
- Official libretro recipes and sources
- Debian Buster (glibc 2.28, GCC 8.3.0) for maximum compatibility
- ARM cross-compilation toolchains
- Optimized flags: NEON SIMD, hard float, Cortex-A7/A53 tuning

Cores include upstream build fixes for cross-compilation issues. Custom builds additionally include minarch-specific behavior patches.

---

## Building from Source

### Prerequisites

- Docker
- Make
- 20+ GB free disk space
- 2-3 hours for initial build

### Quick Start

```bash
# Build all standard cores + create packages
make all

# Or build specific architectures
make build-arm7neonhf        # 32-bit cores only
make build-aarch64           # 64-bit cores only
make build-all               # Both architectures

# Package for distribution
make package-all             # Creates all 4 zip files
```

### Build Targets

**Standard builds:**
- `make build-arm7neonhf` - Build 32-bit ARM cores
- `make build-aarch64` - Build 64-bit ARM cores
- `make build-all` - Build both architectures

**Custom builds (with patches):**
- `make build-arm7neonhf-custom` - Build custom 32-bit cores
- `make build-aarch64-custom` - Build custom 64-bit cores
- `make build-all-custom` - Build all clean + custom

**Packaging:**
- `make package-arm7neonhf` - Create `linux-arm7neonhf.zip`
- `make package-aarch64` - Create `linux-aarch64.zip`
- `make package-arm7neonhf-custom` - Create `linux-arm7neonhf-custom.zip`
- `make package-aarch64-custom` - Create `linux-aarch64-custom.zip`
- `make package-all` - Create all 4 zip files

**Utilities:**
- `make clean` - Remove build artifacts
- `make shell` - Open shell in build container
- `JOBS=N make build-*` - Set parallel jobs (default: 8)

### Output

Built cores: `build/{arm7neonhf,aarch64,arm7neonhf-custom,aarch64-custom}/`
Distribution packages: `dist/*.zip`

### Configuration

Edit `config.env` to customize:
- `JOBS` - Parallel build jobs
- `BUILD_FIX_CORES` - Cores with build fix patches
- `CUSTOM_CORES` - Cores with custom behavior patches

### Project Structure

```
minarch-cores/
├── Dockerfile           # Build environment (Debian Buster)
├── Makefile            # Build orchestration
├── config.env          # Build configuration
├── scripts/            # Build scripts
│   ├── fetch-cores.sh  # Repository management
│   └── build-cores.sh  # Cross-compilation build
├── recipes/            # Core recipes (which cores to build)
│   └── linux/
│       ├── cores-linux-arm7neonhf
│       ├── cores-linux-aarch64
│       ├── cores-linux-arm7neonhf-custom
│       └── cores-linux-aarch64-custom
├── patches/            # Patch files
│   ├── build/          # Build fixes (all builds)
│   └── custom/         # Custom patches (custom builds only)
├── cores/              # Cloned core repositories (gitignored)
├── build/              # Build output (gitignored)
└── dist/               # Distribution packages (gitignored)
```

## License

Individual cores have their own licenses. See each core's repository for details.
