#!/bin/sh

set -eu

ISH_SOURCE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SDK_NAME=${SDK_NAME:-iphoneos}
SDKROOT=$(xcrun --sdk "$SDK_NAME" --show-sdk-path)
ARCH=${ARCHS%% *}
ARCH=${ARCH:-arm64}
BUILD_STYLE=${CONFIGURATION:-Debug}
DEPLOYMENT_TARGET=${IPHONEOS_DEPLOYMENT_TARGET:-18.0}
BUILD_DIR=${ISH_BUILD_DIR:-"$ISH_SOURCE_ROOT/build-xcode/$BUILD_STYLE-$SDK_NAME-$ARCH"}
OUTPUT_DIR=${ISH_OUTPUT_DIR:-"$BUILD_DIR/out"}
CROSS_FILE="$BUILD_DIR/cross-file.txt"

case "$SDK_NAME" in
    iphonesimulator*)
        VERSION_MIN_FLAG="-mios-simulator-version-min=$DEPLOYMENT_TARGET"
        ;;
    *)
        VERSION_MIN_FLAG="-mios-version-min=$DEPLOYMENT_TARGET"
        ;;
esac

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

cat > "$CROSS_FILE" <<EOF
[binaries]
c = ['/usr/bin/xcrun', '--sdk', '$SDK_NAME', 'clang', '-arch', '$ARCH', '-isysroot', '$SDKROOT', '$VERSION_MIN_FLAG']
ar = ['/usr/bin/xcrun', '--sdk', '$SDK_NAME', 'ar']
strip = ['/usr/bin/xcrun', '--sdk', '$SDK_NAME', 'strip']
pkg-config = 'false'

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
needs_exe_wrapper = true
sys_root = '$SDKROOT'
EOF

MESON_ARGS="--cross-file $CROSS_FILE --buildtype release -Db_ndebug=true -Dlog= -Dlog_handler=nslog -Dengine=asbestos -Dkernel=ish -Dguest_arch=arm64"

if [ ! -f "$BUILD_DIR/build.ninja" ]; then
    # shellcheck disable=SC2086
    meson setup "$BUILD_DIR" "$ISH_SOURCE_ROOT" $MESON_ARGS
else
    meson configure "$BUILD_DIR" \
        --buildtype release \
        -Db_ndebug=true \
        -Dlog= \
        -Dlog_handler=nslog \
        -Dengine=asbestos \
        -Dkernel=ish \
        -Dguest_arch=arm64
fi

ninja -C "$BUILD_DIR" libish_emu.a libish.a libfakefs.a

for library in libish_emu.a libish.a libfakefs.a; do
    install -m 0644 "$BUILD_DIR/$library" "$OUTPUT_DIR/$library"
done

printf 'iSH ARM64 libraries: %s\n' "$OUTPUT_DIR"
