/* Credential-hash helper called from COBOL: CALL 'LGHASH' USING PW-SALT PW-INPUT OUT-HASH.
 * Computes lowercase-hex SHA-256 of salt(16 bytes) || trimmed password. Built as a shared module
 * and preloaded (COB_PRE_LOAD=lghash). */
#include <openssl/sha.h>
#include <string.h>

void LGHASH(const unsigned char *salt, const unsigned char *password, unsigned char *out) {
  int plen = 64;
  while (plen > 0 && password[plen - 1] == ' ') plen--;
  unsigned char buf[80];
  memcpy(buf, salt, 16);
  memcpy(buf + 16, password, (size_t)plen);
  unsigned char d[SHA256_DIGEST_LENGTH];
  SHA256(buf, (size_t)(16 + plen), d);
  static const char hx[] = "0123456789abcdef";
  for (int i = 0; i < SHA256_DIGEST_LENGTH; i++) {
    out[i * 2]     = (unsigned char)hx[d[i] >> 4];
    out[i * 2 + 1] = (unsigned char)hx[d[i] & 0x0F];
  }
}
