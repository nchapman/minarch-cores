# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

minarch-cores is a build system for creating architecture-optimized libretro emulator cores for ARM-based retro handhelds running MinUI. It builds ~30 cores per architecture, supporting all MinUI required cores plus additional systems.

**Key Architecture:** Manual YAML recipes define which cores to build for each CPU family. Recipes are the single source of truth - edit them directly to add/update/remove cores.

**MinUI Compatibility:** All 13 MinUI required cores are built for all CPU families to ensure upgrade compatibility from MinUI.

## Common Build Commands

```bash
# Build cores for specific architecture
make build-arm32    # ARM32: All 32-bit devices
make build-arm64    # ARM64: All 64-bit devices

# Build all (1-3 hours per architecture)
make build-all

# Build single core for testing/debugging
make core-arm64-gambatte
make core-arm32-flycast

# Package builds
make package-arm64
make package-all

# Clean
make clean          # Clean all build outputs
make clean-arm64    # Clean specific architecture
```

## Build System Architecture

### Simple Two-Phase Build Flow

**Phase 1: Recipes → Fetched Sources**
- **Input:** `recipes/linux/{cpu}.yml` (YAML files with core definitions)
- **Script:** `lib/source_fetcher.rb`
- **Output:** `output/cores/{corename}/` (git clones at specific commits)

**Phase 2: Sources → Built Cores**
- **Input:** Fetched sources + CPU config from YAML (compiler flags)
- **Script:** `lib/core_builder.rb`
- **Output:** `output/{cpu}/*.so` files (compiled cores)

### Ruby Library Organization

- **`lib/cores_builder.rb`** - Main orchestrator; coordinates fetching and building
- **`lib/cpu_config.rb`** - Extracts CPU config from recipe YAML files into Ruby objects
- **`lib/source_fetcher.rb`** - Clones/fetches git repositories at specific commits
- **`lib/core_builder.rb`** - Executes builds for individual cores
- **`lib/logger.rb`** - Centralized logging with sections and timestamps

### Data Flow

```
recipes/linux/{cpu}.yml → source_fetcher → output/cores/
                              ↓
                        core_builder → output/{cpu}/*.so
```

## Key Configuration Files

### `recipes/linux/{cpu}.yml` - Source of Truth

These are **manually maintained YAML files** that define which cores to build for each CPU family. Edit them directly to add/update/remove cores.

**Location:**
- `recipes/linux/arm32.yml` - ARMv7VE + NEON-VFPv4 (All ARM32 devices)
- `recipes/linux/arm64.yml` - ARMv8-A + NEON (All ARM64 devices)

**Recipe Entry Format (Explicit & Minimal):**
```yaml
atari800:
  repo: libretro/libretro-atari800
  commit: 6a18cb23cc4a7cecabd9b16143d2d7332ae8d44b
  build_type: make
  makefile: Makefile
  build_dir: "."
  platform: unix
  so_file: atari800_libretro.so
```

**Required fields:**
- `repo` - GitHub org/repo (URL auto-constructed)
- `commit` - Git SHA or tag
- `build_type` - `make` or `cmake`
- For make: `makefile`, `build_dir`, `platform`, `so_file`
- For cmake: `cmake_opts`, `so_file`

**Optional fields:**
- `submodules: true` - Only include if needed
- `extra_args: [...]` - Only for special cases
- `clean_extra: "rm -f file.o"` - Only if make clean is broken

**Important Notes:**
- Recipes are explicit - no guessing or fallbacks
- Auto-constructs GitHub tarball URLs from repo + commit
- Uses actual .so output names (no renaming)
- Cores sorted alphabetically
- Missing required fields = immediate clear error

### CPU Configuration (Embedded in YAML)

Each recipe YAML file now contains a `config:` section with CPU-specific compiler flags and architecture settings. This eliminates the need for separate `.config` files.

**Key configuration fields:**
- `arch` - Architecture (arm, aarch64)
- `target_cross` - Compiler prefix (arm-linux-gnueabihf-, aarch64-linux-gnu-)
- `target_optimization` - CPU-specific march/mcpu/mtune flags
- `target_float` - Floating point ABI and FPU settings
- `target_cflags` / `target_cxxflags` - Base compiler optimization flags

**Do not edit the config section unless you understand ARM CPU architecture specifics.**

## Adding New Cores

**Simple 3-step process:**

### 1. Find the commit
```bash
git ls-remote --heads https://github.com/libretro/libretro-atari800.git | grep master
# Result: 6a18cb23cc4a7cecabd9b16143d2d7332ae8d44b
```

Or check the core's GitHub releases/tags for stable versions.

### 2. Add to recipe (alphabetically)

Edit `recipes/linux/arm64.yml`:

```yaml
cores:
  atari800:
    repo: libretro/libretro-atari800
    commit: 6a18cb23cc4a7cecabd9b16143d2d7332ae8d44b
    build_type: make
    makefile: Makefile
    build_dir: "."
    platform: unix
    so_file: atari800_libretro.so
```

### 3. Test and replicate

```bash
# Test on one architecture first
make core-arm64-atari800

# If successful, copy entry to arm32.yml
make core-arm32-atari800
```

**Helper script for inspecting new cores:**
```bash
./scripts/inspect-core libretro/libretro-atari800 6a18cb23cc4a
```

See `docs/adding-cores.md` for detailed guide with examples.

## Updating Cores

To update a core to a newer version:

1. **Find the latest commit:**
   ```bash
   git ls-remote --heads https://github.com/libretro/libretro-atari800.git | grep master
   ```

   Or check the core's GitHub releases for stable commits.

2. **Update the commit hash in recipes:**
   ```bash
   # Edit each architecture recipe
   vim recipes/linux/arm64.yml

   # Change only the commit field in the cores section:
   cores:
     atari800:
       commit: <new-commit-hash>  # ← Update this line
   ```

3. **Clean and rebuild:**
   ```bash
   # Delete fetched source to force re-download
   rm -rf output/cores-arm64/libretro-atari800

   # Test build
   make core-arm64-atari800

   # Update other architectures and test
   ```

**Note:** URLs are auto-constructed from repo + commit, so you only need to update the commit field.

## MinUI Required Cores

These 13 cores MUST be present on all CPU families for MinUI compatibility:

1. **fake08** - PICO-8 (fantasy console)
2. **fceumm** - Nintendo Entertainment System
3. **gambatte** - Game Boy / Game Boy Color
4. **gpsp** - Game Boy Advance (ARM32 optimized)
5. **beetle-pce-fast** - PC Engine / TurboGrafx-16 (mednafen_pce_fast)
6. **supafaust** - Super Nintendo (mednafen_supafaust)
7. **beetle-vb** - Virtual Boy (mednafen_vb)
8. **mgba** - Game Boy Advance (ARM64 / general purpose)
9. **pcsx** - PlayStation (pcsx_rearmed)
10. **picodrive** - Sega Genesis / Mega Drive / 32X
11. **pokemini** - Pokemon Mini
12. **race** - Neo Geo Pocket / Neo Geo Pocket Color
13. **snes9x2005** - Super Nintendo (snes9x2005_plus)

**Core Naming:** Some cores have different names in MinUI vs libretro. Our recipes use libretro names (e.g., `beetle-vb` instead of `mednafen_vb`).

## Build Environment

- **Docker:** Debian Buster (for glibc 2.28 compatibility)
- **Compiler:** GCC 8.3.0
- **Toolchains:** arm-linux-gnueabihf (ARM32), aarch64-linux-gnu (ARM64)
- **Parallel builds:** Controlled by `-j` flag or `JOBS` environment variable

## Architecture Details

| Package | Architecture | Devices |
|---------|--------------|---------|
| **arm32** | ARMv7VE + NEON-VFPv4 | All ARM32 devices (Miyoo Mini, RG35XX, Trimui Smart) |
| **arm64** | ARMv8-A + NEON | All ARM64 devices (RG28xx/40xx, CubeXX, Trimui) |

**Architecture Notes:**
- **arm32:** Cortex-A7 baseline optimizations, compatible with all ARM32 handhelds
- **arm64:** Cortex-A53 baseline for maximum ARM64 compatibility

## Troubleshooting

### Build Failures

1. Check build log: `output/logs/{cpu}-build.log`
2. Test single core: `make core-arm64-{corename}`
3. Verify recipe exists: `grep -A 10 "^  {corename}:" recipes/linux/{cpu}.yml`

### Missing Cores

1. Check if core is in recipe: `grep "^  {corename}:" recipes/linux/{cpu}.yml`
2. Add core to recipe file if missing (see "Adding New Cores" above)
3. Rebuild: `make build-{cpu}`

### Cross-Compilation Issues

- Ensure Docker image is built: `make docker-build`
- Check CPU config in recipe YAML: `recipes/linux/{cpu}.yml` (config section)
- Verify toolchain is available in Docker container: `make shell`

## Output Structure

```
output/
├── cores-arm32/    # Fetched sources for arm32
├── cores-arm64/    # Fetched sources for arm64
├── logs/           # Build logs
├── dist/           # Packaged zips
├── arm32/*.so      # ARM32 cores
└── arm64/*.so      # ARM64 cores
```

## Development Workflow

### Testing a New Core

```bash
# 1. Add core to recipes/linux/arm64.yml under cores: section

# 2. Build just that core
make core-arm64-{corename}

# 3. If successful, add to arm32.yml and test
make core-arm32-{corename}

# 4. Build for both architectures
make build-all
```

### Debugging Build Issues

```bash
# Open shell in build container
make shell

# Manually inspect source
cd output/cores/{corename}
ls -la

# Try manual build with verbose output
make -f Makefile.libretro platform=unix CC=gcc V=1
```

## Release and Deployment

### Creating a Release

The project uses git flow with automated releases triggered by UTC date-based tags (YYYYMMDD format):

```bash
# Create a new release (must be on develop branch)
./scripts/release

# Force re-release (overwrites existing tag/release for today)
./scripts/release --force
```

The release script will:
1. Validate you're on the `develop` branch with no uncommitted changes
2. Generate a UTC date-based tag (e.g., `20251115`)
3. If tag exists and `--force` flag used, delete local/remote tag and GitHub release
4. Execute git flow release start/finish
5. Push branches and tag to trigger GitHub Actions

**Force Mode:** Use `--force` to redeploy on the same day (e.g., after fixing a bad build). This deletes the existing tag and GitHub release (requires `gh` CLI for release deletion).

### GitHub Actions Workflow

When a tag matching YYYYMMDD format is pushed to `main`:
1. Builds Docker image
2. Runs `make build-all` for both architectures
3. Packages builds using `make package-all`
4. Creates GitHub Release with:
   - `linux-arm32.zip` - ARM32 cores
   - `linux-arm64.zip` - ARM64 cores
5. Updates `latest` tag to point to newest release

### Prerequisites for Deployment

- git-flow must be installed: `brew install git-flow` (macOS) or `apt-get install git-flow` (Linux)
- Repository must be on `develop` branch
- All changes must be committed
- GitHub repository must have Actions enabled

## Important Notes

- **Never commit `output/` directory** - It contains build artifacts and fetched sources
- **Recipes are git-tracked** - Your edits to YAML files are preserved in version control
- **Recipes are manually maintained** - No automatic generation; edit YAML files directly
- **Each architecture needs ~5GB disk space** - Plan accordingly
- **Build times are 1-3 hours per architecture** - Use `build-all` overnight
- **One release per day** - UTC date tags prevent multiple releases on the same day
