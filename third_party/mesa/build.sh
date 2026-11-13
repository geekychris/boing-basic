#!/bin/sh
# build.sh [host|os4|all|clean] - static software OSMesa (Mesa 7.8.2, classic swrast) for the
# OpenGL standard extension (ext/opengl, docs/opengl.md).
#   host  out/host/libOSMesa.a with the host's cc (macOS / Linux), about 3 s
#   os4   out/os4/libOSMesa.a with ppc-amigaos-gcc in the walkero Docker image (AmigaOS 4.1 PPC)
# The Mesa tarball is downloaded once and checked against its SHA-256. Mesa is MIT licensed
# (Mesa-7.8.2/docs/COPYING); shims/slang_stub.c replaces its GLSL compiler, so this is OpenGL
# 1.x fixed function (with ARB vertex/fragment programs) only.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
VER=7.8.2
TARBALL=MesaLib-$VER.tar.bz2
URL=https://archive.mesa3d.org/older-versions/7.x/$VER/$TARBALL
SHA=505bf418dceba05837f4ea1b1972b9620c35f8cb94bc4d1e6d573c15f562576d
JOBS=${JOBS:-$( (sysctl -n hw.ncpu || nproc) 2>/dev/null || echo 4)}
what=${1:-host}

if [ "$what" = clean ]; then rm -rf obj out; exit 0; fi

sha() { (shasum -a 256 "$1" 2>/dev/null || sha256sum "$1") | cut -d' ' -f1; }
if [ ! -f "$TARBALL" ]; then
    echo ">> downloading $URL"
    curl -fL -o "$TARBALL.part" "$URL"
    mv "$TARBALL.part" "$TARBALL"
fi
if [ "$(sha "$TARBALL")" != "$SHA" ]; then
    echo "build.sh: $TARBALL does not match its SHA-256 (delete it to download again)" >&2
    exit 1
fi
# patches/*.patch: max-1024 caps the viewport and textures at 1024 x 1024, which makes the span
# functions' stack frames a quarter of the size (_swrast_texture_span: 390 KB -> 99 KB). A tree
# extracted with other patches (the stamp differs) is extracted again, and the objects rebuilt.
want=$(cat patches/*.patch | cksum | cut -d' ' -f1)
if [ ! -d "Mesa-$VER" ] || [ "$(cat "Mesa-$VER/.bb-patches" 2>/dev/null)" != "$want" ]; then
    rm -rf "Mesa-$VER" "Mesa-$VER.tmp" obj out && mkdir "Mesa-$VER.tmp"
    tar xjf "$TARBALL" -C "Mesa-$VER.tmp"
    for p in patches/*.patch; do patch -s -d "Mesa-$VER.tmp/Mesa-$VER" -p1 < "$p"; done
    echo "$want" > "Mesa-$VER.tmp/Mesa-$VER/.bb-patches"
    mv "Mesa-$VER.tmp/Mesa-$VER" "Mesa-$VER" && rmdir "Mesa-$VER.tmp"
fi

if [ "$what" = host ] || [ "$what" = all ]; then
    make -j"$JOBS" TARGET=host
fi
if [ "$what" = os4 ] || [ "$what" = all ]; then
    case $(uname -m) in
    arm64|aarch64) img=walkero/amigagccondocker:os4-gcc11-arm64 ;;
    *) img=walkero/amigagccondocker:os4-gcc11-amd64 ;;
    esac
    docker run --rm -v "$HERE":/work -w /work "${PPC_IMAGE:-$img}" sh -c \
        "export PATH=/opt/ppc-amigaos/bin:\$PATH && make -j$JOBS TARGET=os4 && \
         n=\$(ppc-amigaos-objdump -d out/os4/libOSMesa.a | grep -c dlmzb || true); echo \"dlmzb: \$n\"; test \"\$n\" = 0"
fi
