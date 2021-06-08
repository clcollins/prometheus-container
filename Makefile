IMAGE_REGISTRY := quay.io
ORGANIZATION := clcollins
PROJECT := prometheus

HASH := $(shell git rev-parse --short HEAD)
IMAGE_REF := $(IMAGE_REGISTRY)/$(ORGANIZATION)/$(PROJECT)

CONTAINER_SUBSYS := podman
CONTAINERFILE := Containerfile

PUBLISH_IP := 127.0.0.1
PUBLISH_PORT := 9090

.PHONY: build
build:
	$(CONTAINER_SUBSYS) build --format docker -f $(CONTAINERFILE) -t $(IMAGE_REF):$(HASH) .
	$(CONTAINER_SUBSYS) tag $(IMAGE_REF):$(HASH) $(IMAGE_REF):latest

.PHONY: push
push:
	$(CONTAINER_SUBSYS) push --remove-signatures $(IMAGE_REF):$(HASH)
	$(CONTAINER_SUBSYS) push --remove-signatures $(IMAGE_REF):latest

.PHONY: run
run:
	$(CONTAINER_SUBSYS) run --mount=type=bind,src=$(shell pwd)/data,dst=/prometheus/data,relabel=shared --publish=$(PUBLISH_IP):$(PUBLISH_PORT):$(PUBLISH_PORT) --read-only=true --detach $(IMAGE_REF):$(HASH)

.PHONY: run_node_exporter
run_node_exporter:
	$(CONTAINER_SUBSYS) run --net="host" --pid="host" --mount=type=bind,src=/,dst=/host,ro=true,bind-propagation=rslave --detach quay.io/prometheus/node-exporter:latest --path.rootfs=/host
