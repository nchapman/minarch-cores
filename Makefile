# minarch-cores - Build libretro cores using Knulli definitions
# CPU family-based builds for optimal performance

.PHONY: help list-cores recipes-% recipes-all build-% build-all core-% package-% package-all clean-% clean docker-build shell release

# Docker configuration
DOCKER_IMAGE := minarch-cores-builder
# Use native architecture (ARM64 on Apple Silicon, x86_64 elsewhere)
DOCKER_RUN := docker run --rm -v $(PWD):/workspace -w /workspace $(DOCKER_IMAGE)

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

# Build parallelism (default to number of CPU cores)
JOBS ?= $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

help:
	@echo "minarch-cores - ARM libretro core builder (MinUI-focused)"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. Generate recipes: make recipes-cortex-a53"
	@echo "  2. Build cores:      make build-cortex-a53"
	@echo "  3. Build all:        make build-all"
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
	@echo "Recipe Generation:"
	@echo "  make recipes-cortex-a53     Generate recipes for cortex-a53"
	@echo "  make recipes-all            Generate all CPU family recipes"
	@echo ""
	@echo "Packaging:"
	@echo "  make package-cortex-a53     Create cortex-a53.zip"
	@echo "  make package-all            Create all packages"
	@echo ""
	@echo "Utilities:"
	@echo "  make list-cores             List available cores (131 from Knulli)"
	@echo "  make clean                  Clean build outputs (keeps downloaded cores)"
	@echo "  make clean-artifacts        Clean .o/.a/.so from cores/ (keeps source code)"
	@echo "  make clean-cores            Delete cores/ directory (forces re-download)"
	@echo "  make clean-cortex-a53       Clean specific CPU family build"
	@echo "  make shell                  Open shell in build container"
	@echo "  make release                Create git flow release and trigger build"
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
	docker build -t $(DOCKER_IMAGE) .
	@echo "✓ Docker image ready"

# Generate recipes for a CPU family
.PHONY: recipes-%
recipes-%: docker-build
	@echo "=== Generating recipes for $* ==="
	@if [ ! -f config/$*.config ]; then \
		echo "ERROR: Config not found: config/$*.config"; \
		echo "Available configs: $(CPU_FAMILIES)"; \
		exit 1; \
	fi
	$(DOCKER_RUN) ruby scripts/generate-recipes $*
	@echo "✓ Recipes generated: recipes/linux/$*.json"

# Generate all recipes
.PHONY: recipes-all
recipes-all: $(addprefix recipes-,$(CPU_FAMILIES))

# Generic build target for any CPU family
.PHONY: build-%
build-%: docker-build
	@echo "=== Building cores for $* ==="
	@if [ ! -f config/$*.config ]; then \
		echo "ERROR: Config not found: config/$*.config"; \
		echo "Available configs: $(CPU_FAMILIES)"; \
		exit 1; \
	fi
	@if [ ! -f recipes/linux/$*.json ]; then \
		echo "ERROR: Recipe not found. Generate it first:"; \
		echo "  make recipes-$*"; \
		exit 1; \
	fi
	@CORE_COUNT=$$(jq 'length' recipes/linux/$*.json); \
	echo "Building $$CORE_COUNT cores for $*"
	@echo "This will take 1-3 hours..."
	@mkdir -p output/$* output/cores output/logs
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
	if [ ! -f recipes/linux/$$FAMILY.json ]; then \
		echo "ERROR: Recipe not found. Generate it first:"; \
		echo "  make recipes-$$FAMILY"; \
		exit 1; \
	fi; \
	mkdir -p output/$$FAMILY output/cores output/logs; \
	$(DOCKER_RUN) ruby scripts/build-one $$FAMILY $$CORE -j $(JOBS); \
	if [ -f output/$$FAMILY/$${CORE}_libretro.so ]; then \
		echo ""; \
		echo "✓ Built successfully: output/$$FAMILY/$${CORE}_libretro.so"; \
		ls -lh output/$$FAMILY/$${CORE}_libretro.so | awk '{print "  Size: " $$5}'; \
	else \
		echo ""; \
		echo "✗ Build failed"; \
		exit 1; \
	fi

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
	rm -f output/dist/linux-$*.zip
	@echo "✓ Cleaned $*"

# Clean build artifacts from cores (IMPORTANT: Run between CPU family builds!)
.PHONY: clean-artifacts
clean-artifacts:
	@echo "=== Cleaning build artifacts from cores directories ==="
	@echo "Removing .o files..."
	find output/cores -name "*.o" -type f -delete 2>/dev/null || true
	@echo "Removing .a files..."
	find output/cores -name "*.a" -type f -delete 2>/dev/null || true
	@echo "Removing .so files..."
	find output/cores -name "*.so" -type f -delete 2>/dev/null || true
	@echo "Removing .dylib files..."
	find output/cores -name "*.dylib" -type f -delete 2>/dev/null || true
	@echo "Removing build directories..."
	find output/cores -type d -name "build" -exec rm -rf {} + 2>/dev/null || true
	find output/cores -type d -name "obj" -exec rm -rf {} + 2>/dev/null || true
	@echo "✓ Cleaned $(shell find output/cores -name '*.o' -o -name '*.a' -o -name '*.so' 2>/dev/null | wc -l) artifact files"

# Clean downloaded core sources
.PHONY: clean-cores
clean-cores:
	@echo "=== Cleaning downloaded core sources ==="
	-rm -rf cores
	@echo "✓ Removed cores/ directory"
	@echo "Note: Core sources will be re-downloaded on next build"

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

# Create a git flow release
.PHONY: release
release:
	@./scripts/release
