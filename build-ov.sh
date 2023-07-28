#!/usr/bin/env bash

echo "Building OpenVino for $TARGETARCH"
cd /work


if [ $TARGETARCH = "arm64" ]; then
    mkdir -p python-pkgs && cd python-pkgs
    apt-get download python3.9-minimal:arm64 libpython3.9-minimal:arm64 python3.9-dev:arm64 libpython3.9-dev:arm64
    cd ..
    mkdir -p python-arm64
    find python-pkgs -type f -name "*.deb" -print0  | xargs -0 -I {} dpkg -x "{}" ./python-arm64;
fi

if ! [ -d "openvino" ]; then
    git clone --recurse-submodules --shallow-submodules --depth 1 --branch 2022.3.1 https://github.com/openvinotoolkit/openvino.git
    cd openvino 
    git apply /patches/vpu-wheel.patch
    git apply /patches/numpy-version.patch
    cd thirdparty/open_model_zoo
    git apply /patches/omz-tf2.patch
    cd ../../..;
fi

if ! [ $TARGETARCH = "amd64" ] && ! [ -d openvino_contrib ]; then
    git clone --recurse-submodules --single-branch --branch=master https://github.com/openvinotoolkit/openvino_contrib.git;
fi

python3.9 -m pip install --upgrade setuptools wheel cython protobuf auditwheel crossenv

cd openvino

# Setup Python Crossenv for cross-compiling wheel
python3.9 -m pip install -r src/bindings/python/src/compatibility/openvino/requirements-dev.txt

if [ $TARGETARCH = "amd64" ]; then
    chmod +x install_build_dependencies.sh && ./install_build_dependencies.sh;
fi


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
    ..
    ninja -j $(nproc --ignore=1)
    cp /work/openvino/build/wheels/* /output/;
elif [ $TARGETARCH = "arm64" ]; then
    # Build OV Libraries
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
    -DPYTHON_LIBRARY=/usr/lib/aarch64-linux-gnu/libpython3.9.so \
    -DPYTHON_INCLUDE_DIR=/usr/include/python3.9 \
    -DENABLE_WHEEL=ON \
    .. && ninja -j $(nproc --ignore=1)

    # Build Python Wheel
    cd .. && mkdir -p pybuild && cd pybuild 
    /usr/bin/python3.9 -m crossenv /work/python-arm64/usr/bin/python3.9 venv && \
    source venv/bin/activate && \
    build-pip install --upgrade pip && \
    build-pip install --upgrade setuptools wheel cython protobuf && \
    build-pip install -r ../src/bindings/python/src/compatibility/openvino/requirements-dev.txt
    pip install --upgrade pip
    pip install --upgrade setuptools wheel cython protobuf numpy==1.20
    pip install -r ../src/bindings/python/src/compatibility/openvino/requirements.txt

    cp -a ../licensing ../src/bindings/python/licensing

    cmake -GNinja \
      -DInferenceEngineDeveloperPackage_DIR=/work/openvino/build \
      -DCMAKE_BUILD_TYPE=Release \
      -DIE_EXTRA_MODULES=/work/openvino_contrib/modules/arm_plugin \
      -DTHREADING=TBB\
      -DENABLE_BEH_TESTS=OFF \
      -DENABLE_FUNCTIONAL_TESTS=OFF \
      -DENABLE_TESTS=OFF \
      -DENABLE_SAMPLES=OFF \
      -DENABLE_TEMPLATE=OFF \
      -DENABLE_PYTHON=ON -DPYTHON_EXECUTABLE=`which cross-python` \
      -DENABLE_WHEEL=ON \
      -DPYTHON_INCLUDE_DIRS=/work/python-arm64/usr/include/python3.9 \
      -DPYTHON_LIBRARIES=/work-arm64/python-arm64/lib/python3.9 \
      -DPYTHON_LIBRARY=/usr/lib/aarch64-linux-gnu/libpython3.9.so \
      -DPYTHON_MODULE_EXTENSION=".so" \
      -DPYBIND11_FINDPYTHON=OFF \
      -DPYBIND11_NOPYTHON=OFF \
      -DPYTHONLIBS_FOUND=TRUE \
      -DENABLE_DATA=OFF \
      -DCMAKE_TOOLCHAIN_FILE="/work/openvino/cmake/arm64.toolchain.cmake" \
      ../src/bindings/python
      ninja -j $(nproc --ignore=1)
      cp /work/openvino/pybuild/wheels/* /output/;
fi