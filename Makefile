# Builds the images defined in docker-compose.base.yml.
# Compose always builds through bake, which refuses the templates' `network: host`
# unless it is explicitly allowed, so we call bake directly.
#
#   make                ovpn-client:latest, openconnect-client:latest
#   make no-cache       same, ignoring the build cache
#   make raw            same images with plain `docker build` (no bake/buildx needed)
#   make raw-no-cache   raw build, ignoring the build cache
#   make ARGS=...       pass extra flags to bake / docker build

# Compose resolves `context: ${PWD}` from the environment; pin it to this directory (make -C safe)
export PWD := $(CURDIR)

ARGS ?=
BAKE := docker buildx bake --allow=network.host -f docker-compose.base.yml --load $(ARGS)
DOCKER_BUILD := docker build --network host $(ARGS)

.PHONY: all build no-cache raw raw-no-cache

all: build

build:
	$(BAKE) ovpn-template openconnect-template

no-cache:
	$(MAKE) build ARGS="$(ARGS) --no-cache"

raw:
	$(DOCKER_BUILD) -f Dockerfile --target ovpn -t ovpn-client:latest $(CURDIR)
	$(DOCKER_BUILD) -f Dockerfile --target openconnect -t openconnect-client:latest $(CURDIR)

raw-no-cache:
	$(MAKE) raw ARGS="$(ARGS) --no-cache"
