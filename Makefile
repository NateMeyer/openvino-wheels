local-arm64:
	docker buildx build --tag ov-builder:latest-arm64 --file Dockerfile.aarch64 --load .

local-armv7:
	docker buildx build --tag ov-builder:latest-armv7 --file Dockerfile.armv7 --load .

local-amd64:
	docker buildx build --platform linux/amd64 --tag ov-builder:latest-amd64 --file Dockerfile.ubuntu --load .
