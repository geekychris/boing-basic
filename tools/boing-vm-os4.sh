#!/bin/sh
# boing-vm-os4.sh OUT GLUE.c [SOURCE...] - `boing vm --target os4`: an AmigaOS 4 interpreter with
# linked extensions, cross-built in the walkero Docker image from the glue `boing vm` wrote, the
# extensions' sources and build/os4/libboingvm.a + libboing.a (docs/extensions.md). Checks dlmzb.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
out=$1; glue=$2; shift 2
[ -f "$root/build/os4/libboingvm.a" ] || "$root/tools/build-os4.sh" build/os4/libboingvm.a build/os4/libboing.a >/dev/null
work=$root/build/os4-apps/vm.$$; rm -rf "$work"; mkdir -p "$work"
rel=build/os4-apps/vm.$$
cp "$glue" "$work/glue.c"
cmds="ppc-amigaos-gcc -mcrt=newlib -mcpu=powerpc -O2 -D__USE_OLD_TIMEVAL__ -DBB_PLATFORM_OS4 -Isrc/runtime -c $rel/glue.c -o $rel/0.o &&"
objs="$rel/0.o"; link=ppc-amigaos-gcc; n=0
for f in "$@"; do
    n=$((n+1)); b=$(basename "$f"); cp "$f" "$work/$n-$b"
    case $b in
    *.cpp|*.cc) cc='ppc-amigaos-g++ -athread=native'; link='ppc-amigaos-g++ -athread=native' ;;
    *) cc=ppc-amigaos-gcc ;;
    esac
    cmds="$cmds $cc -mcrt=newlib -mcpu=powerpc -O2 -D__USE_OLD_TIMEVAL__ -DBB_PLATFORM_OS4 -Isrc/runtime -c $rel/$n-$b -o $rel/$n.o &&"
    objs="$objs $rel/$n.o"
done
case $(uname -m) in
arm64|aarch64) img=walkero/amigagccondocker:os4-gcc11-arm64 ;;
*) img=walkero/amigagccondocker:os4-gcc11-amd64 ;;
esac
docker run --rm -v "$root":/src -w /src "${PPC_IMAGE:-$img}" sh -c "
  $cmds
  $link -mcrt=newlib -mcpu=powerpc -o $rel/boing.exe $objs build/os4/libboingvm.a build/os4/libboing.a -lauto -lm &&
  n=\$(ppc-amigaos-objdump -d $rel/boing.exe | grep -c dlmzb || true); test \"\$n\" = 0 ||
  { echo 'boing-vm-os4: dlmzb instructions found (440-only)' >&2; exit 20; }"
mv "$work/boing.exe" "$out"
rm -rf "$work"
echo "$out"
