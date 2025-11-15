# Docker image for building libretro cores
# Uses Debian Buster (GCC 8.3.0, glibc 2.28) for maximum device compatibility
# This is the DEFAULT/ACTIVE Dockerfile
FROM debian:buster

ENV DEBIAN_FRONTEND=noninteractive

# Fix archived Debian repositories (Buster is archived)
RUN echo "deb http://archive.debian.org/debian buster main contrib non-free" > /etc/apt/sources.list && \
    echo "deb http://archive.debian.org/debian-security buster/updates main" >> /etc/apt/sources.list && \
    echo "Acquire::Check-Valid-Until false;" > /etc/apt/apt.conf.d/99no-check-valid-until

# Enable multiarch for ARM libraries
RUN dpkg --add-architecture armhf && \
    dpkg --add-architecture arm64

# Install build tools and libretro core dependencies
# Better to include extras than miss something a core needs
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
	build-essential \
	git \
	wget \
	curl \
	unzip \
	zip \
	make \
	cmake \
	ninja-build \
	nasm \
	yasm \
	patch \
	perl \
	pkg-config \
	python \
	python3 \
	python3-pip \
	ruby \
	ruby-dev \
	ccache \
	autoconf \
	automake \
	libtool \
	jq \
	zlib1g-dev \
	zlib1g-dev:armhf \
	zlib1g-dev:arm64 \
	libpng-dev \
	liblzma-dev \
	libssl-dev \
	libglib2.0-dev \
	libx11-dev \
	mesa-common-dev \
	libglu1-mesa-dev \
	libgl1-mesa-dev \
	libgles2-mesa-dev \
	libasound2-dev \
	gcc-arm-linux-gnueabihf \
	g++-arm-linux-gnueabihf \
	gcc-aarch64-linux-gnu \
	g++-aarch64-linux-gnu \
	libgl1-mesa-dev:armhf \
	libgl1-mesa-dev:arm64 \
	libexpat1-dev \
	libicu-dev \
	libsdl2-dev \
	libsdl2-ttf-dev \
	libavcodec-dev \
	libavdevice-dev \
	libavfilter-dev \
	libavformat-dev \
	libavutil-dev \
	libswresample-dev \
	libswscale-dev \
	libpostproc-dev \
	&& rm -rf /var/lib/apt/lists/*

# Build liblcf from source (needed for easyrpg, uses system cmake 3.13)
RUN cd /tmp && \
    git clone https://github.com/EasyRPG/liblcf.git && \
    cd liblcf && \
    git checkout 0.8 && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr && \
    make -j4 && \
    make install && \
    cd / && rm -rf /tmp/liblcf

# Upgrade CMake to 3.20+ (Debian Buster has 3.13.4, but ppsspp needs 3.16+)
# Detect host architecture and download the appropriate CMake binary
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        CMAKE_ARCH="x86_64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        CMAKE_ARCH="aarch64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    echo "Installing CMake for $CMAKE_ARCH" && \
    wget https://github.com/Kitware/CMake/releases/download/v3.20.0/cmake-3.20.0-linux-${CMAKE_ARCH}.tar.gz && \
    tar -xzf cmake-3.20.0-linux-${CMAKE_ARCH}.tar.gz -C /opt && \
    ln -sf /opt/cmake-3.20.0-linux-${CMAKE_ARCH}/bin/cmake /usr/local/bin/cmake && \
    ln -sf /opt/cmake-3.20.0-linux-${CMAKE_ARCH}/bin/ctest /usr/local/bin/ctest && \
    ln -sf /opt/cmake-3.20.0-linux-${CMAKE_ARCH}/bin/cpack /usr/local/bin/cpack && \
    rm cmake-3.20.0-linux-${CMAKE_ARCH}.tar.gz

# Verify build environment
RUN echo "=== Build Environment ===" && \
    uname -m && \
    gcc --version | head -1 && \
    cmake --version | head -1 && \
    ruby --version && \
    echo "" && \
    echo "=== ARM Cross-Compilers ===" && \
    arm-linux-gnueabihf-gcc --version | head -1 && \
    aarch64-linux-gnu-gcc --version | head -1

WORKDIR /workspace

# Clear any problematic bash configs
RUN rm -f /etc/bash.bashrc /root/.bashrc /etc/profile.d/* || true

# Configure git to avoid credential issues with public repos
RUN git config --global credential.helper "" && \
    git config --global http.postBuffer 524288000 && \
    git config --global core.compression 0

CMD ["/bin/bash"]
