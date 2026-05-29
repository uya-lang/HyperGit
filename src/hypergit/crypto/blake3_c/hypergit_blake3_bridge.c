#include <stddef.h>
#include <stdint.h>

#include "blake3.h"

void hypergit_blake3_digest_c(const uint8_t *input, size_t input_len, uint8_t *out) {
  static const uint8_t zero = 0;
  blake3_hasher hasher;
  blake3_hasher_init(&hasher);
  if (input == NULL) {
    input = &zero;
    input_len = 0;
  }
  blake3_hasher_update(&hasher, input, input_len);
  blake3_hasher_finalize(&hasher, out, BLAKE3_OUT_LEN);
}
