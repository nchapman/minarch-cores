# Core Selection Methodology

This document explains how we chose which libretro cores to use for each system.

## Overview

Our core selection is based on **Knulli's battle-tested configurations** for real handheld devices, ensuring we use cores that actually work well on the target hardware.

## Why Knulli?

[Knulli](https://github.com/knulli-cfw/distribution) is a Linux distribution specifically designed for retro gaming handhelds. They:
- Test cores on actual devices (RG35xx, RG40xx, etc.)
- Optimize for ARM performance and battery life
- Maintain compatibility with hundreds of handhelds
- Make device-specific choices (weak vs powerful CPUs)

Rather than guess which cores work best, we leverage their real-world testing.

## How We Used Knulli

### 1. System List
We started with systems from:
- **MinUI** (13 core systems) - Minimalist, proven essentials
- **Onion OS** - Popular RG35xx CFW system list
- **Additions** - N64, Dreamcast, PSP (requested features)

**Result:** 35 systems total

### 2. Core Choices Per CPU Family

We parsed Knulli's `Config.in` files to extract their actual core selections:

#### Cortex-A7 (ARM32, low-end devices like Raspberry Pi 1)
**Source:** Knulli's BCM2835 configuration

Example cores:
- **SNES:** `pocketsnes` - ARM-optimized, lightest option
- **Atari 2600:** `stella2014` - 2014 version, lighter than current
- **GBA:** `gpsp` - Uses dynarec for speed
- **PSX:** `pcsx` - Lighter than beetle-psx
- **Arcade:** `fbalpha` - Lighter than fbneo

**Philosophy:** Prioritize speed over accuracy

#### Cortex-A53/A55/A76 (ARM64, mid to high-end handhelds)
**Source:** Knulli's H700/A133 configuration (RG35xx, RG40xx devices)

Example cores:
- **SNES:** `snes9x` - Balance of speed and accuracy
- **Atari 2600:** `stella` - Current, more accurate version
- **GBA:** `mgba` - More accurate than gpsp
- **PSX:** `beetle-psx` - More accurate than pcsx
- **Arcade:** `fbneo` - Newer, more games
- **Dreamcast:** `flycast-xtreme` - Knulli's H700/A133 choice

**Philosophy:** Balance accuracy and performance

## Validation Process

1. **Parsed Knulli's Config.in** - Extracted actual conditional selects
2. **Verified core existence** - All cores exist in Knulli's libretro packages
3. **Matched device targets** - Our CPU families map to Knulli's device categories
4. **Cross-referenced MinUI** - Confirmed overlap with MinUI's proven cores

## Key Decisions

### Dreamcast: flycast-xtreme vs flycast
- **Choice:** `flycast-xtreme`
- **Why:**
  - Knulli's preferred choice for H700/A133 (our target devices)
  - Uses Makefile build (avoids GCC 8.3 CMake bug we encountered)
  - Specifically optimized for ARM handhelds

### GBA: gpsp vs mgba
- **cortex-a7:** `gpsp` (Knulli BCM2835 choice)
  - Uses dynarec (dynamic recompilation) for speed
  - Knulli also makes this available for H700/A133 as a lighter option
- **cortex-a53+:** `mgba` (Knulli default for ARM64)
  - More accurate, better compatibility
  - Fast enough on ARM64

### SNES: Multiple Options
- **cortex-a7:** `pocketsnes` (Knulli BCM2835 choice)
  - ARM-optimized
  - Note: MinUI uses `snes9x2005_plus` which Knulli doesn't carry
- **cortex-a53+:** `snes9x` (Knulli default)
- **cortex-a76:** `bsnes` (cycle-accurate, for powerful devices)

## Configuration File

All choices are documented in `config/systems.yml`:

```yaml
snes:
  name: Super Nintendo Entertainment System
  cores:
    default: snes9x
    cortex-a7: pocketsnes  # ARM-optimized, lightest SNES core
    cortex-a76: bsnes  # Cycle-accurate on powerful devices
```

Each core choice includes:
- Default (used unless overridden)
- CPU-specific overrides
- Comments explaining the choice
- References to Knulli configuration when applicable

## Generating Core Lists

Core lists are auto-generated from `systems.yml`:

```bash
# Generate cores for a specific CPU family
ruby scripts/generate-cores-from-systems cortex-a53

# Output: config/cores-cortex-a53.list
```

This ensures consistency and traceability.

## Sources

- **Knulli repository:** https://github.com/knulli-cfw/distribution
- **Config.in file:** `package/batocera/core/batocera-system/Config.in`
- **Device targets:**
  - BCM2835 (cortex-a7): Raspberry Pi 1
  - H700/A133 (cortex-a53): RG35xx, RG40xx, Trimui devices

## Summary

Every core choice is:
✅ Based on Knulli's tested configurations
✅ Validated against real hardware
✅ CPU-appropriate (lighter cores for weaker CPUs)
✅ Documented and traceable

We're not guessing - we're using proven configurations from a project that tests on actual handheld hardware.
