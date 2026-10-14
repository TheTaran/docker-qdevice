.PHONY: build test up down logs

IMAGE ?= docker-qdevice:local

build:
	docker build -t $(IMAGE) .

test:
	sh tests/test-entrypoint.sh
	docker compose config --quiet

up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f qnetd
