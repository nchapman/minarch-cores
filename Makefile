# minarch-cores - Build libretro cores for ARM devices
# Architecture-based builds for optimal performance

.PHONY: help list-cores build-% build-all core-% package-% package-all clean-% clean docker-build shell release test update-recipes-% update-recipes-all update-core-%

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

# CPU families to build (architecture-based variants)
# Building 2 architectures:
#   - arm32: ARMv7VE with NEON-VFPv4 (All ARM32 devices)
#   - arm64: ARMv8-A with NEON (All ARM64 devices)
CPU_FAMILIES := arm32 arm64

# Build parallelism (default to 8 jobs for optimal build speed)
JOBS ?= 8

help:
	@echo "minarch-cores - ARM libretro core builder (MinUI-focused)"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. Build cores:      make build-arm64"
	@echo "  2. Build all:        make build-all"
	@echo ""
	@echo "Architectures:"
	@echo "  make build-arm32    ARMv7VE + NEON-VFPv4 (All ARM32 devices)"
	@echo "  make build-arm64    ARMv8-A + NEON (All ARM64 devices)"
	@echo "  make build-all      Build both architectures"
	@echo ""
	@echo "Device Compatibility:"
	@echo "  ARM32 devices → arm32   (Miyoo Mini/Plus/A30, RG35XX, Trimui Smart)"
	@echo "  ARM64 devices → arm64   (RG28xx/40xx, CubeXX, Trimui)"
	@echo ""
	@echo "Single Core Build (for testing/debugging):"
	@echo "  make core-arm64-gambatte   Build just gambatte for arm64"
	@echo "  make core-arm32-flycast    Build just flycast for arm32"
	@echo ""
	@echo "Packaging:"
	@echo "  make package-arm64    Create arm64.zip"
	@echo "  make package-all      Create all packages"
	@echo ""
	@echo "Utilities:"
	@echo "  make test                   Run RSpec test suite"
	@echo "  make list-cores             List available cores"
	@echo "  make clean              Clean all build outputs"
	@echo "  make clean-arm64        Clean specific architecture"
	@echo "  make clean-cores        Delete all cores source directories"
	@echo "  make clean-cache        Delete download cache"
	@echo "  make shell              Open shell in build container"
	@echo "  make release            Create git flow release and trigger build"
	@echo "  make release FORCE=1    Force recreate today's release"
	@echo ""
	@echo "Testing GitHub Actions Environment:"
	@echo "  make docker-build PLATFORM=amd64    Build x86_64 Docker image"
	@echo "  make build-arm32 PLATFORM=amd64     Test ARM32 cross-compile"
	@echo ""
	@echo "Recipe Management:"
	@echo "  make update-recipes-arm64               Update arm64 core commits"
	@echo "  make update-recipes-arm64 DRY=1         Check for updates (dry-run)"
	@echo "  make update-core-arm64-gambatte         Update specific core"
	@echo "  make update-core-arm64-gambatte DRY=1   Check specific core (dry-run)"
	@echo "  make update-recipes-all                 Update all architectures"

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
	@if [ ! -f recipes/linux/$*.yml ]; then \
		echo "ERROR: Recipe not found: recipes/linux/$*.yml"; \
		echo "Available recipes: $(CPU_FAMILIES)"; \
		exit 1; \
	fi
	@CORE_COUNT=$$(grep -c "^  [a-z]" recipes/linux/$*.yml | head -1); \
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
# Usage: make core-arm64-gambatte
.PHONY: core-%
core-%: docker-build
	@# Parse pattern: core-<family>-<corename>
	@# Handle family names (arm32, arm64)
	@FAMILY=$$(echo "$*" | sed -E 's/^(arm[0-9]+)-(.+)$$/\1/'); \
	CORE=$$(echo "$*" | sed -E 's/^(arm[0-9]+)-(.+)$$/\2/'); \
	echo "=== Building single core: $$CORE for $$FAMILY ==="; \
	if [ ! -f recipes/linux/$$FAMILY.yml ]; then \
		echo "ERROR: Recipe not found: recipes/linux/$$FAMILY.yml"; \
		echo "Available recipes: $(CPU_FAMILIES)"; \
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

# List cores in recipes
list-cores:
	@echo "=== arm32 cores ==="
	@grep -E "^  [a-z]" recipes/linux/arm32.yml | sed 's/://' | awk '{printf "  - %s\n", $$1}'
	@echo ""
	@echo "=== arm64 cores ==="
	@grep -E "^  [a-z]" recipes/linux/arm64.yml | sed 's/://' | awk '{printf "  - %s\n", $$1}'
	@echo ""
	@echo "Total: arm32=$$(grep -cE "^  [a-z]" recipes/linux/arm32.yml) cores, arm64=$$(grep -cE "^  [a-z]" recipes/linux/arm64.yml) cores"

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
	@echo "=== Updating recipes: $* ==="
	@if [ "$(DRY)" = "1" ]; then \
		./scripts/update-recipes $* --dry-run; \
	else \
		./scripts/update-recipes $*; \
	fi

# Update all recipe families
.PHONY: update-recipes-all
update-recipes-all:
	@echo "=== Updating all CPU families ==="
	@for family in $(CPU_FAMILIES); do \
		echo ""; \
		echo "--- $$family ---"; \
		if [ "$(DRY)" = "1" ]; then \
			./scripts/update-recipes $$family --dry-run; \
		else \
			./scripts/update-recipes $$family; \
		fi; \
	done

# Update specific core for specific architecture
.PHONY: update-core-%
update-core-%:
	@arch=$$(echo $* | cut -d- -f1); \
	core=$$(echo $* | cut -d- -f2-); \
	echo "=== Updating: $$arch / $$core ==="; \
	if [ "$(DRY)" = "1" ]; then \
		./scripts/update-recipes $$arch --core=$$core --dry-run; \
	else \
		./scripts/update-recipes $$arch --core=$$core; \
	fi
