/* occ.c: GFOpenCrypto's own 68k code (src/opencrypto_*.c, much of it 64-bit
 * arithmetic) from fixed inputs, one line per call; host output is the
 * reference. */
#include <string.h>
#include <stdint.h>
#include "gfopencrypto/gfopencrypto.h"

#ifdef HOST
#include <stdio.h>
static void puthex(const unsigned char *p, size_t n) { while (n--) printf("%02x", *p++); }
static void say(const char *s) { fputs(s, stdout); }
#else
void puthex(const unsigned char *p, size_t n);
long write(int fd, const void *b, size_t n);
static void say(const char *s) { write(1, s, strlen(s)); }
#endif

static void line(const char *name, const void *p, size_t n) { say(name); say(" "); puthex(p, n); say("\n"); }
static void digest(const char *name, const void *p, size_t n) { uint8_t h[32]; oc_sha256(p, n, h); line(name, h, 16); }

static uint8_t buf[4096];
static uint8_t pk[OC_SNTRUP761_PK_BYTES], sk[OC_SNTRUP761_SK_BYTES], ct[OC_SNTRUP761_CT_BYTES];

int main(void)
{
    static const uint8_t seed[OC_SEED_BYTES] = "OpenCrypto 68060 known answers.";
    uint8_t out[128], ss1[32], ss2[32];
    int r;

    oc_expand_seed(buf, sizeof buf, seed, "occ-test");
    line("seed", buf, 16);
    oc_sha512(buf, 3001, out); line("sha512", out, 64);
    oc_sha384(buf, 777, out); line("sha384", out, 48);
    { OCSHA512 c; size_t i; oc_sha512_init(&c); for (i = 0; i < 2000; i += 97) oc_sha512_update(&c, buf + i, 97); oc_sha512_final(&c, out); line("sha512inc", out, 64); }
    oc_hmac_sha384(buf, 48, buf + 100, 900, out); line("hmac384", out, 48);
    r = oc_hkdf_sha384(buf, 20, buf + 40, 22, buf + 70, 10, out, 82); (void)r; line("hkdf384", out, 82);
    oc_x25519_base(out, buf + 200); line("x25519base", out, 32);
    r = oc_x25519(out, buf + 232, buf + 264); line("x25519", out, 32); out[0] = (uint8_t)r; line("x25519rc", out, 1);
    { uint8_t sig[64]; memcpy(sig, buf + 300, 64); sig[63] &= 0x0f;
      r = oc_ed25519_verify(sig, buf + 364, buf + 400, 100); out[0] = (uint8_t)r; line("ed25519rc", out, 1); }
    { uint8_t d[300]; memcpy(d, buf + 500, sizeof d);
      oc_chacha20_xor(d, d, sizeof d, buf + 800, buf + 832, 0x0000000100000003ULL); digest("chacha", d, sizeof d);
      oc_poly1305(out, d, sizeof d, buf + 840); line("poly", out, 16); }
    { uint8_t d[256]; memcpy(d, buf + 1000, sizeof d);
      oc_aes(d, sizeof d, buf + 1300, 32, buf + 1340, OC_AES_CTR); digest("aesctr", d, sizeof d);
      oc_aes(d, sizeof d, buf + 1300, 16, buf + 1340, OC_AES_CBC_ENCRYPT); digest("aescbc", d, sizeof d); }
    { static uint8_t n[256], s[256], o[256]; static const uint8_t e[3] = { 1, 0, 1 };
      memcpy(n, buf + 1400, 256); n[0] |= 0xC0; n[255] |= 1; memcpy(s, buf + 1700, 256); s[0] = 0x12;
      r = oc_rsa_public(o, s, n, 256, e, 3); digest("rsa", o, 256); out[0] = (uint8_t)r; line("rsarc", out, 1); }
    r = oc_ecdsa_verify(256, buf + 2000, buf + 2032, buf + 2064, buf + 2096, buf + 2128, 32); out[0] = (uint8_t)r; line("ecdsarc", out, 1);
    oc_sntrup761_keypair(pk, sk, seed); digest("ntrupk", pk, sizeof pk);
    oc_sntrup761_enc(ct, ss1, pk, buf + 2200); digest("ntruct", ct, sizeof ct); line("ntruss1", ss1, 32);
    oc_sntrup761_dec(ss2, ct, sk); line("ntruss2", ss2, 32);
    say("end\n");
    return 0;
}
