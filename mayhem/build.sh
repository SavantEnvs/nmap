#!/usr/bin/env bash
#
# mayhem/build.sh — build nmap's libFuzzer harnesses (upstream fuzz/fuzz_*.cc, built by upstream's own
# `./configure --enable-fuzzing` + `make build-fuzz`), a standalone reproducer per harness, and the
# project's unit tests (normal flags). Runs in /mayhem as `mayhem`; offline (all libs are bundled or apt).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

HARNESSES="fuzz_dns_packet_parseFromBuffer fuzz_gettcpopt_ts fuzz_hexutils fuzz_ippackethdrinfo fuzz_PacketParser fuzz_traceroute_decode_reply fuzz_validatepkt"
TESTS="nmap_dns_test expr_match_test cstring_unescape_test"
CONF_OPTS="--without-zenmap --without-ndiff --without-nping --without-ncat"

clean_tree() {
  if [ -f Makefile ]; then make distclean >/dev/null 2>&1 || true; fi
}

# 1) Unit tests with the project's NORMAL flags (no sanitizers), stashed in /mayhem for test.sh.
clean_tree
env -u CFLAGS -u CXXFLAGS -u LDFLAGS \
  ./configure CC="$CC" CXX="$CXX" CFLAGS="$COVERAGE_FLAGS" CXXFLAGS="$COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS" $CONF_OPTS
rm -f $(for t in $TESTS; do echo "tests/$t"; done)
make -j"$MAYHEM_JOBS" nmap
make -j"$MAYHEM_JOBS" $(for t in $TESTS; do echo "tests/$t"; done)
for t in $TESTS; do cp "tests/$t" "$SRC/$t"; done

# 2) Sanitized fuzz build through upstream's --enable-fuzzing support.
clean_tree
./configure CC="$CC" CXX="$CXX" \
  CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" CXXFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
  LDFLAGS="$SANITIZER_FLAGS" $CONF_OPTS --enable-fuzzing
rm -f $(for h in $HARNESSES; do echo "fuzz/$h"; done)
make -j"$MAYHEM_JOBS" nmap
make -j"$MAYHEM_JOBS" build-fuzz

# lsan_off + standalone driver (C object so its LLVMFuzzerTestOneInput reference keeps C linkage)
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o /tmp/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o

# Link/compile flags come from upstream's own Makefile variables.
mkvar() { printf 'print-%%:\n\t@echo $($*)\n' | make -s -f Makefile -f - "print-$1"; }
OBJS_ALL="$(mkvar OBJS)"
LIBS_ALL="$(mkvar LIBS)"
LDFLAGS_ALL="$(mkvar LDFLAGS)"

# make deletes the per-harness objects as intermediates; rebuild them for the relinks below
make -j"$MAYHEM_JOBS" $(for h in $HARNESSES; do echo "fuzz/$h.o"; done)
# fuzz_hexutils: our copy (zero-initialised scratch buffer, see the file) replaces upstream's object
$CXX -c $(mkvar CPPFLAGS) $(mkvar CXXFLAGS) "$SRC/mayhem/harnesses/fuzz_hexutils.cc" -o fuzz/fuzz_hexutils.o
for h in $HARNESSES; do
  $CXX $LDFLAGS_ALL $SANITIZER_FLAGS -o "$SRC/$h-standalone" "fuzz/$h.o" /tmp/standalone_main.o /tmp/lsan_off.o $OBJS_ALL $LIBS_ALL
  # relink the libFuzzer binary with the LSan-off hook
  $CXX $LDFLAGS_ALL $LIB_FUZZING_ENGINE -o "$SRC/$h" "fuzz/$h.o" /tmp/lsan_off.o $OBJS_ALL $LIBS_ALL
done
