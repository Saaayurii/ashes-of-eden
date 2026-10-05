.PHONY: pull-playtest android android-image validate test net-test build build-web web image editor server relay

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

relay:      ## the relay rooms by code go through, on ws://localhost:8920 (docs/RELAY.md)
	docker compose run --rm --service-ports relay

build:      ## export Windows/Linux/macOS/Web to ./build
	docker compose run --rm build

build-web:  ## export only the Web preset
	docker compose run --rm build build Web

web: build-web ## serve the web build at http://localhost:8080
	docker compose up web

editor:     ## open the project in the native Godot editor (macOS)
	open -a Godot --args --path "$(CURDIR)" -e

GODOT := /Applications/Godot.app/Contents/MacOS/Godot

import:     ## re-import changed assets (Godot serves the old ones until you do)
	"$(GODOT)" --headless --path "$(CURDIR)" --import

room: import ## open straight into one room, e.g. make room ROOM=hell_gate (names: make rooms)
	"$(GODOT)" --path "$(CURDIR)" scenes/run/run.tscn -- room=$(ROOM)

rooms:      ## list the names `make room ROOM=...` accepts, in play order
	@grep -o 'scenes/rooms/[a-z0-9_]*\.tscn' scripts/run/run.gd \
		| sed 's|scenes/rooms/||;s|\.tscn||' | nl -w3 -s'  '

android-image: ## Android export image (JDK + SDK + debug keystore; accepts the Android SDK licence)
	docker build -f tools/docker/Dockerfile.android -t ashes-of-eden/godot-android:4.7.2 .

android: ## debug-signed test APK -> build/android/ashes-of-eden.apk (install: adb install -r build/android/ashes-of-eden.apk)
	docker run --rm -v "$(CURDIR):/project" --entrypoint bash ashes-of-eden/godot-android:4.7.2 \
		-c "cp /project/tools/docker/entrypoint.sh /usr/local/bin/entrypoint && chmod +x /usr/local/bin/entrypoint && entrypoint build-debug Android"

PLAYTEST_DIR := $(HOME)/Library/Application Support/Godot/app_userdata/Ashes of Eden/playtest
pull-playtest: ## copy the playtest logs off a USB phone (debug APK) next to the desktop ones, for balance_probe
	mkdir -p "$(PLAYTEST_DIR)"
	adb exec-out run-as org.ashesofeden.game sh -c 'cd files/playtest && tar cf - .' | tar xf - -C "$(PLAYTEST_DIR)"
	@ls "$(PLAYTEST_DIR)" | tail -5
