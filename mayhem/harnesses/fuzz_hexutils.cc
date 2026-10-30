// Port of fuzz/fuzz_hexutils.cc. The only change: the scratch buffer is zero-initialised.
// bintohexstr() writes nothing (not even a NUL) when it has no bytes to render, which is the case for the
// empty input and for every input cstring_unescape() rejects, so the upstream harness hands an
// uninitialised buffer to strlen() in parse_hex_string() and aborts on the first execution.
#include "../../fuzz/common.h"
#include "../../output.h"
#include "../../utils.h"

#include <stddef.h>
#include <stdint.h>

extern "C"
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
  fuzz_init();
  unsigned int newlen = 0;
  char *cbuf = new char[size + 1];
  memcpy(cbuf, data, size);
  cbuf[size] = '\0';
  char *cdata = cstring_unescape(cbuf, &newlen);
  int bufsize = newlen * 4 + newlen / 8 + 1;
  char *buf = new char[bufsize]();

  bintohexstr(buf, bufsize, cdata, (int)newlen);
  size_t phs_len = 0;
  u8 *phs_buf = parse_hex_string(buf, &phs_len);
  if (phs_buf != NULL) {
    volatile std::string safe = protect_xml(std::string((char *)phs_buf, phs_len));
    (void) safe;
  }

  delete[] buf;
  delete[] cbuf;
  return 0;
}
