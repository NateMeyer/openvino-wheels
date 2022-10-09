local-arm64:
	docker buildx build --tag ov-builder:latest-arm64 --file Dockerfile.aarch64 --load .

local-armhf:
	docker buildx build --tag ov-builder:latest-armhf --file Dockerfile.armhf --load .

local-amd64:
	docker buildx build --tag ov-builder:latest-amd64 --file Dockerfile.ubuntu --load .
