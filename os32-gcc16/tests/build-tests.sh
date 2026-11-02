#!/bin/sh
# Build the os32-gcc16 qualification tests with the stove (STOVE, default
# ~/AmiCradle/stoves/os32-gcc16) into bin/. Copy bin/ and run-tests to an
# instance (e.g. DH1:GCC16/), Execute run-tests there, copy results/ back and
# run ./check-results.sh. OPENTLS points at a gfopentls checkout (t8, t9).
#
# All builds are for the 68040 only, soft float by default, so one program runs
# on a full 68040 and on an LC/EC040. Each test is built for:
#   040   -m68040 + SOFT    soft float (libm020; maths through the mathieee
#                           libraries). SOFT is -specs=build/m68k-soft-m68040.specs:
#                           without it (stock *link_cpu) the link takes libnix's
#                           FPU libm881 and strtod/atof/printf("%f") go wrong.
#   040f  -m68040 -m68881   with the FPU (hard float), as the browser stack builds
set -u
cd "$(dirname "$0")"
STOVE=${STOVE:-"$HOME/AmiCradle/stoves/os32-gcc16"}
OPENTLS=${OPENTLS:-"$HOME/gfopentls"}
P="$STOVE/prefix/bin/m68k-amigaos-"
SOFT="-specs=$(cd ../.. && pwd)/build/m68k-soft-m68040.specs"
# libos32compat for the code model in FLAGS: compat/ (absolute), compat/libb (-fbaserel)
# or compat/libb32 (-fbaserel32). A base-relative program must not get the absolute one.
# The C++ tests are soft float, so they need a soft-float libos32compat: COMPAT_DIR
# names one built by compat/build.sh (a stove installed before 17 Oct 2026 has
# only the -m68020 -m68881 one in <stove>/compat).
compat_for() {   # compat_for FLAGS...
    case " $* " in
        *" -fbaserel32 "*) d=/libb32 ;;
        *" -fbaserel "*) d=/libb ;;
        *) d= ;;
    esac
    echo "-L${COMPAT_DIR:-$STOVE/compat}$d -los32compat -Wl,--wrap=malloc -Wl,--wrap=calloc -Wl,--wrap=realloc -Wl,--wrap=free -Wl,-u,___wrap_malloc -Wl,-u,___wrap_free -Wl,-u,___wrap_calloc -Wl,-u,___wrap_realloc"
}
cxxlibs_for() { echo "-lpthread -latomic -lstdc++ $(compat_for "$@") -fexceptions"; }
COMPAT=$(compat_for)
CXXLIBS=$(cxxlibs_for)
COMMON="-O2 -fno-delete-null-pointer-checks -fomit-frame-pointer"
mkdir -p bin obj
: > build.log
ok() { printf '%-28s %8s bytes\n' "$1" "$(wc -c < "$1")" | tee -a build.log; }
bad() { echo "$1: BUILD FAILED (see build.log)" | tee -a build.log; }
run() { echo "== $*" >> build.log; "$@" >> build.log 2>&1; }
echo "stove: $("${P}gcc" --version | head -1)" | tee -a build.log

# t1: exceptions through a static library and a C function
F="-m68040 $SOFT $COMMON -std=gnu++23"
if run "${P}g++" $F -c src/t1_except_b.cpp -o obj/t1b.o && run "${P}ar" rcs obj/libt1.a obj/t1b.o &&
   run "${P}gcc" -m68040 $SOFT $COMMON -fexceptions -c src/t1_except_c.c -o obj/t1c.o &&
   run "${P}g++" $F -o bin/t1-040 src/t1_except_a.cpp obj/t1c.o -Lobj -lt1 $CXXLIBS; then ok bin/t1-040; else bad bin/t1-040; fi
# t2..t4: RTTI, threads, atomics
run "${P}g++" $F -o bin/t2-040 src/t2_rtti_a.cpp src/t2_rtti_b.cpp $CXXLIBS && ok bin/t2-040 || bad bin/t2-040
run "${P}g++" $F -o bin/t3-040 src/t3_threads.cpp $CXXLIBS && ok bin/t3-040 || bad bin/t3-040
run "${P}g++" $F -o bin/t4-040 src/t4_atomics.cpp $CXXLIBS && ok bin/t4-040 || bad bin/t4-040
# t3a-t3f: t3's pieces one at a time (t3 crashed with an address error in a thread, 11 Oct)
for t in t3a_join t3b_condvar t3c_tls t3d_once t3e_async t3g_malloc t3h_malloc_locked; do
    b=${t%%_*}
    run "${P}g++" $F -o bin/$b-040 src/$t.cpp $CXXLIBS && ok bin/$b-040 || bad bin/$b-040
done
run "${P}gcc" -m68040 $SOFT $COMMON -o bin/t3f-040 src/t3f_pthread.c -lpthread && ok bin/t3f-040 || bad bin/t3f-040
# t11-t19: C++ thread safety (exceptions in threads, thread_local destructors,
# more than 22 threads at once, shared_mutex, jthread, atomic wait, cv_any,
# iostreams, 1150 short threads)
for t in t11_thread_except t12_tls_dtor t13_many_threads t14_shared_mutex t15_jthread t16_atomic_wait t17_cv_any t18_iostream t19_create_join; do
    b=${t%%_*}
    run "${P}g++" $F -o bin/$b-040 src/$t.cpp $CXXLIBS && ok bin/$b-040 || bad bin/$b-040
done
# t12c, t13c, t19c: t12, t13 and t19 built with -fuse-cxa-atexit. With the stove's default
# (-fno-use-cxa-atexit) GCC registers no destructor for a thread_local, so these
# count none. Built this way the destructors go through libstdc++'s
# __cxa_thread_atexit and libpthread's TLS destructor loop at thread exit.
for t in t12_tls_dtor t13_many_threads t19_create_join; do
    b=${t%%_*}c
    run "${P}g++" $F -fuse-cxa-atexit -o bin/$b-040 src/$t.cpp src/cxa_dso.c $CXXLIBS && ok bin/$b-040 || bad bin/$b-040
done
# t5: a jump table that needs 32-bit offsets
run "${P}gcc" -m68040 $SOFT $COMMON -mlong-jump-table-offsets -o bin/t5-040 src/t5_bigswitch.c && ok bin/t5-040 || bad bin/t5-040
# t6: the FPCR clash (exit code 0 is right; 7 is the clash)
run "${P}gcc" -m68040 -m68881 $COMMON -o bin/t6-040f src/t6_fpcr.c && ok bin/t6-040f || bad bin/t6-040f
# t7..t10 soft float (040) and with the FPU (040f)
for c in 040 040f; do
    case $c in 040) CF="-m68040 $SOFT" ;; 040f) CF="-m68040 -m68881" ;; esac
    BR="$OPENTLS/third_party/bearssl"
    BRDEFS="-DBR_USE_UNIX_TIME=0 -DBR_USE_WIN32_TIME=0 -DBR_USE_URANDOM=0 -DBR_USE_WIN32_RAND=0 -DBR_RDRAND=0 -DBR_AES_X86NI=0 -DBR_SSE2=0 -DBR_POWER8=0 -DBR_INT128=0 -DBR_UMUL128=0 -DBR_64=0 -DBR_LE_UNALIGNED=0 -DBR_BE_UNALIGNED=0 -DOT_LOMUL=1"
    run "${P}gcc" $CF $COMMON -DHOST -o bin/t7-$c src/t7_64bit.c -lm && ok bin/t7-$c || bad bin/t7-$c
    # GFOpenTLS's own flags for BearSSL (build-amiga-tls.sh), plus this driver
    run "${P}gcc" $CF $COMMON -fno-tree-loop-distribute-patterns -DHOST $BRDEFS -I"$BR/inc" -I"$BR/src" -o bin/t8-$c src/t8_bearssl_kat.c "$BR"/src/*/*.c && ok bin/t8-$c || bad bin/t8-$c
    run "${P}gcc" $CF $COMMON -fno-tree-loop-distribute-patterns -DHOST -I"$OPENTLS/include" -I"$OPENTLS/library" -o bin/t9-$c src/t9_opencrypto_kat.c "$OPENTLS"/src/opencrypto_*.c && ok bin/t9-$c || bad bin/t9-$c
    # t10 deliberately WITHOUT -fno-tree-loop-distribute-patterns: it checks the memmove fix
    run "${P}gcc" $CF $COMMON -o bin/t10-$c src/t10_memmove.c && ok bin/t10-$c || bad bin/t10-$c
done
