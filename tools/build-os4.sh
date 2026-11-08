#!/bin/sh
# build-os4.sh [make args] - cross-compile boing and libboing.a for AmigaOS 4.1 PPC in the
# walkero GCC 11 Docker image. Output in build/os4/. `tools/build-os4.sh check-cpu` also
# verifies there are no 440-only (dlmzb) instructions.
root=$(cd "$(dirname "$0")/.." && pwd)
case $(uname -m) in
arm64|aarch64) img=walkero/amigagccondocker:os4-gcc11-arm64 ;;
*) img=walkero/amigagccondocker:os4-gcc11-amd64 ;;
esac
exec docker run --rm -v "$root":/src -w /src "${PPC_IMAGE:-$img}" make -f mk/os4.mk -j"${JOBS:-4}" "$@"
