# TODO: Build 35 Systems with Knulli-Derived Cores

**Current Status:** Configuration complete, ready for build testing
**New Approach:** Systems-first (35 systems) → Best cores per CPU family
**Target:** 26 cores building for cortex-a53 (100% of configured systems)

## What We Just Did

✅ Created `config/systems.yml` - 35 systems with Knulli-validated core choices
✅ Generated CPU-specific core lists (26 cores for cortex-a53)
✅ Added missing MinUI systems (SGB, Virtual Boy, NGP, Pokemini)
✅ Switched to `flycast-xtreme` (Makefile build, Knulli's H700 choice)
✅ Fixed Dockerfile (CMake 3.20, liblcf, platform support)
✅ Added `CMAKE_SYSTEM_PROCESSOR` for cross-compilation
✅ Documented methodology in `CORE_SELECTION.md`

## Next Steps

### 1. Test New Core List (30 minutes) ⭐

**Goal:** Verify our 26 cores build successfully

**Already known to work (from previous testing):**
- ✅ ppsspp (31 MB) - CMake 3.20 fix working
- ✅ fake08 - Submodules working
- ✅ mrboom - Submodules working (not in our list, but tested)
- ✅ freechaf - Submodules working (not in our list, but tested)

**New cores to test:**
- ⭐ **flycast-xtreme** - KEY TEST: Makefile build should avoid GCC bug
- ⭐ **race** - Neo Geo Pocket (new from MinUI)
- ⭐ **beetle-vb** - Virtual Boy (new from MinUI)
- ⭐ **pokemini** - Pokémon mini (new from MinUI)
- ⭐ **stella2014** - Lighter Atari 2600 for cortex-a7
- ⭐ **pocketsnes** - ARM-optimized SNES for cortex-a7

**Test commands:**
```bash
# Priority 1: Test flycast-xtreme (our Dreamcast solution)
make core-cortex-a53-flycast-xtreme

# Priority 2: Test new MinUI cores
make core-cortex-a53-race
make core-cortex-a53-beetle-vb
make core-cortex-a53-pokemini

# Priority 3: Test cortex-a7 specific cores
make core-cortex-a7-pocketsnes
make core-cortex-a7-stella2014
make core-cortex-a7-gpsp
```

**Expected Results:**
- flycast-xtreme builds without GCC ICE (Makefile vs CMake!)
- All MinUI cores build (they're proven on real hardware)
- cortex-a7 cores build (Knulli BCM2835 tested)

---

### 2. Generate Recipes with New Core Lists (5 minutes)

**Update:** Our recipe generator already reads from `config/cores-{cpu}.list`

**Action:**
```bash
# Regenerate recipes for all CPU families
make recipes-cortex-a53
make recipes-cortex-a7
make recipes-cortex-a35
make recipes-cortex-a55
make recipes-cortex-a76
```

**Expected:**
- cortex-a53: 26 cores in recipe
- cortex-a7: 25 cores in recipe (PSP excluded)
- Should see flycast-xtreme instead of flycast

**Verify:**
```bash
jq 'keys | length' recipes/linux/cortex-a53.json
jq '.["flycast-xtreme"]' recipes/linux/cortex-a53.json
jq 'has("flycast")' recipes/linux/cortex-a53.json  # Should be false
```

---

### 3. Full Build Test - cortex-a53 (1-2 hours)

**Goal:** Build all 26 cores for cortex-a53

**Prep:**
```bash
# Clean to ensure fresh build
rm -rf cores build/cortex-a53

# Regenerate recipes
make recipes-cortex-a53
```

**Build:**
```bash
# Full build with logging
make build-cortex-a53 2>&1 | tee logs/cortex-a53-systems-build.log
```

**Check results:**
```bash
ls build/cortex-a53/*.so | wc -l  # Target: 26/26
ls -lh build/cortex-a53/*.so
```

**Success Criteria:**
- 26/26 cores built (100%)
- flycast-xtreme builds successfully
- ppsspp builds successfully
- All MinUI cores present

---

### 4. Document Build Results (10 minutes)

**Create:** `SYSTEMS_BUILD_STATUS.md`

Document for each system:
- ✅/❌ Build status
- Core used
- File size
- Any issues or notes

**Example:**
```markdown
| System      | Core            | Status | Size   | Notes                    |
|-------------|-----------------|--------|--------|--------------------------|
| dreamcast   | flycast-xtreme  | ✅     | 8.5 MB | Makefile build successful|
| psp         | ppsspp          | ✅     | 31 MB  | CMake 3.20 working       |
| virtualboy  | beetle-vb       | ✅     | 2.1 MB | MinUI core               |
```

---

## Known Issues from Previous Build

### Fixed ✅
- ✅ **ppsspp** - CMake 3.20 installed, CMAKE_SYSTEM_PROCESSOR added
- ✅ **fake08** - Submodules working after re-fetch
- ✅ **Docker platform** - Added `--platform linux/amd64` for ARM Mac

### Likely Fixed ✅
- ✅ **flycast** → **flycast-xtreme** - Makefile build should avoid GCC bug
- ✅ **Submodules** - freechaf/mrboom confirmed working after re-fetch

### Potentially Still Broken ❌
- ❓ **easyrpg** - Not in our system list (removed)
- ❓ Cores we haven't tested yet with new configuration

---

## Post-Build: Quality Checks

Once build completes, verify:

### Coverage Check
```bash
# Should show 26 cores
ls build/cortex-a53/*.so | wc -l

# Verify key systems
ls build/cortex-a53/flycast-xtreme_libretro.so  # Dreamcast
ls build/cortex-a53/ppsspp_libretro.so          # PSP
ls build/cortex-a53/race_libretro.so            # Neo Geo Pocket
ls build/cortex-a53/beetle-vb_libretro.so       # Virtual Boy
```

### MinUI Coverage
```bash
# Verify all 13 MinUI cores built
for core in fceumm gambatte gpsp mgba snes9x picodrive pcsx beetle-pce-fast beetle-vb pokemini race fake08; do
  if [ -f "build/cortex-a53/${core}_libretro.so" ]; then
    echo "✅ $core"
  else
    echo "❌ $core MISSING"
  fi
done
```

### Size Check
```bash
# Total size should be reasonable
du -sh build/cortex-a53
# Expected: ~200-300 MB for 26 cores
```

---

## Success Metrics

**Target Goals:**
- ✅ 26/26 cores building for cortex-a53 (100%)
- ✅ 25/25 cores building for cortex-a7 (100%)
- ✅ 100% MinUI system coverage
- ✅ flycast-xtreme builds (Dreamcast working)
- ✅ ppsspp builds (PSP working)

**If we hit these targets:**
- We have a **production-ready core set**
- All systems based on **proven configurations**
- CPU-optimized for each device tier
- Full traceability via systems.yml

---

## Quick Reference

### Current Configuration Files
- `config/systems.yml` - Master configuration (35 systems)
- `config/cores-cortex-a53.list` - Generated core list (26 cores)
- `config/cores-cortex-a7.list` - Generated core list (25 cores)

### Build Commands
```bash
# Test single core
make core-cortex-a53-flycast-xtreme

# Test full build
make build-cortex-a53

# Generate recipes
make recipes-cortex-a53
```

### Key Files Modified
- `Dockerfile` - CMake 3.20, liblcf, platform support
- `Makefile` - Platform flags for ARM Mac
- `lib/core_builder.rb` - CMAKE_SYSTEM_PROCESSOR, flycast workarounds
- `scripts/generate-cores-from-systems` - Auto-generate lists from systems.yml

---

## Philosophy

**Old approach:** Build all 131 Knulli cores, see what sticks
**New approach:** Define 35 systems, pick best core per CPU family

**Benefits:**
- Clear purpose (system coverage, not core count)
- Knulli-validated choices
- CPU-appropriate optimization
- MinUI compatibility
- Maintainable and documented

Let's build! 🚀
