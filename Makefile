# minarch-cores Makefile
# Builds libretro cores using official recipes via Docker

.PHONY: help build-arm7neonhf build-aarch64 build-arm7neonhf-patched build-aarch64-patched build-all build-all-patched apply-patches clean-patches package-arm7neonhf package-aarch64 package-arm7neonhf-patched package-aarch64-patched package-all clean shell

# Include configuration
include config.env

# Docker image name
DOCKER_IMAGE := minarch-cores-builder
DOCKER_RUN := docker run --rm -v $(PWD):/workspace $(DOCKER_IMAGE)

# Recipe paths
RECIPE_ARMV7 := libretro-super/recipes/linux/cores-linux-arm7neonhf
RECIPE_AARCH64 := recipes/linux/cores-linux-aarch64
RECIPE_ARMV7_PATCHED := recipes/linux/cores-linux-arm7neonhf-patched
RECIPE_AARCH64_PATCHED := recipes/linux/cores-linux-aarch64-patched

help:
	@echo "minarch-cores - Local Build System"
	@echo ""
	@echo "Clean Builds (unmodified cores via official recipes):"
	@echo "  make build-arm7neonhf         Build ~134 arm7neonhf cores"
	@echo "  make build-aarch64            Build ~137 aarch64 cores"
	@echo "  make build-all                Build both architectures"
	@echo ""
	@echo "Patched Builds (minarch customizations):"
	@echo "  make build-arm7neonhf-patched Build patched arm7neonhf cores"
	@echo "  make build-aarch64-patched    Build patched aarch64 cores"
	@echo "  make build-all-patched        Build all clean + patched"
	@echo ""
	@echo "Packaging (create distribution zips):"
	@echo "  make package-arm7neonhf         Create linux-arm7neonhf.zip"
	@echo "  make package-aarch64            Create linux-aarch64.zip"
	@echo "  make package-arm7neonhf-patched Create linux-arm7neonhf-patched.zip"
	@echo "  make package-aarch64-patched    Create linux-aarch64-patched.zip"
	@echo "  make package-all                Create all 4 zip files"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean                 Remove build artifacts"
	@echo "  make shell                 Open shell in build container"
	@echo ""
	@echo "Note: First build takes 1-3 hours (fetches + compiles 130+ cores)"

# Build Docker image (only needed once)
docker-build:
	@echo "=== Building Docker image (Debian Buster) ==="
	docker build -t $(DOCKER_IMAGE) .
	@echo "✓ Docker image ready"

# Apply patches to cores in PATCHED_CORES
apply-patches:
	@echo "=== Applying minarch patches ==="
	@for core in $(PATCHED_CORES); do \
		echo "  → Cleaning and patching $$core"; \
		cd libretro-super/libretro-$$core && git checkout . && git clean -fd && cd ../..; \
		patch_file=$$(ls patches/$$core-*.patch 2>/dev/null | head -1); \
		if [ -n "$$patch_file" ]; then \
			echo "    Applying $$patch_file"; \
			cd libretro-super/libretro-$$core && patch -p1 < ../../$$patch_file && cd ../..; \
		fi; \
	done
	@echo "✓ Patches applied"

# Clean patches from cores in PATCHED_CORES
clean-patches:
	@echo "=== Reverting patches ==="
	@for core in $(PATCHED_CORES); do \
		echo "  → Reverting $$core"; \
		cd libretro-super/libretro-$$core && git checkout . && git clean -fd && cd ../..; \
	done
	@echo "✓ Patches reverted"

# Build 32-bit ARM cores using official recipe
build-arm7neonhf: docker-build
	@echo "=== Building arm7neonhf cores via official recipe ==="
	@echo "Recipe: $(RECIPE_ARMV7) (134 YES cores)"
	@echo "This will take 1-3 hours depending on your system..."
	@mkdir -p build/arm7neonhf
	$(DOCKER_RUN) bash -c "cd libretro-super && \
		JOBS=$(JOBS) \
		FORCE=YES \
		./libretro-buildbot-recipe.sh $(RECIPE_ARMV7) arm7neonhf-build"
	@echo "  → Copying cores to build/arm7neonhf/"
	@cp libretro-super/dist/unix/*_libretro.so build/arm7neonhf/ 2>/dev/null || true
	@echo "✓ arm7neonhf cores built: $$(ls build/arm7neonhf/*.so 2>/dev/null | wc -l | xargs) cores"
	@du -sh build/arm7neonhf 2>/dev/null || true

# Build 64-bit ARM cores using official recipe
build-aarch64: docker-build
	@echo "=== Building aarch64 cores via official recipe ==="
	@echo "Recipe: $(RECIPE_AARCH64) (137 YES cores)"
	@echo "This will take 1-3 hours depending on your system..."
	@mkdir -p build/aarch64
	$(DOCKER_RUN) bash -c "cd libretro-super && \
		JOBS=$(JOBS) \
		FORCE=YES \
		./libretro-buildbot-recipe.sh $(RECIPE_AARCH64) aarch64-build"
	@echo "  → Copying cores to build/aarch64/"
	@cp libretro-super/dist/unix/*_libretro.so build/aarch64/ 2>/dev/null || true
	@echo "✓ aarch64 cores built: $$(ls build/aarch64/*.so 2>/dev/null | wc -l | xargs) cores"
	@du -sh build/aarch64 2>/dev/null || true

# Build 32-bit ARM patched cores
build-arm7neonhf-patched: docker-build apply-patches
	@echo "=== Building arm7neonhf patched cores ==="
	@echo "Recipe: $(RECIPE_ARMV7_PATCHED)"
	@echo "Patched cores: $(PATCHED_CORES)"
	@mkdir -p build/arm7neonhf-patched
	@rm -rf build/arm7neonhf-patched/*
	$(DOCKER_RUN) bash -c "cd libretro-super && \
		JOBS=$(JOBS) \
		FORCE=YES \
		./libretro-buildbot-recipe.sh ../$(RECIPE_ARMV7_PATCHED) arm7neonhf-patched"
	@echo "  → Copying patched cores to build/arm7neonhf-patched/"
	@cp libretro-super/dist/unix/*_libretro.so build/arm7neonhf-patched/ 2>/dev/null || true
	@echo "✓ arm7neonhf patched cores built: $$(ls build/arm7neonhf-patched/*.so 2>/dev/null | wc -l | xargs) cores"
	$(MAKE) clean-patches

# Build 64-bit ARM patched cores
build-aarch64-patched: docker-build apply-patches
	@echo "=== Building aarch64 patched cores ==="
	@echo "Recipe: $(RECIPE_AARCH64_PATCHED)"
	@echo "Patched cores: $(PATCHED_CORES)"
	@mkdir -p build/aarch64-patched
	@rm -rf build/aarch64-patched/*
	$(DOCKER_RUN) bash -c "cd libretro-super && \
		JOBS=$(JOBS) \
		FORCE=YES \
		./libretro-buildbot-recipe.sh ../$(RECIPE_AARCH64_PATCHED) aarch64-patched"
	@echo "  → Copying patched cores to build/aarch64-patched/"
	@cp libretro-super/dist/unix/*_libretro.so build/aarch64-patched/ 2>/dev/null || true
	@echo "✓ aarch64 patched cores built: $$(ls build/aarch64-patched/*.so 2>/dev/null | wc -l | xargs) cores"
	$(MAKE) clean-patches

# Build both architectures (clean only)
build-all: build-arm7neonhf build-aarch64
	@echo ""
	@echo "=== Build Summary ==="
	@echo "  arm7neonhf cores: $$(ls build/arm7neonhf/*.so 2>/dev/null | wc -l | xargs)"
	@echo "  aarch64 cores:    $$(ls build/aarch64/*.so 2>/dev/null | wc -l | xargs)"
	@echo ""
	@echo "Total size:"
	@du -sh build/arm7neonhf build/aarch64 2>/dev/null || true

# Build all: clean + patched for both architectures
build-all-patched: build-arm7neonhf build-aarch64 build-arm7neonhf-patched build-aarch64-patched
	@echo ""
	@echo "=== Complete Build Summary ==="
	@echo "Clean builds:"
	@echo "  arm7neonhf cores: $$(ls build/arm7neonhf/*.so 2>/dev/null | wc -l | xargs)"
	@echo "  aarch64 cores:    $$(ls build/aarch64/*.so 2>/dev/null | wc -l | xargs)"
	@echo ""
	@echo "Patched builds:"
	@echo "  arm7neonhf cores: $$(ls build/arm7neonhf-patched/*.so 2>/dev/null | wc -l | xargs)"
	@echo "  aarch64 cores:    $$(ls build/aarch64-patched/*.so 2>/dev/null | wc -l | xargs)"
	@echo ""
	@echo "Total size:"
	@du -sh build/* 2>/dev/null || true

# Package arm7neonhf cores into zip file
package-arm7neonhf: build-arm7neonhf
	@echo "=== Packaging arm7neonhf cores ==="
	@cd build/arm7neonhf && zip -q ../../linux-arm7neonhf.zip *.so
	@echo "✓ Created linux-arm7neonhf.zip ($$(ls -lh linux-arm7neonhf.zip | awk '{print $$5}'))"

# Package aarch64 cores into zip file
package-aarch64: build-aarch64
	@echo "=== Packaging aarch64 cores ==="
	@cd build/aarch64 && zip -q ../../linux-aarch64.zip *.so
	@echo "✓ Created linux-aarch64.zip ($$(ls -lh linux-aarch64.zip | awk '{print $$5}'))"

# Package arm7neonhf patched cores into zip file
package-arm7neonhf-patched: build-arm7neonhf-patched
	@echo "=== Packaging arm7neonhf patched cores ==="
	@cd build/arm7neonhf-patched && zip -q ../../linux-arm7neonhf-patched.zip *.so
	@echo "✓ Created linux-arm7neonhf-patched.zip ($$(ls -lh linux-arm7neonhf-patched.zip | awk '{print $$5}'))"

# Package aarch64 patched cores into zip file
package-aarch64-patched: build-aarch64-patched
	@echo "=== Packaging aarch64 patched cores ==="
	@cd build/aarch64-patched && zip -q ../../linux-aarch64-patched.zip *.so
	@echo "✓ Created linux-aarch64-patched.zip ($$(ls -lh linux-aarch64-patched.zip | awk '{print $$5}'))"

# Package all cores into zip files
package-all: package-arm7neonhf package-aarch64 package-arm7neonhf-patched package-aarch64-patched
	@echo ""
	@echo "=== Packaging Summary ==="
	@ls -lh *.zip 2>/dev/null | awk '{print "  " $$9 " - " $$5}'

# Clean build artifacts
clean:
	@echo "=== Cleaning ==="
	rm -rf build/
	rm -rf libretro-super/libretro-*/
	rm -rf libretro-super/dist/
	rm -f *.zip
	@echo "✓ Cleaned"

# Open interactive shell in build container (for debugging)
shell: docker-build
	@echo "=== Opening shell in build container ==="
	@echo "Debian Buster (GCC 8.3.0, glibc 2.28)"
	@echo "Cores directory: /workspace/libretro-super"
	@echo "Type 'exit' to return"
	@echo ""
	docker run --rm -it -v $(PWD):/workspace $(DOCKER_IMAGE) /bin/bash
