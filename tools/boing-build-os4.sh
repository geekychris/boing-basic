#!/bin/sh
# boing-build-os4.sh PROG.bas|PROG.bbp [-o OUT] [--keep-c] [--debug]
#
# `boing build` for AmigaOS 4 from the Mac: the host `boing` turns the program into C
# (`boing emit-c`), the walkero Docker cross compiler compiles it with -O2 -mcpu=powerpc
# and links it with build/os4/libboing.a (tools/build-os4.sh builds that). The result is
# an OS4 executable; deploy it with tools/os4guest.py push or amiga_mcp's deploy-os4.sh.
# (`boing build --target os4` runs this script.)
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
src= out= keep= debug=
while [ $# -gt 0 ]; do
    case $1 in
    -o) out=$2; shift ;;
    --keep-c) keep=1 ;;
    --debug) debug=1 ;;
    -*) echo "boing-build-os4: unknown option $1" >&2; exit 5 ;;
    *) src=$1 ;;
    esac
    shift
done
[ -n "$src" ] || { echo "usage: boing-build-os4.sh PROG.bas|PROG.bbp [-o OUT] [--keep-c] [--debug]" >&2; exit 5; }
base=$(basename "$src"); base=${base%.*}
[ -n "$out" ] || out=$(dirname "$src")/$base
boing=${BOING:-$root/boing}
[ -x "$boing" ] || boing=$root/build/host/boing
[ -x "$boing" ] || { echo "boing-build-os4: build the host boing first (make)" >&2; exit 10; }
[ -f "$root/build/os4/libboing.a" ] || "$root/tools/build-os4.sh" build/os4/libboing.a >/dev/null

work=$root/build/os4-apps
mkdir -p "$work"
cfile=$work/$base.c
"$boing" emit-c "$src" -o "$cfile"

case $(uname -m) in
arm64|aarch64) img=walkero/amigagccondocker:os4-gcc11-arm64 ;;
*) img=walkero/amigagccondocker:os4-gcc11-amd64 ;;
esac
opt="-O2"; [ -n "$debug" ] && opt="-O0 -g"
# never -mcpu=440/440fp (dlmzb crashes real X5000/A1222/G4 machines)
docker run --rm -v "$root":/src -w /src "${PPC_IMAGE:-$img}" sh -c "
  ppc-amigaos-gcc -mcrt=newlib -mcpu=powerpc $opt -Wall -Wno-unused -D__USE_OLD_TIMEVAL__ -DBB_PLATFORM_OS4 \
    -Isrc/runtime -o build/os4-apps/$base.exe build/os4-apps/$base.c build/os4/libboing.a -lauto -lm &&
  n=\$(ppc-amigaos-objdump -d build/os4-apps/$base.exe | grep -c dlmzb || true); test \"\$n\" = 0 ||
  { echo 'boing-build-os4: dlmzb instructions found (440-only)' >&2; exit 20; }"
mv "$work/$base.exe" "$out"
[ -n "$keep" ] && cp "$cfile" "$(dirname "$out")/$base.c"
echo "$out"
