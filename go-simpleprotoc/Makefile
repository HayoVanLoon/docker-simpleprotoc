
IMAGE_NAME := go-simpleprotoc

VERSION := 3.20.0
ARCH := linux-x86_64


build:
	docker build \
		--build-arg VERSION="$(VERSION)" \
		--build-arg ARCH="$(ARCH)" \
		-t $(IMAGE_NAME) .

explore:
	docker run -i -t $(IMAGE_NAME) bash
