local-arm64:
	docker buildx build --build-arg ARCH=arm64 --build-arg ARCH_SPEC=aarch64-linux-gnu --build-arg ARCH_TOOLCHAIN=arm64.toolchain.cmake --tag ov-builder:latest-amd64 --file Dockerfile.arm --load .

local-armhf:
	 docker buildx build --build-arg ARCH=armhf --build-arg ARCH_SPEC=arm-linux-gnueabihf --build-arg ARCH_TOOLCHAIN=arm.toolchain.cmake --tag ov-builder:latest-armhf --file Dockerfile.arm --load .

local-amd64:
	docker buildx build --tag ov-builder:latest-amd64 --file Dockerfile.ubuntu --load .
