/* loader.h: runs the 68k code of an Amiga object (libnix's qsort.o and bsearch.o, as
 * test_qsort.sh turns them into code.h) inside a Linux m68k program under qemu-m68k.
 * Both use the same calling convention (arguments on the stack, result in d0, d2-d7 and
 * a2-a6 kept), so t20_qsort.c calls the code as a function. The only relocations
 * allowed are 32-bit references to ___mulsi3 (the 68000 builds' multiply), set here to
 * t_mulsi3. MIT, Copyright (c) 2026 AmiCradle Team. */
#include <string.h>
#include <sys/mman.h>
#include "code.h"   /* t_qsort_code[], t_qsort_rel[], t_bsearch_code[], t_bsearch_rel[], T_NAME */

static __attribute__((noinline)) unsigned long t_mulsi3(unsigned long a, unsigned long b) { return a * b; }

static void *t_load(const unsigned char *code, size_t len, const unsigned long *rel, size_t nrel)
{
    unsigned char *m = mmap(0, len, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    size_t i;
    if (m == MAP_FAILED) { puts("t20: mmap failed"); exit(30); }
    memcpy(m, code, len);
    for (i = 0; i < nrel; i++) {
        unsigned char *p = m + rel[i];
        unsigned long v = ((unsigned long)p[0] << 24 | (unsigned long)p[1] << 16 | (unsigned long)p[2] << 8 | p[3]) + (unsigned long)&t_mulsi3;
        p[0] = (unsigned char)(v >> 24); p[1] = (unsigned char)(v >> 16); p[2] = (unsigned char)(v >> 8); p[3] = (unsigned char)v;
    }
    return m;
}

typedef void (*t_qsort_fn)(void *, size_t, size_t, int (*)(const void *, const void *));
/* bsearch returns its pointer in d0 only: called as returning an integer */
typedef unsigned long (*t_bsearch_fn)(const void *, const void *, size_t, size_t, int (*)(const void *, const void *));
static t_qsort_fn t_qsort_p;
static t_bsearch_fn t_bsearch_p;

static void t_qsort(void *base, size_t n, size_t size, int (*cmp)(const void *, const void *))
{
    if (!t_qsort_p) t_qsort_p = (t_qsort_fn)t_load(t_qsort_code, sizeof t_qsort_code, t_qsort_rel, sizeof t_qsort_rel / sizeof t_qsort_rel[0] - 1);
    t_qsort_p(base, n, size, cmp);
}

static void *t_bsearch(const void *key, const void *base, size_t n, size_t size, int (*cmp)(const void *, const void *))
{
    if (!t_bsearch_p) t_bsearch_p = (t_bsearch_fn)t_load(t_bsearch_code, sizeof t_bsearch_code, t_bsearch_rel, sizeof t_bsearch_rel / sizeof t_bsearch_rel[0] - 1);
    return (void *)t_bsearch_p(key, base, n, size, cmp);
}

#define T_QSORT t_qsort
#define T_BSEARCH t_bsearch
