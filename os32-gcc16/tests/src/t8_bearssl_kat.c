/* kat.c: drive the BearSSL code GFOpenTLS's builds use, from a fixed
 * seed, and print one line per primitive. The host build is the reference;
 * the m68k builds (-m68040 with and without -m68881) must print the same lines. */
#include <string.h>
#include <stdint.h>
#include "bearssl.h"

#ifdef HOST
#include <stdio.h>
static void puthex(const unsigned char *p, size_t n) { while (n--) printf("%02x", *p++); }
static void say(const char *s) { fputs(s, stdout); }
#else
void puthex(const unsigned char *p, size_t n);
long write(int fd, const void *b, size_t n);
static void say(const char *s) { write(1, s, strlen(s)); }
#endif

static br_hmac_drbg_context rng;
static unsigned char buf[4096], out[512];

static void line(const char *name, const void *p, size_t n)
{
    say(name); say(" "); puthex(p, n); say("\n");
}

static void digest(const char *name, const void *p, size_t n)
{
    br_sha256_context c; unsigned char h[32];
    br_sha256_init(&c); br_sha256_update(&c, p, n); br_sha256_out(&c, h);
    line(name, h, 16);
}

int main(void)
{
    static const unsigned char seed[] = "OpenTLS 68060 GCC 16 known answers";
    size_t i;

    br_hmac_drbg_init(&rng, &br_sha256_vtable, seed, sizeof seed - 1);
    br_hmac_drbg_generate(&rng, buf, sizeof buf);
    line("drbg", buf, 16);

    { br_sha512_context c; br_sha512_init(&c);
      for (i = 0; i < sizeof buf; i += 111) br_sha512_update(&c, buf + i, sizeof buf - i < 111 ? sizeof buf - i : 111);
      br_sha512_out(&c, out); line("sha512", out, 64); }
    { br_sha384_context c; br_sha384_init(&c); br_sha384_update(&c, buf, 1000);
      br_sha384_out(&c, out); line("sha384", out, 48); }
    { br_sha1_context c; br_sha1_init(&c); br_sha1_update(&c, buf, 999);
      br_sha1_out(&c, out); line("sha1", out, 20); }
    { br_md5_context c; br_md5_init(&c); br_md5_update(&c, buf, 998);
      br_md5_out(&c, out); line("md5", out, 16); }

    { br_hmac_key_context kc; br_hmac_context hc;
      br_hmac_key_init(&kc, &br_sha384_vtable, buf, 48);
      br_hmac_init(&hc, &kc, 0); br_hmac_update(&hc, buf + 64, 700);
      br_hmac_out(&hc, out); line("hmac384", out, 48); }
    { br_tls_prf_seed_chunk sc[1]; sc[0].data = buf + 100; sc[0].len = 64;
      br_tls12_sha384_prf(out, 96, buf, 48, "master secret", 1, sc); line("prf384", out, 96);
      br_tls12_sha256_prf(out, 96, buf, 48, "key expansion", 1, sc); line("prf256", out, 96); }

    { br_aes_ct_ctr_keys k; unsigned char d[300];
      memcpy(d, buf + 500, sizeof d);
      br_aes_ct_ctr_init(&k, buf, 32); br_aes_ct_ctr_run(&k, buf + 40, 7, d, sizeof d);
      digest("aesctr", d, sizeof d); }
    { br_aes_ct_cbcenc_keys k; unsigned char d[256], iv[16];
      memcpy(d, buf + 900, sizeof d); memcpy(iv, buf + 64, 16);
      br_aes_ct_cbcenc_init(&k, buf + 32, 16); br_aes_ct_cbcenc_run(&k, iv, d, sizeof d);
      digest("aescbc", d, sizeof d); }
    { unsigned char d[333]; memcpy(d, buf + 1200, sizeof d);
      br_chacha20_ct_run(buf, buf + 32, 1, d, sizeof d); digest("chacha", d, sizeof d); }
    { unsigned char d[200], tag[16]; memcpy(d, buf + 1600, sizeof d);
      br_poly1305_ctmul32_run(buf, buf + 32, d, sizeof d, buf + 2000, 13, tag, br_chacha20_ct_run, 1);
      digest("aead", d, sizeof d); line("poly", tag, 16); }
    { unsigned char y[16]; memset(y, 0, 16);
      br_ghash_ctmul32(y, buf + 16, buf + 2100, 333); line("ghash32", y, 16); }

    { br_ec_private_key sk; br_ec_public_key pk; unsigned char kb[BR_EC_KBUF_PRIV_MAX_SIZE], pb[BR_EC_KBUF_PUB_MAX_SIZE];
      unsigned char G[65], sig[80], h[32]; size_t gl, sl;
      br_ec_keygen(&rng.vtable, &br_ec_all_m15, &sk, kb, BR_EC_secp256r1);
      br_ec_compute_pub(&br_ec_all_m15, &pk, pb, &sk); line("p256pub", pk.q, pk.qlen);
      { const unsigned char *g = br_ec_all_m15.generator(BR_EC_secp256r1, &gl); memcpy(G, g, gl); }
      { unsigned char k[32]; memcpy(k, buf + 3000, 32); k[0] &= 0x7F; br_ec_all_m15.mul(G, gl, k, 32, BR_EC_secp256r1); } line("p256mul", G, gl);
      memcpy(h, buf + 3100, 32); memcpy(sig, buf + 3140, 64); sig[0] &= 0x7F; sig[32] &= 0x7F; sl = 64;
      { unsigned char v = (unsigned char)br_ecdsa_i15_vrfy_raw(&br_ec_all_m15, h, 32, &pk, sig, sl); line("ecdsavrfy", &v, 1); } }
    { unsigned char G[32]; size_t gl;
      { const unsigned char *g = br_ec_c25519_m15.generator(BR_EC_curve25519, &gl); memcpy(G, g, gl); }
      br_ec_c25519_m15.mul(G, gl, buf + 3200, 32, BR_EC_curve25519); line("x25519", G, 32); }

    { static unsigned char n[256], e[3] = { 1, 0, 1 }; br_rsa_public_key pk; unsigned char x[256]; uint32_t ok;
      memcpy(n, buf + 3400, 256); n[0] |= 0xC0; n[255] |= 1;
      pk.n = n; pk.nlen = 256; pk.e = e; pk.elen = 3;
      memcpy(x, buf + 3700, 256); x[0] = 0x12;
      ok = br_rsa_i15_public(x, 256, &pk); digest("rsapub2048", x, 256); { unsigned char ob[4] = { (unsigned char)(ok >> 24), (unsigned char)(ok >> 16), (unsigned char)(ok >> 8), (unsigned char)ok }; line("rsaok", ob, 4); } }

    say("end\n");
    return 0;
}
