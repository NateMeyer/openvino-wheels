#!/usr/bin/env bash

echo "Building OpenVino for $TARGETARCH"
cd /work

git clone --recurse-submodules --shallow-submodules --depth 1 --branch 2022.2.0 https://github.com/openvinotoolkit/openvino.git

if ! [ $TARGETARCH = "amd64" ]; then
    git clone --recurse-submodules --single-branch --branch=master https://github.com/openvinotoolkit/openvino_contrib.git;
fi

python3.9 -m pip install --upgrade setuptools wheel cython protobuf auditwheel
python3.9 -m pip install -r openvino/src/bindings/python/src/compatibility/openvino/requirements-dev.txt

cd openvino

if [ $TARGETARCH = "amd64" ]; then
    chmod +x install_build_dependencies.sh && ./install_build_dependencies.sh;
fi

git apply /patches/vpu-wheel.patch

mkdir -p build && cd build

if [ $TARGETARCH = "amd64" ]; then
    cmake -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DTHREADING=TBB\
    -DENABLE_BEH_TESTS=OFF \
    -DENABLE_FUNCTIONAL_TESTS=OFF \
    -DENABLE_TESTS=OFF \
    -DENABLE_SAMPLES=OFF \
    -DENABLE_TEMPLATE=OFF \
    -DENABLE_PYTHON=ON \
    -DPYTHON_EXECUTABLE=`which python3.9` \
    -DPYTHON_LIBRARY=/usr/lib/x86_64-linux-gnu/libpython3.9.so \
    -DPYTHON_INCLUDE_DIR=/usr/include/python3.9 \
    -DENABLE_WHEEL=ON \
    ..;
elif [ $TARGETARCH = "arm64" ]; then
    cmake -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE=../cmake/arm64.toolchain.cmake \
    -DIE_EXTRA_MODULES=/work/openvino_contrib/modules/arm_plugin \
    -DTHREADING=TBB\
    -DENABLE_BEH_TESTS=OFF \
    -DENABLE_FUNCTIONAL_TESTS=OFF \
    -DENABLE_TESTS=OFF \
    -DENABLE_SAMPLES=OFF \
    -DENABLE_TEMPLATE=OFF \
    -DENABLE_PYTHON=ON \
    -DPYTHON_EXECUTABLE=`which python3.9` \
    -DPYTHON_LIBRARY=/usr/lib/aarch64-linux-gnu/libpython3.9.so \
    -DPYTHON_INCLUDE_DIR=/usr/include/python3.9 \
    -DENABLE_WHEEL=ON \
    ..;
fi

echo Configured $TARGETARCH
ninja -j $(nproc --ignore=1)

cp /work/openvino/build/wheels/* /output/