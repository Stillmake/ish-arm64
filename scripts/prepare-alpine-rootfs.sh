#!/bin/sh

set -eu

ISH_SOURCE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ALPINE_VERSION=${ALPINE_VERSION:-3.21.0}
ALPINE_ARCH=${ALPINE_ARCH:-aarch64}
CACHE_DIR=${ISH_CACHE_DIR:-"$ISH_SOURCE_ROOT/.cache"}
NATIVE_BUILD_DIR=${ISH_NATIVE_BUILD_DIR:-"$ISH_SOURCE_ROOT/build-native"}
OUTPUT_PATH=${ISH_ROOTFS_OUTPUT:?Set ISH_ROOTFS_OUTPUT to the destination ZIP path}
TARBALL="$CACHE_DIR/alpine-minirootfs-$ALPINE_VERSION-$ALPINE_ARCH.tar.gz"
WORK_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$CACHE_DIR" "$(dirname "$OUTPUT_PATH")"

if [ ! -f "$TARBALL" ]; then
    curl -fL \
        "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION%.*}/releases/$ALPINE_ARCH/alpine-minirootfs-$ALPINE_VERSION-$ALPINE_ARCH.tar.gz" \
        -o "$TARBALL"
fi

curl -fL \
    "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION%.*}/releases/$ALPINE_ARCH/alpine-minirootfs-$ALPINE_VERSION-$ALPINE_ARCH.tar.gz.sha256" \
    -o "$TARBALL.sha256"
(
    cd "$CACHE_DIR"
    shasum -a 256 -c "$(basename "$TARBALL").sha256"
)

if [ ! -x "$NATIVE_BUILD_DIR/tools/fakefsify" ]; then
    if [ ! -f "$NATIVE_BUILD_DIR/build.ninja" ]; then
        meson setup "$NATIVE_BUILD_DIR" "$ISH_SOURCE_ROOT" \
            --buildtype release \
            -Db_ndebug=true \
            -Dengine=asbestos \
            -Dkernel=ish \
            -Dguest_arch=arm64
    fi
    ninja -C "$NATIVE_BUILD_DIR" tools/fakefsify
fi

"$NATIVE_BUILD_DIR/tools/fakefsify" "$TARBALL" "$WORK_DIR/alpine-rootfs"
printf 'aarch64\n' > "$WORK_DIR/alpine-rootfs/.arch"
sqlite3 "$WORK_DIR/alpine-rootfs/meta.db" 'PRAGMA wal_checkpoint(TRUNCATE);'
rm -f "$WORK_DIR/alpine-rootfs/meta.db-shm" "$WORK_DIR/alpine-rootfs/meta.db-wal"
ditto -c -k --norsrc --noextattr --keepParent "$WORK_DIR/alpine-rootfs" "$OUTPUT_PATH"

printf 'Alpine fakefs rootfs: %s\n' "$OUTPUT_PATH"
