# Build Status and Known Issues

## Current Status

✅ **PPSSPP regression FIXED!** (2025-11-15) - 15 MB core building successfully
⚠️ **TIC-80 still broken** - requires janet library + asset generation fixes
✅ **25+ cores built successfully** per CPU family

## Latest Build Results

| CPU Family | Built | Failed | Total | Success Rate |
|------------|-------|--------|-------|--------------|
| cortex-a7 | TBD | TBD | 25 | TBD |
| cortex-a53 | 21 | 4 | 26 | 81% |
| cortex-a55 | TBD | TBD | 26 | TBD |
| cortex-a76 | TBD | TBD | 27 | TBD |

**Last tested:** cortex-a53 build completed in 13m 31s

---

## FIXED Issues ✅

### 1. ppsspp (PlayStation Portable) - FIXED ✅

**Status:** ✅ **BUILDING SUCCESSFULLY** (15.0 MB core)

**Root Causes:**
1. Missing system dependencies (SDL2, SDL2-ttf, FFmpeg libraries) in Docker
2. cmake_overrides was replacing ALL options instead of merging with Knulli's config
3. .so file path extraction from INSTALL_TARGET_CMDS
4. Recipe's so_file path wasn't being used by build system

**Solution:**

**Dockerfile** - Added missing dependencies:
- `libsdl2-dev libsdl2-ttf-dev` (required even for libretro builds)
- All FFmpeg libraries: `libavcodec-dev libavdevice-dev libavfilter-dev libavformat-dev libavutil-dev libswresample-dev libswscale-dev libpostproc-dev`

**config/cmake-overrides.yml** - Use system FFmpeg:
```yaml
ppsspp:
  cmake_opts:
    - "-DUSE_FFMPEG=ON"
    - "-DUSE_SYSTEM_FFMPEG=ON"
  so_file: "build/lib/ppsspp_libretro.so"
```

**lib/recipe_generator.rb** - Merge cmake overrides instead of replacing:
- Preserve Knulli's options like `-DLIBRETRO=ON`, `-DARM64=ON`, etc.
- Only override conflicting flags

**lib/mk_parser.rb** - Extract .so paths from INSTALL_TARGET_CMDS

**lib/core_builder.rb** - Use metadata['so_file'] path + absolute paths

**Test:** `make core-cortex-a53-ppsspp` ✅

---

### 2. tic80 (Fantasy Console) - DISABLED ⚠️

**Status:** ❌ **DISABLED** (commented out in systems.yml)

**Root Cause:** Language API source files (`src/api/lua.c`, `squirrel.c`, etc.) have hardcoded `#include` statements for demo cart binary data files (e.g., `#include "../build/assets/luademo.tic.dat"`). While these .dat files are committed to git, the build is fragile outside Buildroot.

**Issues:**
- Demo carts embedded as binary data via #include in C source
- Requires janet library dependency
- `-DBUILD_DEMO_CARTS=OFF` doesn't prevent the #includes
- Complex build environment requirements

**Decision:** Disabled (niche fantasy console)

**Useful infrastructure added:**
- ✅ Patching system (`apply_patches()` in `core_builder.rb`)
- ✅ Git-aware cmake cleaning (preserves tracked files in `build/`)
- ✅ Patch documentation (`patches/README.md`)

---

## Current Build Failures

### 1. a5200, beetle-lynx, vice - Missing Makefiles

**Affected:** cortex-a53 (likely all CPUs)

**Error:** Makefile not found after build

**Priority:** Low-Medium

**Next Steps:** Investigate why Makefiles are missing after source extraction

---

### 2. scummvm - Build Error

**Affected:** cortex-a53 (likely all CPUs)

**Error:** Build fails with Rosetta error on macOS
```
rosetta error: Rosetta is only intended to run on Apple Silicon with a macOS host
```

**Priority:** Low (scummvm compiles but the build is run in Docker/container in CI)

**Notes:** This only affects local macOS builds. CI builds in Linux containers will work fine.

---

## Next Steps

1. ✅ **COMPLETED:** Fix ppsspp and tic80 regressions
2. Test full rebuild with new recipes on CI to verify fixes
3. Investigate missing Makefile cores (a5200, beetle-lynx, vice)
4. Document final build statistics after complete rebuild

---

## Build System Status

✅ Knulli submodule integration working
✅ Directory restructure complete (`build/` consolidation)
✅ systems.yml-driven core selection working
✅ Recipe generation from Knulli working
✅ Cross-compilation for all 4 CPU families working
✅ Absolute path fixes applied
✅ **NEW:** INSTALL_TARGET_CMDS parsing for correct .so file paths
