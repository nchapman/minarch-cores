# Adding New Cores

This guide shows how to add a new core to minarch-cores. The process is straightforward with our explicit recipe system.

## Quick Process (3 Steps)

### 1. Find the Core Commit

```bash
# Get latest commit from the core's repo
git ls-remote --heads https://github.com/libretro/libretro-atari800.git | grep master

# Output:
# 6a18cb23cc4a7cecabd9b16143d2d7332ae8d44b	refs/heads/master
```

Or check the core's GitHub releases/tags for stable versions.

### 2. Add to Recipe (Alphabetically)

Edit `recipes/linux/arm64.yml` and add under the `cores:` section:

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

**Required fields:**
- `repo` - GitHub org/repo path
- `commit` - Git SHA or tag
- `build_type` - `make` or `cmake`
- For `make`: `makefile`, `build_dir`, `platform`, `so_file`
- For `cmake`: `cmake_opts`, `so_file`

**Optional fields:**
- `submodules: true` - If repo needs submodules
- `extra_args: [...]` - Additional make arguments
- `clean_extra: "rm -f path/file.o"` - Extra clean commands if needed

### 3. Test Build

```bash
# Test on one architecture first
make core-arm64-atari800

# If successful, copy to arm32.yml and test
make core-arm32-atari800
```

## Helper Script: inspect-core

Use the helper script to inspect a core's build configuration:

```bash
./scripts/inspect-core libretro/libretro-atari800 6a18cb23cc4a7cecabd9b16143d2d7332ae8d44b
```

This will:
- Download the core
- List available Makefiles
- Detect CMake builds
- Show build directories
- Suggest a recipe entry

## Finding the Right Settings

### Which Makefile?

**Prefer Makefile.libretro if it exists** (standard libretro convention):

```bash
# Check available makefiles
ls output/cores/libretro-atari800/Makefile*

# If both exist:
# - Makefile.libretro ← Use this (preferred)
# - Makefile ← Fallback
```

### Finding the .so Output

After a successful build:

```bash
# Find the actual .so file
find output/cores/libretro-atari800 -name "*_libretro.so"

# Use the exact path in recipe (relative to core root)
# Example: atari800_libretro.so
# Example: platform/libretro/fake08_libretro.so
# Example: src/burner/libretro/fbneo_libretro.so
```

### Special Cases

**Non-root build directory:**
```yaml
fake08:
  build_dir: platform/libretro  # Not "."
  so_file: platform/libretro/fake08_libretro.so
```

**Needs submodules:**
```yaml
picodrive:
  submodules: true
```

**Needs extra make args:**
```yaml
snes9x2005:
  extra_args:
    - USE_BLARGG_APU=1
```

**CMake build:**
```yaml
flycast:
  build_type: cmake
  so_file: build/flycast_libretro.so
  submodules: true
  cmake_opts:
    - -DCMAKE_BUILD_TYPE=Release
    - -DLIBRETRO=ON
```

**Custom clean (for broken make clean targets):**
```yaml
snes9x2005:
  clean_extra: "rm -f source/apu_blargg.o"  # Makefile clean misses this
```

## Real Example: Adding atari800

**Step 1: Find commit**
```bash
git ls-remote --heads https://github.com/libretro/libretro-atari800.git | grep master
# Result: 6a18cb23cc4a7cecabd9b16143d2d7332ae8d44b
```

**Step 2: Add to recipe** (alphabetically after a5200)
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

**Step 3: Test**
```bash
make core-arm64-atari800
# ✓ atari800_libretro.so
# Built successfully!
```

**Step 4: Add to arm32**
- Copy the same entry to arm32.yml
- Test it

## Common Patterns

**Standard libretro core (most common):**
```yaml
corename:
  repo: libretro/libretro-corename
  commit: <sha>
  build_type: make
  makefile: Makefile.libretro
  build_dir: "."
  platform: unix
  so_file: corename_libretro.so
```

**Beetle/Mednafen cores (use mednafen_ prefix):**
```yaml
beetle-lynx:
  repo: libretro/beetle-lynx-libretro
  # ...
  so_file: mednafen_lynx_libretro.so  # Not beetle-lynx_libretro.so!
```

**Upstream project cores (not libretro fork):**
```yaml
stella:
  repo: stella-emu/stella  # Not libretro/stella
  # ...
  build_dir: src/os/libretro  # Nested build location
  so_file: src/os/libretro/stella_libretro.so
```

## Verification Checklist

After adding a new core:

- [ ] Builds successfully on all architectures
- [ ] Uses Makefile.libretro if available
- [ ] Uses actual .so output name (no renaming)
- [ ] Alphabetically sorted in recipe under `cores:` section
- [ ] All required fields present
- [ ] Added to both architecture recipes (arm32, arm64)

## Tips

- **Copy from similar core** - Most cores follow the same pattern
- **Test incrementally** - Build for one architecture first
- **Check actual output** - Don't guess the .so filename
- **Use official repos** - Prefer upstream over forks when possible
- **Keep it simple** - Only add fields that are needed
- **YAML format** - Remember to add cores under the `cores:` section

That's it! With explicit YAML recipes, adding cores is straightforward and error-free.
