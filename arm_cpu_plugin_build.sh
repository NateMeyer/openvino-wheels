#!/bin/sh

set -eux

BUILD_JOBS=${BUILD_JOBS:-$(nproc)}
BUILD_TYPE=${BUILD_TYPE:-Release}
UPDATE_SOURCES=${UPDATE_SOURCES:-clean}
WITH_OPENCV=${WITH_OPENCV:-ON}
WITH_OMZ_DEMO=${WITH_OMZ_DEMO:-OFF}

DEV_HOME="$(pwd)"
ONETBB_HOME="$DEV_HOME/oneTBB"
OPENCV_HOME="$DEV_HOME/opencv"
OPENVINO_HOME="$DEV_HOME/openvino"
OPENVINO_CONTRIB="$DEV_HOME/openvino_contrib"
ARM_PLUGIN_HOME="$OPENVINO_CONTRIB/modules/arm_plugin"
OMZ_HOME="$DEV_HOME/open_model_zoo"
STAGING_DIR="$DEV_HOME/armcpu_package"

ONETBB_BUILD="$DEV_HOME/oneTBB/build"
OPENCV_BUILD="$DEV_HOME/opencv/build"
OPENVINO_BUILD="$DEV_HOME/openvino/build"
OMZ_BUILD="$DEV_HOME/open_model_zoo/build"

OV_PATCH_DIR=/patches


# Variables needed by build scripts
export BUILD_PYTHON=$DEV_HOME/host_python
export INSTALL_PYTHON=$DEV_HOME/target_python
export NUM_PROC=$(nproc)


fail()
{
    if [ $# -lt 2 ]; then
      echo "Script internal error"
      exit 31
    fi
    retval=$1
    shift
    echo "$@"
    exit "$retval"
}

cloneSrcTree()
{
    DESTDIR=$1
    shift
    SRCURL=$1
    shift
    while [ $# -gt 0 ]; do
        git clone --recurse-submodules --shallow-submodules --depth 1 --branch="$1" "$SRCURL" "$DESTDIR" && return 0
        shift
    done
    return 1
}

checkSrcTree()
{
    [ $# -lt 3 ] && fail

    if ! [ -d "$1" ]; then
        echo "Unable to detect $1"
        echo "Cloning $2..."
        cloneSrcTree "$@" || fail 3 "Failed to clone $2. Stopping"
    else
        echo "Detected $1"
        echo "Considering it as source directory"
        if [ "$UPDATE_SOURCES" = "reload" ]; then
            echo "Source reloading requested"
            echo "Removing existing sources..."
            rm -rf "$1" || fail 1 "Failed to remove. Stopping"
            echo "Cloning $2..."
            cloneSrcTree "$@" || fail 3 "Failed to clone $2. Stopping"
        elif [ -d "$1/build" ]; then
            echo "Build directory detected at $1"
            if [ "$UPDATE_SOURCES" = "clean" ]; then
                echo "Cleanup of previous build requested"
                echo "Removing previous build results..."
                rm -rf "$1/build" || fail 2 "Failed to cleanup. Stopping"
            fi
        fi
    fi
    return 0
}

# Prepare sources
if ! [ -d $OPENVINO_HOME ] || [ "$UPDATE_SOURCES" = "reload" ]; then
    NEED_PATCH=true;
else
    NEED_PATCH=false;
fi

checkSrcTree "$ONETBB_HOME" https://github.com/oneapi-src/oneTBB.git master
if [ "$WITH_OPENCV" = "ON" ]; then
    checkSrcTree "$OPENCV_HOME" https://github.com/opencv/opencv.git 4.x
fi
checkSrcTree "$OPENVINO_HOME" https://github.com/openvinotoolkit/openvino.git 2022.3.1
checkSrcTree "$OPENVINO_CONTRIB" https://github.com/openvinotoolkit/openvino_contrib.git releases/2022/3
if [ "$WITH_OMZ_DEMO" = "ON" ]; then
    checkSrcTree "$OMZ_HOME" https://github.com/openvinotoolkit/open_model_zoo.git releases/2022/3
fi

# Apply Openvino patches
if [ $NEED_PATCH = true ]; then
    patch -p 1 -d $OPENVINO_HOME -i /patches/vpu-wheel.patch
    patch -p 1 -d $OPENVINO_HOME -i /patches/numpy-version.patch
    patch -p 1 -d $OPENVINO_HOME/thirdparty/open_model_zoo -i /patches/omz-tf2.patch
fi

# python variables
python_executable="$(which python3)"
python_min_ver=$($python_executable -c "import sys; print(str(sys.version_info[1]))")
python_library_name=$($python_executable -c "import sysconfig as s; print(str(s.get_config_var(\"LDLIBRARY\")))")
python_library_dir=$($python_executable -c "import sysconfig as s; print(str(s.get_config_var(\"LIBDIR\")))")
python_library="$python_library_dir/$python_library_name"
python_inc_dir=$($python_executable -c "import sysconfig as s; print(str(s.get_config_var(\"INCLUDEPY\")))")
numpy_inc_dir=$($python_executable -c "import numpy; print(numpy.get_include())")

if [ -n "$TOOLCHAIN_DEFS" ]; then
    export CMAKE_TOOLCHAIN_FILE="$OPENVINO_HOME/cmake/$TOOLCHAIN_DEFS"
    # use cross-compiled binaries
    pymalloc=""
    [ "$python_min_ver" -lt "8" ] && pymalloc="m"
    python_library="/opt/python3.${python_min_ver}_arm/lib/libpython3.${python_min_ver}${pymalloc}.so"
    python_inc_dir="/opt/python3.${python_min_ver}_arm/include/python3.${python_min_ver}${pymalloc}"
fi

# cleanup package destination folder
[ -e "$STAGING_DIR" ] && rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Build oneTBB
cmake -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_CXX_FLAGS="-Wno-error=attributes" \
    -DCMAKE_INSTALL_PREFIX="$ONETBB_BUILD/install" \
    -DTBB_TEST=OFF \
    -S "$ONETBB_HOME" \
    -B "$ONETBB_BUILD" && \
cmake --build "$ONETBB_BUILD" --parallel "$BUILD_JOBS" && \
cmake --install "$ONETBB_BUILD" && \
cd "$DEV_HOME" || fail 11 "oneTBB build failed. Stopping"

# export TBB for later usage in OpenCV / OpenVINO
export TBB_DIR="$ONETBB_BUILD/install/lib/cmake/TBB/"
# Build OpenCV
if [ "$WITH_OPENCV" = "ON" ]; then
    cmake -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DBUILD_LIST=imgcodecs,videoio,highgui,gapi,python3 \
        -DCMAKE_INSTALL_PREFIX="$STAGING_DIR/extras/opencv" \
        -DBUILD_opencv_python2=OFF \
        -DBUILD_opencv_python3=ON \
        -DOPENCV_SKIP_PYTHON_LOADER=OFF \
        -DPYTHON3_LIMITED_API=ON \
        -DPYTHON3_EXECUTABLE="$python_executable" \
        -DPYTHON3_INCLUDE_PATH="$python_inc_dir" \
        -DPYTHON3_LIBRARIES="$python_library" \
        -DPYTHON3_NUMPY_INCLUDE_DIRS="$numpy_inc_dir" \
        -DCMAKE_USE_RELATIVE_PATHS=ON \
        -DCMAKE_SKIP_INSTALL_RPATH=ON \
        -DOPENCV_SKIP_PKGCONFIG_GENERATION=ON \
        -DOPENCV_BIN_INSTALL_PATH=bin \
        -DOPENCV_PYTHON3_INSTALL_PATH=python \
        -DOPENCV_INCLUDE_INSTALL_PATH=include \
        -DOPENCV_LIB_INSTALL_PATH=lib \
        -DOPENCV_CONFIG_INSTALL_PATH=cmake \
        -DOPENCV_3P_LIB_INSTALL_PATH=3rdparty \
        -DOPENCV_SAMPLES_SRC_INSTALL_PATH=samples \
        -DOPENCV_DOC_INSTALL_PATH=doc \
        -DOPENCV_OTHER_INSTALL_PATH=etc \
        -DOPENCV_LICENSES_INSTALL_PATH=etc/licenses \
        -DWITH_GTK_2_X=OFF \
        -DOPENCV_ENABLE_PKG_CONFIG=ON \
        -S "$OPENCV_HOME" \
        -B "$OPENCV_BUILD" && \
    cmake --build "$OPENCV_BUILD" --parallel "$BUILD_JOBS" && \
    cmake --install "$OPENCV_BUILD" && \
    mkdir -pv "$STAGING_DIR/python/python3" && cp -r "$STAGING_DIR/extras/opencv/python/cv2" "$STAGING_DIR/python/python3" && \
    cd "$DEV_HOME" || fail 11 "OpenCV build failed. Stopping"

    # export OpenCV for later usage in OpenVINO
    export OpenCV_DIR="$STAGING_DIR/extras/opencv/cmake"
fi

# Build OpenVINO
cmake -DENABLE_CPPLINT=OFF \
      -DENABLE_NCC_STYLE=OFF \
      -DENABLE_PYTHON=OFF \
      -DENABLE_TEMPLATE=OFF \
      -DENABLE_TESTS=OFF \
      -DENABLE_GAPI_TESTS=OFF \
      -DENABLE_DATA=OFF \
      -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
      -DARM_COMPUTE_SCONS_JOBS="$BUILD_JOBS" \
      -DOPENVINO_EXTRA_MODULES="$ARM_PLUGIN_HOME" \
      -S "$OPENVINO_HOME" \
      -B "$OPENVINO_BUILD" && \
cmake --build "$OPENVINO_BUILD" --parallel "$BUILD_JOBS" && \
cmake --install "$OPENVINO_BUILD" --prefix "$STAGING_DIR" && \
cd "$DEV_HOME" || fail 12 "OpenVINO build failed. Stopping"

# OpenVINO python
[ "$UPDATE_SOURCES" = "clean" ] && [ -e "$OPENVINO_BUILD/pbuild" ] && rm -rf "$OPENVINO_BUILD/pbuild"
[ -e "/opt/cross_venv/bin/activate" ] && . /opt/cross_venv/bin/activate

cmake -DOpenVINODeveloperPackage_DIR="$OPENVINO_BUILD" \
      -DCMAKE_INSTALL_PREFIX="$STAGING_DIR" \
      -DENABLE_PYTHON=ON \
      -DENABLE_WHEEL=ON \
      -S "$OPENVINO_HOME/src/bindings/python" \
      -B "$OPENVINO_BUILD/pbuild" && \
cmake --build "$OPENVINO_BUILD/pbuild" --parallel "$BUILD_JOBS" && \
cmake --install "$OPENVINO_BUILD/pbuild" && \
cd "$DEV_HOME" || fail 13 "OpenVINO python bindings build failed. Stopping"

# deactivate crossenv
[ -e "/opt/cross_venv/bin/activate" ] && deactivate

# Open Model Zoo
if [ "$WITH_OMZ_DEMO" = "ON" ]; then
  cmake -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DENABLE_PYTHON=ON \
        -DPYTHON_EXECUTABLE="$python_executable" \
        -DPYTHON_INCLUDE_DIR="$python_inc_dir" \
        -DPYTHON_LIBRARY="$python_library" \
        -DOpenVINO_DIR="$OPENVINO_HOME/build" \
        -S "$OMZ_HOME/demos" \
        -B "$OMZ_BUILD" && \
  cmake --build "$OMZ_BUILD" --parallel "$BUILD_JOBS" && \
  cd "$DEV_HOME" || fail 16 "Open Model Zoo build failed. Stopping"
  python3 "$OMZ_HOME/ci/prepare-openvino-content.py" l "$OMZ_BUILD" && \
  cp -vr "$OMZ_BUILD/dev/." "$STAGING_DIR" && \
  find "$OMZ_BUILD" -type d -name "Release" -exec cp -vr {} "$STAGING_DIR/extras/open_model_zoo/demos" \; || \
  fail 21 "Open Model Zoo package preparation failed. Stopping"
fi

# Package creation
cd "$STAGING_DIR" && \
tar -czvf ../OV_${ARCH_NAME}_package.tar.gz ./* || \
fail 23 "Package creation failed. Nothing more to do"

if [ -d /output ]; then
cp ../OV_${ARCH_NAME}_package.tar.gz /output/
cp -a $STAGING_DIR /output/openvino_build-${ARCH_NAME};
fi

exit 0
