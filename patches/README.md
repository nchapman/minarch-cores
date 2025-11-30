# Core Patches

This directory contains patches for libretro cores that need fixes or modifications for standalone builds outside of Buildroot.

## How Patching Works

Patches are automatically applied during the build process by `lib/core_builder.rb`:

1. Before building each core, the builder looks for patches in `patches/<corename>/`
2. All `*.patch` files are applied in alphabetical order using `git apply`
3. Patches are skipped if already applied (idempotent)

## Patch Format

Patches should be in unified diff format (`git diff` or `diff -u`), suitable for `git apply`:

```patch
--- a/path/to/file
+++ b/path/to/file
@@ -line,count +line,count @@
 context
-removed line
+added line
 context
```

## Current Patches

### gambatte (Game Boy / Game Boy Color)

**`01-export-dmg-grid-color-on-change.patch`**
- **Purpose:** Export DMG grid color to `/tmp/dmg_grid_color` when palette changes
- **Reason:** MinUI compatibility - allows MinUI frontend to read the current GB palette color for UI customization
- **Source:** Adapted from MinUI workspace/all/cores/patches/gambatte/001-export-dmg-grid-color-on-change.patch

### picodrive (Sega Genesis / Mega Drive / 32X)

**`fix-cyclone-cross-compile.patch`**
- **Purpose:** Fix Cyclone ARM assembly compilation for cross-compilation
- **Reason:** Ensures proper build when cross-compiling for ARM targets

## Creating New Patches

### For New Cores

1. Make changes in the core's source directory: `workspace/cores/libretro-<corename>/`
2. Create a patch using git:
   ```bash
   cd workspace/cores/libretro-<corename>
   git diff > /path/to/project/patches/<corename>/01-description.patch
   ```
3. Test that the patch applies cleanly:
   ```bash
   git apply --check patches/<corename>/01-description.patch
   ```
4. Commit the patch file to the project repository

### Patch Naming Convention

- Use numbered prefixes for ordering: `01-`, `02-`, etc.
- Use descriptive names: `01-skip-studio-for-libretro.patch`
- Keep patches focused on a single issue or change

## Best Practices

1. **Minimal Changes:** Keep patches as small as possible
2. **Documentation:** Document the purpose and reason for each patch
3. **Upstream:** Consider submitting patches upstream to the core's repository
4. **Testing:** Verify patches apply cleanly and fix the intended issue
5. **Idempotency:** Patches should be safe to apply multiple times

## Alternatives to Patching

Before creating a patch, consider:

1. **CMake Overrides:** Use `config/cmake-overrides.yml` for build options
2. **Environment Variables:** Set compiler flags or paths in configs
3. **Build Scripts:** Add pre/post-build steps if needed

Patches should be a last resort for issues that can't be solved through configuration.
