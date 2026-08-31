IMAGE ?= ghcr.io/ninjatronics/calibre-server
VERSION ?= 9.14.0

.PHONY: build push

build:
	docker build --pull --tag $(IMAGE):$(VERSION) .

push: build
	docker push $(IMAGE):$(VERSION)
