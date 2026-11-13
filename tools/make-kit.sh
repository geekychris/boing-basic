#!/bin/zsh
# make-kit.sh [--bb REV] [--af REV] [--no-native] [--out DIR]
#
# Builds the Boing BASIC kit for AmigaOS 4: BoingBASIC.lha, a BoingBASIC drawer with
#
#   AmiForge(.info)           the IDE, AmiForge's feat-basic branch (REV default origin/feat-basic)
#   boing, lib/libboing.a     the compiler/interpreter and runtime, boing_basic REV (default origin/main);
#                             boing has the standard extensions of KIT_STD_EXTS (default: those of sqlite
#                             and opengl that ext/ has)
#   lib/libOSMesa.a           Mesa's software OpenGL, for native builds with Extension=opengl
#   lib/libboingvm.a          the compiler and VM, for `boing vm` on the Amiga (projects with Extension=)
#   include/, bindings/       the runtime headers incl. boing_ext.h (native builds and boing vm), OS library declarations
#   ext/                      the standard extensions' sources (PROGDIR:ext/), when the tree has ext/
#   Docs/Manual, Examples/Book  the user manual (text + BoingBASIC-Manual.guide) and every listing and exercise of it
#   Templates/, Rexx/, Docs/  AmiForge's project templates and macros; the guides as Latin-1 text
#   Examples/<dir>/           every examples/ drawer (not examples/common): sources and assets,
#                             a .afp project with an icon, README.txt, and for games and apps a
#                             ready native build <Name>-native (tools/kit/examples.txt says which)
#   Getting-Started.txt       how to open, run (interpreted) and build (native), each game's keys
#   KIT-MANIFEST.txt          the revisions and examples (tools/install-kit.py reads it)
#
# Both sources are exported clean (git archive) into build/kit/src, and build/os4 is built from
# scratch every time (a stale build/os4 once shipped a boing whose builtin table was out of step).
# Every PowerPC binary is checked for dlmzb (440-only: crashes X5000/A1222/G4). A native build that
# fails doesn't stop the kit: the example ships interpreted and the failure is listed.
#
# Install it on a guest with tools/install-kit.py (BB_GUEST=...).
set -e
here=${0:A:h}
repo=${here:h}
bbrev=origin/main
afrev=origin/feat-basic
native=1
out=$repo/build/kit
afrepo=${AMIFORGE:-$repo/../amiforge}
while (( $# )); do
    case $1 in
    --bb) bbrev=$2; shift ;;
    --af) afrev=$2; shift ;;
    --no-native) native=0 ;;
    --out) out=${2:A}; shift ;;
    *) print -u2 "usage: make-kit.sh [--bb REV] [--af REV] [--no-native] [--out DIR]"; exit 5 ;;
    esac
    shift
done
case $(uname -m) in
arm64|aarch64) img=walkero/amigagccondocker:os4-gcc11-arm64 ;;
*) img=walkero/amigagccondocker:os4-gcc11-amd64 ;;
esac
export PPC_IMAGE=${PPC_IMAGE:-$img}
src=$out/src
log=$out/logs
mkdir -p $out $log

step() { print -P "%B== $*%b" }

# --- the sources, exported clean ---
step "sources"
git -C $repo fetch -q origin || print -u2 "make-kit: git fetch failed in $repo (using what is there)"
git -C $afrepo fetch -q origin || print -u2 "make-kit: git fetch failed in $afrepo (using what is there)"
bbsha=$(git -C $repo rev-parse --verify "$bbrev^{commit}")
afsha=$(git -C $afrepo rev-parse --verify "$afrev^{commit}")
print "boing_basic $bbrev = $bbsha"
print "amiforge    $afrev = $afsha"
rm -rf $src && mkdir -p $src/bb $src/af
git -C $repo archive $bbsha | tar -x -C $src/bb
git -C $afrepo archive $afsha | tar -x -C $src/af
# submodules (scintilla etc.), if AmiForge has any checked out
if [[ -f $afrepo/.gitmodules ]]; then
    git -C $afrepo submodule foreach --quiet 'echo $sm_path' | while read sm; do
        smsha=$(git -C $afrepo ls-tree $afsha $sm | awk '{print $3}')
        mkdir -p $src/af/$sm
        git -C $afrepo/$sm archive $smsha | tar -x -C $src/af/$sm
    done
fi

# --- boing: host (emits C for native builds) and OS4 ---
step "boing (host)"
make -C $src/bb -j${JOBS:-8} >$log/host.log 2>&1 || { tail -30 $log/host.log; exit 1 }
hostboing=$src/bb/build/boing
[[ -x $hostboing ]] || hostboing=$src/bb/build/host/boing
step "boing + libboing.a (OS4, clean, check-cpu)"
rm -rf $src/bb/build/os4
# the standard extensions linked into the kit's boing (docs/extensions.md): KIT_STD_EXTS, else
# sqlite and opengl, each once ext/ has it (OpenGL: Mesa is built for OS4 first, third_party/mesa)
if [[ -n ${KIT_STD_EXTS+x} ]]; then stdexts=$KIT_STD_EXTS
else
    stdexts=
    for x in sqlite opengl; do [[ -d $src/bb/ext/$x ]] && stdexts="${stdexts:+$stdexts }$x"; done
fi
print "standard extensions in the kit's boing: ${stdexts:-none}"
# git archive has no Mesa source or build: reuse this checkout's tarball (it is checked by SHA-256)
[[ -f $repo/third_party/mesa/MesaLib-7.8.2.tar.bz2 && -d $src/bb/third_party/mesa ]] && cp $repo/third_party/mesa/MesaLib-7.8.2.tar.bz2 $src/bb/third_party/mesa/
$src/bb/tools/build-os4.sh check-cpu ${stdexts:+STD_EXTS="$stdexts"} >$log/os4.log 2>&1 || { tail -30 $log/os4.log; exit 1 }
[[ " $stdexts " == *" opengl "* ]] && { $src/bb/tools/build-os4.sh build/os4/libOSMesa.a >>$log/os4.log 2>&1 || { tail -30 $log/os4.log; exit 1 } }
[[ -f $src/bb/build/os4/libboingvm.a ]] || { print -u2 "make-kit: no build/os4/libboingvm.a (boing vm needs it)"; exit 1 }
# The guest SDK's ld (binutils 2.23) doesn't know GCC 11's float-ABI attribute value ("hard float,
# 64-bit long double", Tag_GNU_Power_ABI_FP 9) and warns "uses unknown floating point ABI 9" for every
# object of libboing.a in a `boing build` on the Amiga. The guest's GCC 11.5 targets the same ABI, so
# the attribute adds nothing: the shipped libraries go without .gnu.attributes.
docker run --rm -v $src/bb/build/os4:/o -w /o $PPC_IMAGE sh -c '
  libs="libboing.a libboingvm.a"; [ -f libOSMesa.a ] && libs="$libs libOSMesa.a"
  for a in $libs; do ppc-amigaos-objcopy --remove-section=.gnu.attributes $a || exit 1; done
  n=$(for a in $libs; do ppc-amigaos-readelf -A $a; done | grep -c Tag_GNU_Power_ABI_FP); test "$n" = 0' \
  || { print -u2 "make-kit: removing .gnu.attributes from the libraries failed"; exit 1 }
print "libboing.a, libboingvm.a: no .gnu.attributes (the guest SDK's ld 2.23 warned about GCC 11's float-ABI tag)"
grep 'dlmzb=' $log/os4.log | grep -v 'dlmzb=0$' && { print -u2 "make-kit: dlmzb in the OS4 build"; exit 1 }
print "$(grep -c 'dlmzb=0' $log/os4.log) OS4 binaries, no dlmzb"

# --- AmiForge feat-basic ---
step "AmiForge (OS4, check-cpu)"
(cd $src/af && tools/build.sh all) >$log/amiforge.log 2>&1 || { tail -30 $log/amiforge.log; exit 1 }
[[ -f $src/af/build/AmiForge ]] || { print -u2 "make-kit: no build/AmiForge"; exit 1 }
python3 $src/af/tools/make-icons.py $out/icons >/dev/null

# --- native builds of the games and apps ---
rm -rf $out/native && mkdir -p $out/native
failed=()
if (( native )); then
    python3 $here/kit/kit.py plan $src/bb | while IFS=$'\t' read dir bbp nat name; do
        [[ $nat == 1 ]] || continue
        step "native: $dir ($name)"
        mkdir -p $out/native/$dir
        if BOING=$hostboing $src/bb/tools/boing-build-os4.sh $src/bb/examples/$dir/$bbp \
                -o $out/native/$dir/$name >$log/native-$dir.log 2>&1; then
            docker run --rm -v $out/native/$dir:/n $PPC_IMAGE ppc-amigaos-strip /n/$name
            print "  $(wc -c < $out/native/$dir/$name | tr -d ' ') bytes"
        else
            tail -15 $log/native-$dir.log
            rm -f $out/native/$dir/$name
            print "$dir" >> $out/native/FAILED
        fi
    done
fi

# --- the drawer ---
step "assemble"
python3 $here/kit/kit.py assemble --bb $src/bb --af $src/af --icons $out/icons --native $out/native \
    --stage $out/stage --bb-rev $bbsha --af-rev $afsha
top=$out/stage/BoingBASIC

# every example as staged must pass `boing check` (paths rewritten, assets beside it)
step "boing check (host) of every staged example"
bad=0
grep '^example=' $top/KIT-MANIFEST.txt | cut -d= -f2 | while IFS='|' read dir name kind afp bbp nat; do
    if (cd $top/Examples/$dir && $hostboing check $bbp >$log/check-$dir.log 2>&1); then
        print "  ok    $dir/$bbp"
    else
        print "  FAIL  $dir/$bbp"; sed 's/^/        /' $log/check-$dir.log | head -8; bad=1
    fi
done
(( bad == 0 )) || { print -u2 "make-kit: an example doesn't check"; exit 1 }

# dlmzb in anything PowerPC in the drawer
step "dlmzb check of every ELF in the kit"
elfs=()
for f in $top/**/*(.); do [[ $(head -c 4 $f) == $'\x7fELF' ]] && elfs+=(${f#$out/stage/}); done
docker run --rm -v $out/stage:/s -w /s $PPC_IMAGE sh -c '
  n=0; for f in "$@"; do c=$(ppc-amigaos-objdump -d "$f" | grep -c dlmzb); echo "  $f: dlmzb=$c"; n=$((n+c)); done; test $n -eq 0' sh $elfs \
  || { print -u2 "make-kit: dlmzb found"; exit 1 }

# --- the archive (LHa for UNIX in the build image; files only: xadmaster dislikes directory entries) ---
step "BoingBASIC.lha"
rm -f $out/BoingBASIC.lha
docker run --rm -v $out:/o -w /o/stage $PPC_IMAGE sh -c 'lha aq ../BoingBASIC.lha BoingBASIC.info $(find BoingBASIC -type f | sort)'
cp $top/KIT-MANIFEST.txt $out/KIT-MANIFEST.txt
print "$out/BoingBASIC.lha: $(wc -c < $out/BoingBASIC.lha | tr -d ' ') bytes, $(find $top -type f | wc -l | tr -d ' ') files"
[[ -f $out/native/FAILED ]] && print "native builds that failed (shipped interpreted): $(tr '\n' ' ' < $out/native/FAILED)"
exit 0
