
###################################################################################################
# Build OpenVino Runtime
###################################################################################################
FROM debian:11 as ov-build
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get -qq update && \
    apt-get install -y \
    git build-essential cmake ninja-build \
    python3 libpython3-dev python3-pip \
    python3-venv python3-enchant \
    pkg-config unzip automake libtool autoconf \
    ccache curl wget unzip lintian file gzip \
    patchelf shellcheck \
    libssl-dev ca-certificates \
    libjson-c5 nlohmann-json3-dev \
    libusb-1.0-0 libusb-1.0-0-dev \
    protobuf-compiler \
    git-lfs \
    libtbb-dev \
    libpugixml-dev \
    libudev1 \
    libtinfo5 \
    libboost-filesystem1.74.0 libboost-program-options1.74.0 libboost-regex-dev \
    libpng-dev \
    libopenblas-dev \
    libgstreamer1.0-0 gstreamer1.0-plugins-base \
    libva-dev libavcodec-dev libavformat-dev \
    libswscale-dev \
    libgtk2.0-dev libglib2.0-dev libpango1.0-dev libcairo2-dev

#  cmake 3.20 or higher is required to build OpenVINO
RUN current_cmake_ver=$(cmake --version | sed -ne 's/[^0-9]*\(\([0-9]\.\)\{0,4\}[0-9][^.]\).*/\1/p') && \
    required_cmake_ver=3.20.0 && \
    if [ ! "$(printf '%s\n' "$required_cmake_ver" "$current_cmake_ver" | sort -V | head -n1)" = "$required_cmake_ver" ]; then \
        installed_cmake_ver=3.23.2 && \
        wget "https://github.com/Kitware/CMake/releases/download/v${installed_cmake_ver}/cmake-${installed_cmake_ver}.tar.gz" && \
        tar xf cmake-${installed_cmake_ver}.tar.gz && \
        (cd cmake-${installed_cmake_ver} && ./bootstrap --parallel="$(nproc --all)" && make --jobs="$(nproc --all)" && make install) && \
        rm -rf cmake-${installed_cmake_ver} cmake-${installed_cmake_ver}.tar.gz; \
    fi


# Arm-Specific package needs
RUN if ! [ "${TARGETARCH}" = "amd64"]; then \
    apt-get install scons; \
    fi

# # # Get OpenVino Source
# RUN git clone --recurse-submodules --shallow-submodules --depth 1 --branch 2022.1.0 https://github.com/openvinotoolkit/openvino.git
# RUN pip3 install --upgrade setuptools wheel cython protobuf && \
#     pip3 install -r openvino/src/bindings/python/requirements.txt

# # # Configure and Build OpenVino
# RUN mkdir -p openvino/build && cd openvino/build && \
#     if [ "${TARGETARCH}" = "arm" ]; then \
#     export TCFILE="../cmake/arm.toolchain.cmake"; \
#     elif [ "${TARGETARCH}" = "arm64" ]; then \
#     export TCFILE="../cmake/arm64.toolchain.cmake"; \
#     elif [ "${TARGETARCH}" = "amd64" ]; then \
#     export TCFILE="" ;\
#     fi && \
#     cmake -GNinja \
#     -DCMAKE_BUILD_TYPE=Release \
#     -DCMAKE_TOOLCHAIN_FILE=${TCFILE} \
#     -DTHREADING=TBB\
#     -DENABLE_OPENCV=OFF \
#     -DENABLE_OV_ONNX_FRONTEND=OFF \
#     -DENABLE_OV_TF_FRONTEND=OFF \
#     -DENABLE_OV_PADDLE_FRONTEND=OFF \
#     -DENABLE_BEH_TESTS=OFF \
#     -DENABLE_FUNCTIONAL_TESTS=OFF \
#     -DENABLE_TESTS=OFF \
#     -DENABLE_SAMPLES=OFF \
#     -DENABLE_PYTHON=ON \
#     -DENABLE_WHEEL=ON \
#     .. && ninja -j $(nproc --ignore=1)


# ## Build ARM CPU Plugin
# # Get  Contrib Source for ARM Builds
# RUN if ! [ "${TARGETARCH}" = "amd64" ]; then \
#     cd / && \
#     git clone --recurse-submodules --single-branch --branch=2022.1 https://github.com/openvinotoolkit/openvino_contrib.git &&\
#     cd openvino_contrib/modules/arm_plugin && mkdir build && cd build && \
#     cmake -GNinja \
#     -DInferenceEngineDeveloperPackage_DIR=/openvino/build \
#     -DCMAKE_BUILD_TYPE=Release \
#     -DARM_COMPUTE_SCONS_JOBS=$(nproc --ignore=1) .. && \
#     ninja -j $(nproc --ignore=1); \
#     fi

# # # Install
# RUN mkdir /opt/openvino && cd /openvino/build && \
#     cmake --install /openvino/build --prefix /opt/openvino