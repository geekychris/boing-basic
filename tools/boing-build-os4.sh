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
[ -x "$boing" ] || boing=$root/build/boing
[ -x "$boing" ] || boing=$root/build/host/boing
[ -x "$boing" ] || { echo "boing-build-os4: build the host boing first (make)" >&2; exit 10; }
[ -f "$root/build/os4/libboing.a" ] || "$root/tools/build-os4.sh" build/os4/libboing.a >/dev/null
# Extension=opengl links Mesa (build/os4/libOSMesa.a, beside libboing.a)
case $src in *.bbp) case " $("${BOING:-$root/build/boing}" links "$src" os4 2>/dev/null) " in *" -lOSMesa "*)
  [ -f "$root/build/os4/libOSMesa.a" ] || "$root/tools/build-os4.sh" build/os4/libOSMesa.a >/dev/null ;; esac ;; esac

work=$root/build/os4-apps
mkdir -p "$work"
cfile=$work/$base.c
"$boing" emit-c "$src" -o "$cfile"

case $(uname -m) in
arm64|aarch64) img=walkero/amigagccondocker:os4-gcc11-arm64 ;;
*) img=walkero/amigagccondocker:os4-gcc11-amd64 ;;
esac
opt="-O${BOING_OPT:-2}"; [ -n "$debug" ] && opt="-O0 -gstabs"       # stabs: what AmiForge's debugger reads
# linked extensions and CSource= files (docs/extensions.md): copied beside the generated C (the
# container sees only this tree), each compiled to an object; with C++ the C++ driver links
xd=$base.ext.$$; xdir=$work/$xd; rm -rf "$xdir"; mkdir -p "$xdir"     # per run: Docker's file share can miss a directory deleted and made again
xobjs= cmds= link=ppc-amigaos-gcc progx=
case $src in *.bbp)
  n=0
  for f in $("$boing" sources "$src"); do
    n=$((n+1)); b=$(basename "$f"); cp "$f" "$xdir/$n-$b"
    # the headers beside the source (and in its subdirectories, e.g. ext/opengl/GL/gl.h): its
    # quoted #includes find them through -I, as they did beside the original
    inc=$xdir/inc$n; mkdir -p "$inc"
    (cd "$(dirname "$f")" && find . -maxdepth 3 -name '*.h' | while read -r h; do mkdir -p "$inc/$(dirname "$h")"; cp "$h" "$inc/$h"; done)
    ci="-Isrc/runtime -Ibuild/os4-apps/$xd/inc$n"
    case $b in
    *.cpp|*.cc) cmds="$cmds ppc-amigaos-g++ -athread=native -mcrt=newlib -mcpu=powerpc $opt -D__USE_OLD_TIMEVAL__ -DBB_PLATFORM_OS4 $ci -c build/os4-apps/$xd/$n-$b -o build/os4-apps/$xd/$n.o &&"
                link='ppc-amigaos-g++ -athread=native'; progx="-x c" ;;
    *) cmds="$cmds ppc-amigaos-gcc -mcrt=newlib -mcpu=powerpc $opt -D__USE_OLD_TIMEVAL__ -DBB_PLATFORM_OS4 $ci -c build/os4-apps/$xd/$n-$b -o build/os4-apps/$xd/$n.o &&" ;;
    esac
    xobjs="$xobjs build/os4-apps/$xd/$n.o"
  done ;;
esac
[ -n "$progx" ] && xobjs="-x none$xobjs"
xlibs=; case $src in *.bbp) xlibs=$("$boing" links "$src" os4) ;; esac     # .bbx 'link' lines
# never -mcpu=440/440fp (dlmzb crashes real X5000/A1222/G4 machines)
docker run --rm -v "$root":/src -w /src "${PPC_IMAGE:-$img}" sh -c "
  $cmds
  $link -mcrt=newlib -mcpu=powerpc $opt -Wall -Wno-unused -D__USE_OLD_TIMEVAL__ -DBB_PLATFORM_OS4 \
    -Isrc/runtime ${BOING_CFLAGS:-} -o build/os4-apps/$base.exe $progx build/os4-apps/$base.c $xobjs build/os4/libboing.a -Lbuild/os4 $xlibs -lauto -lm &&
  n=\$(ppc-amigaos-objdump -d build/os4-apps/$base.exe | grep -c dlmzb || true); test \"\$n\" = 0 ||
  { echo 'boing-build-os4: dlmzb instructions found (440-only)' >&2; exit 20; }"
mv "$work/$base.exe" "$out"
rm -rf "$xdir"
[ -n "$keep" ] && cp "$cfile" "$(dirname "$out")/$base.c"
echo "$out"
