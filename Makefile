# Builds the images defined in compose/docker-compose.base.yml and runs the compose stacks.
# Compose always builds through bake, which refuses the templates' `network: host`
# unless it is explicitly allowed, so we call bake directly.
#
#   make                      ovpn-client:latest, openconnect-client:latest (same as `make build`)
#   make build-no-cache       same, ignoring the build cache
#   make build-raw            same images with plain `docker build` (no bake/buildx needed)
#   make build-raw-no-cache   raw build, ignoring the build cache
#   make ARGS=...             pass extra flags to bake / docker build
#
#   make up                   start a stack in the background (STACK=main|bridge|test, default main)
#   make down                 stop and remove the stack's containers
#   make logs                 follow the stack's logs
#   make ps                   list the stack's containers
#   make config               validate and print the resolved compose file
#   S=...                     limit up/logs to some services, e.g. `make logs STACK=bridge S=tci-bridge`

# Compose resolves `context: ${PWD}/docker` from the environment; pin it to this directory (make -C safe)
export PWD := $(CURDIR)

ARGS ?=
BAKE := docker buildx bake --allow=network.host -f compose/docker-compose.base.yml --load $(ARGS)
DOCKER_BUILD := docker build --network host $(ARGS)

STACK ?= main
S ?=
STACK_FILE_main := docker-compose.yml
STACK_FILE_bridge := compose/docker-compose.bridge.yml
STACK_FILE_test := compose/docker-compose.test.yml
STACK_FILE := $(STACK_FILE_$(STACK))
# Lazy, so an unknown STACK only errors when a compose target runs
COMPOSE = docker compose -f $(or $(STACK_FILE),$(error unknown STACK '$(STACK)', use main|bridge|test))

.PHONY: all build build-no-cache build-raw build-raw-no-cache up down logs ps config

all: build

build:
	$(BAKE) ovpn-template openconnect-template

build-no-cache:
	$(MAKE) build ARGS="$(ARGS) --no-cache"

build-raw:
	$(DOCKER_BUILD) -f docker/Dockerfile --target ovpn -t ovpn-client:latest $(CURDIR)/docker
	$(DOCKER_BUILD) -f docker/Dockerfile --target openconnect -t openconnect-client:latest $(CURDIR)/docker

build-raw-no-cache:
	$(MAKE) build-raw ARGS="$(ARGS) --no-cache"

up:
	$(COMPOSE) up -d $(S)

# No $(S): `down SERVICE` needs a newer Compose than some supported hosts ship
down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f $(S)

ps:
	$(COMPOSE) ps

config:
	$(COMPOSE) config
