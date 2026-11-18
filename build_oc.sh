#!/bin/bash
# build_oc.sh - reproducible build of the N770 Exynos9810 OC kernel.
# Produces arch/arm64/boot/Image and .../dts/exynos/exynos9810.dtb
#
# Requires: flex (apt), and a Python 2 interpreter reachable as `python`
# (needed by scripts/rkp_cfp/instrument.py - the RKP-CFP/JOPP vmlinux step).
# Set PY2_BIN to a python2 binary; a `python` shim is created automatically.
set -euo pipefail
cd "$(dirname "$0")"

GCC_BIN="$PWD/toolchain/gcc-cfp/gcc-cfp-jopp-only/aarch64-linux-android-4.9/bin"
[ -x "$GCC_BIN/aarch64-linux-android-gcc" ] || { echo "bundled GCC not found"; exit 1; }

PY2_BIN="${PY2_BIN:-$(command -v python2 || true)}"
[ -n "$PY2_BIN" ] || { echo "ERROR: need Python 2; set PY2_BIN=/path/to/python2"; exit 1; }
SHIM="$(mktemp -d)"; ln -sf "$PY2_BIN" "$SHIM/python"
trap 'rm -rf "$SHIM"' EXIT

export PATH="$SHIM:$GCC_BIN:$PATH"
export ARCH=arm64 PLATFORM_VERSION=12 ANDROID_MAJOR_VERSION=s
export CONFIG_SECTION_MISMATCH_WARN_ONLY=y
MK="ARCH=arm64 CROSS_COMPILE=aarch64-linux-android- HOSTCFLAGS=-fcommon"

python --version
make $MK exynos9810-r7_defconfig
make $MK -j"$(nproc)"
ls -la arch/arm64/boot/Image arch/arm64/boot/dts/exynos/exynos9810.dtb
sha256sum arch/arm64/boot/Image arch/arm64/boot/dts/exynos/exynos9810.dtb
