#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:?usage: package_release.sh <tag>}"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$ROOT_DIR/release-staging"

source "$ROOT_DIR/scripts/common.sh"

rm -rf "$DIST_DIR" "$STAGING_DIR"
mkdir -p "$DIST_DIR"

for CAMERA in "${!CAMERAS[@]}"; do
    MODEL_DIR="$STAGING_DIR/$CAMERA"
    mkdir -p "$MODEL_DIR"

    cp "$ROOT_DIR/build/home/yi-hack/bin/h264grabber" "$MODEL_DIR/"
    cp "$ROOT_DIR/build/home/yi-hack/bin/h264grabber2" "$MODEL_DIR/"
    cp "$ROOT_DIR/build/home/yi-hack/bin/rRTSPServer" "$MODEL_DIR/"
    cp "$ROOT_DIR/src/static/static/home/yi-hack/script/wd.sh" "$MODEL_DIR/"
    cp "$ROOT_DIR/src/static/static/home/yi-hack/script/service.sh" "$MODEL_DIR/"
    cp "$ROOT_DIR/src/static/static/home/yi-hack/script/system.sh" "$MODEL_DIR/"
    cp "$ROOT_DIR/src/www/httpd/cgi-bin/load.sh" "$MODEL_DIR/"
    chmod 755 "$MODEL_DIR"/*

    printf '%s\n' "$CAMERA" > "$MODEL_DIR/MODEL"
    cat > "$MODEL_DIR/README.txt" <<EOF
yihack-tng $TAG for $CAMERA

This package contains the model-agnostic MStar grabber binaries, the patched
RTSP server, and RTSP scripts. The camera selects its own model suffix from
/home/yi-hack/model_suffix.

Set RTSP_TRANSPORT=tcp in /home/yi-hack/etc/system.conf to force RTP-over-TCP,
then restart RTSP. The default is udp.

Supported package targets: ${!CAMERAS[*]}

The binaries and scripts are shared across models. This package is not a
complete firmware image and does not include the stock home/rootfs partitions.

The maintainer has no hardware access to test these packages. They are built by
GitHub Actions but are not hardware-validated. Test on a spare camera before
deploying.
EOF

    tar -czf "$DIST_DIR/yihack-tng-${TAG}-${CAMERA}.tar.gz" -C "$MODEL_DIR" .
done
