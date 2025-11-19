# minarch-cores - Build libretro cores using Knulli definitions
# CPU family-based builds for optimal performance

.PHONY: help list-cores build-% build-all core-% package-% package-all clean-% clean docker-build shell release test update-recipes-% update-recipes-all

# Docker configuration
DOCKER_IMAGE := minarch-cores-builder
# Platform: Set PLATFORM=amd64 to force x86_64 (for testing GitHub Actions environment)
# Default: uses native architecture (ARM64 on Apple Silicon, x86_64 elsewhere)
ifdef PLATFORM
DOCKER_PLATFORM := --platform linux/$(PLATFORM)
else
DOCKER_PLATFORM :=
endif
DOCKER_RUN := docker run --rm $(DOCKER_PLATFORM) -v $(PWD):/workspace -w /workspace $(DOCKER_IMAGE)

# CPU families to build (all MinUI-compatible optimized variants)
# Building 4 CPU families for optimal per-device performance
# and minui build optimization:
#   - cortex-a7:  ARM32 devices (Miyoo Mini family)
#   - cortex-a53: ARM64 universal baseline
#   - cortex-a55: RK3566 optimized (Miyoo Flip, RGB30, RG353)
#   - cortex-a76: High-performance ARM64 (RG-406/556)
#
# Disabled:
#   - cortex-a35: RG-351 series (no MinUI support - runs Knulli/JelOS)
CPU_FAMILIES := cortex-a7 cortex-a53 cortex-a55 cortex-a76

# All available CPU families (including disabled)
ALL_CPU_FAMILIES := cortex-a7 cortex-a35 cortex-a53 cortex-a55 cortex-a76

# Build parallelism (default to 8 jobs for optimal build speed)
JOBS ?= 8

help:
	@echo "minarch-cores - ARM libretro core builder (MinUI-focused)"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. Build cores:      make build-cortex-a53"
	@echo "  2. Build all:        make build-all"
	@echo ""
	@echo "Active CPU Families (MinUI-compatible optimized variants):"
	@echo "  make build-cortex-a7        ARM32: Miyoo Mini family"
	@echo "  make build-cortex-a53       ARM64: Universal baseline"
	@echo "  make build-cortex-a55       ARM64: RK3566 optimized"
	@echo "  make build-cortex-a76       ARM64: High-performance"
	@echo "  make build-all              Build all 4 families"
	@echo ""
	@echo "Device Compatibility Guide:"
	@echo "  Miyoo Mini/Plus/A30         → cortex-a7"
	@echo "  RG28xx/35xx/40xx/CubeXX     → cortex-a53"
	@echo "  Miyoo Flip, RGB30, RG353    → cortex-a55"
	@echo "  RG406/556, Retroid Pocket   → cortex-a76"
	@echo ""
	@echo "Optional Builds (disabled):"
	@echo "  make build-cortex-a35       RG351 series (no MinUI support)"
	@echo ""
	@echo "Single Core Build (for testing/debugging):"
	@echo "  make core-cortex-a53-gambatte  Build just gambatte for cortex-a53"
	@echo "  make core-cortex-a53-flycast   Build just flycast for cortex-a53"
	@echo ""
	@echo "Packaging:"
	@echo "  make package-cortex-a53     Create cortex-a53.zip"
	@echo "  make package-all            Create all packages"
	@echo ""
	@echo "Utilities:"
	@echo "  make test                   Run RSpec test suite"
	@echo "  make list-cores             List available cores (131 from Knulli)"
	@echo "  make clean                  Clean all build outputs"
	@echo "  make clean-cortex-a53       Clean specific CPU family (built cores + sources)"
	@echo "  make clean-cores            Delete all cores-* source directories"
	@echo "  make clean-cache            Delete download cache (forces re-download)"
	@echo "  make shell                  Open shell in build container"
	@echo "  make release                Create git flow release and trigger build"
	@echo "  make release FORCE=1        Force recreate today's release (deletes existing)"
	@echo ""
	@echo "Testing GitHub Actions Environment:"
	@echo "  make docker-build PLATFORM=amd64    Build x86_64 Docker image"
	@echo "  make build-cortex-a7 PLATFORM=amd64 Test ARM32 cross-compile from x86_64"
	@echo ""
	@echo "Recipe Management:"
	@echo "  make update-recipes-cortex-a53      Check for core updates (dry-run)"
	@echo "  make update-recipes-cortex-a53 LIVE=1  Apply core updates"
	@echo "  make update-recipes-all             Check all families for updates"
	@echo "  make update-recipes-all LIVE=1      Update all families"
	@echo ""
	@echo "Device Guide:"
	@echo "  Anbernic RG28xx/35xx/40xx, Trimui → cortex-a53"
	@echo "  Miyoo Flip, RGB30, RG353          → cortex-a55"
	@echo "  Miyoo Mini series                 → cortex-a7"
	@echo "  RG351 series                      → cortex-a35"
	@echo "  Retroid Pocket 5                  → cortex-a76"

# Build Docker image
docker-build:
	@echo "=== Building Docker image ==="
	@if [ -n "$(DOCKER_PLATFORM)" ]; then \
		echo "Using platform: $(DOCKER_PLATFORM)"; \
	fi
	docker build $(DOCKER_PLATFORM) -t $(DOCKER_IMAGE) .
	@echo "✓ Docker image ready"

# Note: Recipes are now manually maintained YAML files in recipes/linux/
# No automatic generation - edit recipes/*.yml directly to add/update cores

# Generic build target for any CPU family
.PHONY: build-%
build-%: docker-build
	@echo "=== Building cores for $* ==="
	@if [ ! -f config/$*.config ]; then \
		echo "ERROR: Config not found: config/$*.config"; \
		echo "Available configs: $(CPU_FAMILIES)"; \
		exit 1; \
	fi
	@if [ ! -f recipes/linux/$*.yml ]; then \
		echo "ERROR: Recipe not found: recipes/linux/$*.yml"; \
		echo "Available recipes: $(CPU_FAMILIES)"; \
		exit 1; \
	fi
	@CORE_COUNT=$$(grep -c "^[a-z]" recipes/linux/$*.yml | head -1); \
	echo "Building cores for $*"
	@echo "This will take 1-3 hours..."
	@mkdir -p output/$* output/cores-$* output/cache output/logs
	$(DOCKER_RUN) ruby scripts/build-all $* -j $(JOBS) -l output/logs/$*-build.log
	@echo ""
	@echo "✓ Build complete for $*"
	@echo "  Cores built: $$(ls output/$*/*.so 2>/dev/null | wc -l)"
	@du -sh output/$* 2>/dev/null || true

# Build all CPU families
.PHONY: build-all
build-all: $(addprefix build-,$(CPU_FAMILIES))
	@echo ""
	@echo "=== Build Summary ==="
	@for family in $(CPU_FAMILIES); do \
		echo "  $$family: $$(ls output/$$family/*.so 2>/dev/null | wc -l) cores"; \
	done
	@echo ""
	@echo "Total size:"
	@du -sh output/* 2>/dev/null || true

# Build a single core (for testing/debugging)
# Usage: make core-cortex-a53-gambatte
.PHONY: core-%
core-%: docker-build
	@# Parse pattern: core-<family>-<corename>
	@FAMILY=$$(echo "$*" | cut -d- -f1,2); \
	CORE=$$(echo "$*" | cut -d- -f3-); \
	echo "=== Building single core: $$CORE for $$FAMILY ==="; \
	if [ ! -f config/$$FAMILY.config ]; then \
		echo "ERROR: Config not found: config/$$FAMILY.config"; \
		echo "Available configs: $(CPU_FAMILIES)"; \
		exit 1; \
	fi; \
	if [ ! -f recipes/linux/$$FAMILY.yml ]; then \
		echo "ERROR: Recipe not found: recipes/linux/$$FAMILY.yml"; \
		exit 1; \
	fi; \
	mkdir -p output/$$FAMILY output/cores-$$FAMILY output/cache output/logs; \
	$(DOCKER_RUN) ruby scripts/build-one $$FAMILY $$CORE -j $(JOBS)

# Generic package target
.PHONY: package-%
package-%:
	@if [ ! -d output/$* ] || [ -z "$$(ls output/$*/*.so 2>/dev/null)" ]; then \
		echo "ERROR: No cores built for $*. Run: make build-$*"; \
		exit 1; \
	fi
	@echo "=== Packaging $* cores ==="
	@mkdir -p output/dist
	@cd output/$* && zip -q ../dist/linux-$*.zip *.so
	@echo "✓ Created output/dist/linux-$*.zip ($$(ls -lh output/dist/linux-$*.zip | awk '{print $$5}'))"

# Package all families
.PHONY: package-all
package-all: $(addprefix package-,$(CPU_FAMILIES))
	@echo ""
	@echo "=== Packaging Summary ==="
	@ls -lh output/dist/*.zip 2>/dev/null | awk '{print "  " $$9 " - " $$5}'

# List available cores
list-cores:
	@echo "Available cores from Knulli (131 cores):"
	@find -L package/batocera/emulators/retroarch/libretro -name 'libretro-*.mk' 2>/dev/null | \
		sed 's|.*/libretro-||' | sed 's|/.*||' | sort | uniq | \
		awk '{printf "  - %s\n", $$0}' | head -20
	@echo "  ... (and 111 more)"
	@echo ""
	@echo "Total: $$(find -L package/batocera/emulators/retroarch/libretro -name 'libretro-*.mk' 2>/dev/null | wc -l | xargs) cores"

# Clean specific CPU family
.PHONY: clean-%
clean-%:
	@echo "=== Cleaning $* ==="
	rm -rf output/$*
	rm -rf output/cores-$*
	rm -f output/dist/linux-$*.zip
	@echo "✓ Cleaned $* (built cores and source files)"

# Clean downloaded core sources for all CPU families
.PHONY: clean-cores
clean-cores:
	@echo "=== Cleaning all CPU-specific core source directories ==="
	-rm -rf output/cores-*
	@echo "✓ Removed all cores-* directories"
	@echo "Note: Core sources will be re-downloaded on next build"

# Clean download cache
.PHONY: clean-cache
clean-cache:
	@echo "=== Cleaning download cache ==="
	-rm -rf output/cache
	@echo "✓ Removed cache directory"
	@echo "Note: Tarballs will be re-downloaded on next build"

# Clean everything
clean:
	@echo "=== Cleaning all ==="
	-rm -rf output
	@echo "✓ Cleaned"

# Open interactive shell in build container
shell: docker-build
	@echo "=== Opening shell in build container ==="
	@echo "Debian Buster (GCC 8.3.0, glibc 2.28)"
	@echo "Type 'exit' to return"
	@echo ""
	docker run --rm -it -v $(PWD):/output -w /output $(DOCKER_IMAGE) /bin/bash

# Run tests
.PHONY: test
test:
	@echo "=== Running RSpec Tests ==="
	@if ! command -v bundle >/dev/null 2>&1; then \
		echo "ERROR: bundler not found. Install with: gem install bundler"; \
		exit 1; \
	fi
	@bundle check >/dev/null 2>&1 || bundle install
	@bundle exec rspec

# Create a git flow release
.PHONY: release
release:
	@if [ "$(FORCE)" = "1" ]; then \
		./scripts/release --force; \
	else \
		./scripts/release; \
	fi

# Update recipe commit hashes to latest versions
.PHONY: update-recipes-%
update-recipes-%:
	@echo "=== Checking for updates: $* ==="
	@if [ "$(LIVE)" = "1" ]; then \
		./scripts/update-recipes $*; \
	else \
		./scripts/update-recipes $* --dry-run; \
	fi

# Update all recipe families
.PHONY: update-recipes-all
update-recipes-all:
	@echo "=== Checking all CPU families for updates ==="
	@for family in $(CPU_FAMILIES); do \
		echo ""; \
		echo "--- $$family ---"; \
		if [ "$(LIVE)" = "1" ]; then \
			./scripts/update-recipes $$family; \
		else \
			./scripts/update-recipes $$family --dry-run; \
		fi; \
	done
	@if [ "$(LIVE)" != "1" ]; then \
		echo ""; \
		echo "To apply updates, run: make update-recipes-all LIVE=1"; \
	fi
