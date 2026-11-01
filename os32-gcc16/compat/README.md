# libos32compat for the os32-gcc16 stove

What libstdc++ (GCC 16) and C++ programs need that libnix does not have:
`__xpg_strerror_r` and other C symbols (`os32compat.c`), `aligned_alloc`/`memalign`/`posix_memalign`
over a wrapped malloc (`os32compat_malloc.c`), C99 float functions (`os32compat_math.c`),
C++-mangled `clock_*` and `statvfs` (`os32compat_cxx.cpp`, `os32compat_statvfs.cpp`), and
long double maths through double (`ldbl/`). `fenv.h` and `uchar.h` are header-only.

    sh build.sh [OUT_DIR]        STOVE defaults to ~/AmiCradle/stoves/os32-gcc16

`build.sh` makes six libraries, all for the 68040: soft float (the default for all our builds) as `libos32compat.a` (absolute), `libb/libos32compat.a` (`-fbaserel`) and `libb32/libos32compat.a` (`-fbaserel32`), and the same three with the FPU (`-m68881`) in `m881/`, `libb/m881/` and `libb32/m881/`. The maths parts return floating point values, so a program must link the one that matches its own float ABI: a hard-float program adds `/m881` to its `-L`. Soft-float objects are compiled with `-specs=build/m68k-soft-m68040.specs` (see the top README). Base-relative programs need their own build: the absolute one uses a4 as a scratch register in the malloc wrappers, and a `-fbaserel32` program linked with it hangs. Before 17 October 2026 the absolute one reproduced the stove's installed `compat/libos32compat.a` (`-m68020 -m68881`) object for object; the installed stoves still have that one.
Link it after libstdc++: `-lstdc++ -L<stove>/compat -los32compat`, with
`-Wl,--wrap=malloc,--wrap=calloc,--wrap=realloc,--wrap=free` for the aligned allocator.
