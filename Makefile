.PHONY: validate test net-test build build-web web image editor server

image:      ## build the Docker image with headless Godot
	docker compose build godot

validate:   ## validate data + localization in Docker
	docker compose run --rm validate

test:       ## headless end-to-end smoke test in Docker
	docker compose run --rm test

net-test:   ## two-process crossplay stand: co-op and duel, in Docker
	docker compose run --rm net-test

server:     ## dedicated headless host on ws://localhost:8910 (for two browsers)
	docker compose run --rm --service-ports server

build:      ## export Windows/Linux/macOS/Web to ./build
	docker compose run --rm build

build-web:  ## export only the Web preset
	docker compose run --rm build build Web

web: build-web ## serve the web build at http://localhost:8080
	docker compose up web

editor:     ## open the project in the native Godot editor (macOS)
	open -a Godot --args --path "$(CURDIR)" -e
