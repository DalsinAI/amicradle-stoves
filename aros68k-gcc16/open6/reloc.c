/*
 * collect-aros, relocatable. AROS's collect-aros runs m68k-aros-ld, -strip, -nm and
 * -objdump by the absolute paths its env.h was given at build time, and takes
 * libpthread.a and static-cxx-cxa-pure-virtual.o from the SDK's lib/ by an absolute
 * path too, so a stove built in one folder still used that folder after it moved.
 * Built with env.h naming the tools without a folder, this finds them from where
 * collect-aros itself is (/proc/self/exe): toolchain/m68k-aros-collect-aros or
 * toolchain/m68k-aros/bin/collect-aros, both mean toolchain/; it puts that folder
 * first on PATH (execvp and popen search it) and takes the SDK's lib/ as
 * toolchain/../sdk/Developer/lib, the stove's layout.
 * MIT, Copyright (c) 2026 AmiCradle Team.
 */
#define _GNU_SOURCE
#include <limits.h>
#include <libgen.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static char tooldir[PATH_MAX];
static char objlibdir[PATH_MAX + 32];

__attribute__((constructor)) static void reloc_init(void)
{
    char exe[PATH_MAX], probe[PATH_MAX + 32];
    ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
    if (n <= 0)
        return;
    exe[n] = 0;
    char *d = dirname(exe);
    snprintf(probe, sizeof probe, "%s/m68k-aros-ld", d);
    if (access(probe, X_OK) == 0)
        snprintf(tooldir, sizeof tooldir, "%s", d);
    else
        snprintf(tooldir, sizeof tooldir, "%s/../..", d);
    snprintf(objlibdir, sizeof objlibdir, "%s/../sdk/Developer/lib", tooldir);
    const char *p = getenv("PATH");
    size_t len = strlen(tooldir) + (p ? strlen(p) : 0) + 2;
    char *np = malloc(len);
    if (!np)
        return;
    snprintf(np, len, "%s%s%s", tooldir, p ? ":" : "", p ? p : "");
    setenv("PATH", np, 1);
    free(np);
}

const char *reloc_objlibdir(void)
{
    return objlibdir;
}
