local-arm64:
	docker buildx build --platform linux/arm64 --tag ov-builder:latest-arm64 --file Dockerfile --load .

local-armv7:
	docker buildx build --platform linux/arm/v7 --tag ov-builder:latest-armv7 --file Dockerfile --load .

local-amd64:
	docker buildx build --platform linux/amd64 --tag ov-builder:latest-amd64 --file Dockerfile.ubuntu --load .
