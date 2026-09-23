# Headless Godot for validation and exports. The editor itself runs natively;
# this image is what CI and `make build` use so every platform is built the same way.
#
#   docker compose run --rm validate
#   docker compose run --rm build            # all desktop + web presets -> ./build
#   docker compose run --rm build Web        # one preset
#   docker compose up web                    # play the web build at http://localhost:8080

ARG GODOT_VERSION=4.7.2
FROM debian:bookworm-slim

ARG GODOT_VERSION
ARG TARGETARCH
ENV GODOT_VERSION=${GODOT_VERSION} \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip zip \
        libfontconfig1 libgl1 libxcursor1 libxinerama1 libxrandr2 libxi6 \
    && rm -rf /var/lib/apt/lists/*

# Engine binary + export templates, straight from the official GitHub release.
# Native binary for the host (arm64 on Apple Silicon, x86_64 in CI); the
# templates archive is the same for every host and contains all target platforms.
RUN set -eux; \
    case "${TARGETARCH}" in arm64) arch=arm64 ;; *) arch=x86_64 ;; esac; \
    base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"; \
    curl -fsSL -o /tmp/godot.zip "${base}/Godot_v${GODOT_VERSION}-stable_linux.${arch}.zip"; \
    unzip -q /tmp/godot.zip -d /tmp; \
    mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.${arch}" /usr/local/bin/godot; \
    chmod +x /usr/local/bin/godot; \
    curl -fsSL -o /tmp/templates.tpz "${base}/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"; \
    mkdir -p "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable"; \
    unzip -q /tmp/templates.tpz -d /tmp/templates; \
    mv /tmp/templates/templates/* "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable/"; \
    rm -rf /tmp/godot.zip /tmp/templates.tpz /tmp/templates

WORKDIR /project
COPY tools/docker/entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint
ENTRYPOINT ["entrypoint"]
CMD ["validate"]
