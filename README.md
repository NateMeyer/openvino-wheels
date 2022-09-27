# OpenVino Wheels

This repo contains build scripts to generate the OpenVino Python library wheels.  This will build the wheel against python 3.9 and build it for x86_64, arm64, and armv7 architectures.

A docker image is generated to run the build within.  Included build script(s) will download, configure, install dependencies, and build the openvino library, generating the python wheel distributable package at the end.  The image is intended to have `/work` and `/output` folders mapped to the user's filesystem to use as a build folder and to store the wheel packages when complete.

The included build script will also apply a patch that adds the Myriad plugin to the python wheel. This is needed to be able to use the NCS2 from Intel with the python library.

Note: the NCS2 will be deprecated after OpenVino 2022.3.  The build script currently downloads the 2022.2 release tag from Intel's Openvino Github repository.

## Pre-requisites

- Install a recent version of docker with buildx support.  The command to do this will depend on your host environment.
- An internet connection
- Patience

## Usage

The makefile included will generate the build image using docker and buildx.

### AMD64 Build

```bash
> make local-amd64
```

Run the generated image to produce the OpenVino wheel.

```bash
> mkdir -p  work.amd64 && mkdir -p output
> docker run \
  -v $PWD/work.amd64:/work \
  -v $PWD/output:/output \
  ov-builder:latest-amd64
```

### ARM64 Build

```bash
> make local-arm64
```

```bash
> mkdir -p  work.arm64 && mkdir -p output
> docker run \
  -v $PWD/work.arm64:/work \
  -v $PWD/output:/output \
  ov-builder:latest-arm64
```

All the resulting build files can be found in the `work.amd64/openvino/build` folder.  If you only want to keep the .whl (both the runtime and the dev package), these are copied to the `output` folder