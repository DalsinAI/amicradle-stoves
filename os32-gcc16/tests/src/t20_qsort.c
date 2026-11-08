/* t20_qsort: libnix's qsort and bsearch with comparison functions real programs use.
 * libnix's qsort (to 7 Nov 2026) never returned, or read outside the array, when the
 * comparison function never returns 0, as libwebp's do (its Huffman-tree sort hung
 * webp.datatype's lossless save). Every comparison goes through guard(), which stops
 * the sort (longjmp) as soon as qsort passes a pointer outside the array or not on an
 * element or calls it more than n*n+64 times (a quicksort needs at most about n*n/2):
 * the test fails instead of hanging. Each part stops at its first wrong sort.
 * Sorts where compar got one element as both arguments are counted and shown (the old
 * qsort did that; libwebp's comparisons assert the two differ, in a debug build).
 * Built as an Amiga program it tests the stove's libnix; qemu-libnix/test_qsort.sh
 * builds it with -DQSORT_UNDER_TEST to run the stove's own machine code under qemu-m68k.
 * MIT, Copyright (c) 2026 AmiCradle Team. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>

#ifdef QSORT_UNDER_TEST
#include QSORT_UNDER_TEST   /* T_NAME, T_QSORT(base, n, size, cmp), T_BSEARCH(key, base, n, size, cmp) */
#else
#define T_NAME "the C library's (libnix on an Amiga)"
#define T_QSORT qsort
#define T_BSEARCH bsearch
#endif

typedef int (*cmp_fn)(const void *, const void *);
static jmp_buf jb;
static const char *lo, *hi;
static size_t esize;
static unsigned long calls, limit;
static int why;                     /* 1 no end, 2 outside, 8 wrong order */
static int fails, self;
static unsigned long selfsorts;

static void guard(const void *p, const void *q)
{
    const char *x = p, *y = q;
    if (++calls > limit) { why = 1; longjmp(jb, 1); }
    if (x < lo || x >= hi || y < lo || y >= hi || (size_t)(x - lo) % esize || (size_t)(y - lo) % esize) { why = 2; longjmp(jb, 1); }
    if (x == y) self = 1;
}

static unsigned long seed = 1;
static unsigned long rnd(void) { seed = seed * 1103515245UL + 12345UL; return (seed >> 8) & 0xffffffUL; }

/* qsort under the guard: 0 when it returned having stayed inside */
static int guarded(void *base, size_t n, size_t size, cmp_fn cmp)
{
    why = 0; self = 0; calls = 0; esize = size ? size : 1; limit = (unsigned long)n * n + 64;
    lo = (const char *)base; hi = lo + n * size;
    if (setjmp(jb)) { selfsorts += self; return why; }
    T_QSORT(base, n, size, cmp);
    selfsorts += self;
    return 0;
}

static const char *what(int w)
{
    return w == 1 ? "never returns" : w == 2 ? "compares outside the array" : "wrong order";
}

static void result(const char *test, int bad, unsigned long cases, int w, unsigned long first)
{
    char note[80] = "";
    if (selfsorts) sprintf(note, " (compar got one element as both arguments in %lu sort%s)", selfsorts, selfsorts == 1 ? "" : "s");
    if (bad) { printf("FAIL %s: sort %lu %s%s\n", test, first, what(w), note); fails++; }
    else printf("PASS %s: %lu sorts%s\n", test, cases, note);
    selfsorts = 0;
}

/* 1. libwebp 1.6.0's Huffman-tree sort (huffman_encode_utils.c): 16-byte nodes, more
 *    count first, then smaller value; never 0 (the values differ). */
typedef struct { unsigned long total_count; int value; int left, right; } HuffmanTree;
static int CompareHuffmanTrees(const void *ptr1, const void *ptr2)
{
    const HuffmanTree *t1 = ptr1, *t2 = ptr2;
    guard(ptr1, ptr2);
    if (t1->total_count > t2->total_count) return -1;
    else if (t1->total_count < t2->total_count) return 1;
    else return (t1->value < t2->value) ? -1 : 1;
}

static void test_huffman(void)
{
    static HuffmanTree tree[300]; static unsigned long hist[300];
    static const unsigned long two[2] = {1, 5};
    int bad = 0, w = 0, r, k; unsigned long first = 0, cases = 0;
    size_t n, j, i;
    for (k = -1; k < 300 && !bad; k++) {
        if (k < 0) { n = 2; for (j = 0; j < 2; j++) { tree[j].total_count = two[j]; tree[j].value = (int)j; } }
        else {
            size_t hs = k % 3 == 0 ? 280 : k % 3 == 1 ? 256 : 40;
            unsigned long span = 1 + rnd() % 8;      /* few different counts: many the same */
            for (j = 0; j < hs; j++) hist[j] = rnd() % 4 == 0 ? 0 : 1 + rnd() % span;
            for (j = 0, n = 0; j < hs; j++) if (hist[j]) { tree[n].total_count = hist[j]; tree[n].value = (int)j; n++; }
        }
        for (j = 0; j < n; j++) tree[j].left = tree[j].right = -1;
        cases++;
        r = guarded(tree, n, sizeof *tree, CompareHuffmanTrees);
        if (!r)
            for (i = 1; i < n; i++)
                if (tree[i - 1].total_count < tree[i].total_count ||
                    (tree[i - 1].total_count == tree[i].total_count && tree[i - 1].value > tree[i].value)) { r = 8; break; }
        if (r) { bad = 1; w = r; first = cases; }
    }
    result("libwebp Huffman-tree sort", bad, cases, w, first);
}

/* 2. libwebp's palette sort (palette.c): distinct colours, (a < b) ? -1 : 1. */
static int PaletteCompareColorsForQsort(const void *p1, const void *p2)
{
    const unsigned long a = *(const unsigned long *)p1, b = *(const unsigned long *)p2;
    guard(p1, p2);
    return (a < b) ? -1 : 1;
}

static void test_palette(void)
{
    static unsigned long pal[256];
    int bad = 0, w = 0, r, k; unsigned long first = 0, cases = 0;
    size_t n, j, i;
    for (k = 0; k < 200 && !bad; k++) {
        n = 2 + rnd() % 255;
        for (j = 0; j < n; j++) {
            unsigned long c;
            do { c = rnd() & (k & 1 ? 0xffUL : 0xffffffUL); for (i = 0; i < j && pal[i] != c; i++) ; } while (i < j);
            pal[j] = c;
        }
        cases++;
        r = guarded(pal, n, sizeof *pal, PaletteCompareColorsForQsort);
        if (!r) for (i = 1; i < n; i++) if (pal[i - 1] >= pal[i]) { r = 8; break; }
        if (r) { bad = 1; w = r; first = cases; }
    }
    result("libwebp palette sort", bad, cases, w, first);
}

/* 3. Elements of 1, 2, 3, 4, 7, 12, 16 and 33 bytes, every byte of an element its key
 *    (so a broken swap shows), keys random with many the same, sorted, reversed, all
 *    the same and organ pipe; n 0..64, 200 and 1000. A comparison that returns 0 on a
 *    tie (as the C standard expects), then two that never return 0 and one that
 *    answers at random: those need only end, stay inside and keep every element. */
static unsigned char arr[1000 * 33];
static int cmp_mode;
static int cmp_bytes(const void *p, const void *q)
{
    unsigned a = *(const unsigned char *)p, b = *(const unsigned char *)q;
    guard(p, q);
    switch (cmp_mode) {
    case 0: return a < b ? -1 : a > b;
    case 1: return a <= b ? -1 : 1;      /* ties: -1 */
    case 2: return a < b ? -1 : 1;       /* ties: 1, as libwebp */
    default: return (int)(rnd() % 3) - 1;
    }
}

static void test_sizes(void)
{
    static const size_t sizes[8] = {1, 2, 3, 4, 7, 12, 16, 33};
    static const char *names[4] = {"ints, 0 on ties", "never 0, -1 on ties", "never 0, 1 on ties", "random answers"};
    unsigned long before[256], after[256];
    int m, s, pat, bad, w, r; unsigned long first, cases;
    size_t n, j, b;
    char test[64];
    for (m = 0; m < 4; m++) {
        cmp_mode = m; bad = 0; w = 0; first = 0; cases = 0;
        for (s = 0; s < 8; s++)
            for (n = 0; n <= 66; n++)
                for (pat = 0; pat < 5; pat++) {
                    size_t nn = n == 65 ? 200 : n == 66 ? 1000 : n, sz = sizes[s];
                    unsigned span = 1 + (unsigned)(rnd() % 40);
                    if (bad || (nn > 200 && sz > 4)) continue;
                    memset(before, 0, sizeof before);
                    for (j = 0; j < nn; j++) {
                        unsigned k = pat == 0 ? (unsigned)(rnd() % span) : pat == 1 ? (unsigned)(j * 255 / (nn ? nn : 1))
                                   : pat == 2 ? (unsigned)(255 - j * 255 / (nn ? nn : 1)) : pat == 3 ? 7u
                                   : (unsigned)(j < nn / 2 ? j : nn - j) & 0xffu;
                        memset(arr + j * sz, (int)k, sz); before[k & 0xff]++;
                    }
                    cases++;
                    r = guarded(arr, nn, sz, cmp_bytes);
                    if (!r) {
                        memset(after, 0, sizeof after);
                        for (j = 0; j < nn && !r; j++) {
                            for (b = 1; b < sz; b++) if (arr[j * sz + b] != arr[j * sz]) { r = 8; break; }
                            after[arr[j * sz]]++;
                            if (m == 0 && j && arr[j * sz] < arr[(j - 1) * sz]) r = 8;
                        }
                        if (!r && memcmp(before, after, sizeof before)) r = 8;
                    }
                    if (r) { bad = 1; w = r; first = cases; }
                }
        sprintf(test, "%s, %s", m == 0 ? "sorted" : "ends and keeps every element", names[m]);
        result(test, bad, cases, w, first);
    }
}

/* 4. bsearch: every element of a sorted array is found where it is, every key between
 *    them and past both ends is not; n 0..100. */
static int cmp_long(const void *p, const void *q)
{
    long a = *(const long *)p, b = *(const long *)q;
    return a < b ? -1 : a > b;
}

static void *find(long key, const long *v, size_t n)
{
    return (void *)T_BSEARCH(&key, v, n, sizeof *v, cmp_long);
}

static void test_bsearch(void)
{
    static long v[100];
    int bad = 0; unsigned long cases = 0;
    size_t n, j;
    for (n = 0; n <= 100; n++) {
        for (j = 0; j < n; j++) v[j] = (long)(j * 3 + 1);
        for (j = 0; j < n; j++) { cases++; if (find(v[j], v, n) != &v[j]) bad++; }
        for (j = 0; j <= n; j++) { cases++; if (find((long)(j * 3), v, n) != NULL) bad++; }
        cases++; if (find((long)(n * 3 + 2), v, n) != NULL) bad++;
    }
    if (bad) { printf("FAIL bsearch: %d of %lu searches wrong\n", bad, cases); fails++; }
    else printf("PASS bsearch (%lu searches)\n", cases);
}

int main(void)
{
    printf("t20 qsort and bsearch: %s\n", T_NAME);
    test_huffman();
    test_palette();
    test_sizes();
    test_bsearch();
    puts(fails ? "t20 FAILED" : "t20 OK");
    return fails ? 20 : 0;
}
