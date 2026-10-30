#!/usr/bin/env bash
#
# mayhem/test.sh — RUN nmap's own unit tests (tests/*_test.cc, built by mayhem/build.sh with normal
# flags). Each binary prints "Ran N tests. F failures."; a binary that does not print that line
# (crash, no-op, missing) counts as a failure.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

passed=0 ; failed=0
for t in nmap_dns_test expr_match_test cstring_unescape_test; do
  if [ ! -x "$SRC/$t" ]; then
    echo "missing test binary $SRC/$t (build.sh should have produced it)" >&2
    failed=$((failed + 1)) ; continue
  fi
  out="$("$SRC/$t" 2>&1)" ; rc=$?
  echo "$out" | tr '\r' '\n' | grep -v '^[0-9]*$' || true
  line="$(echo "$out" | tr '\r' '\n' | grep -E 'Ran [0-9]+ tests\. [0-9]+ failures\.' | tail -1)"
  if [ -z "$line" ]; then
    echo "$t: no 'Ran N tests' summary" >&2
    failed=$((failed + 1)) ; continue
  fi
  n="$(echo "$line" | sed -E 's/.*Ran ([0-9]+) tests\. ([0-9]+) failures\./\1/')"
  f="$(echo "$line" | sed -E 's/.*Ran ([0-9]+) tests\. ([0-9]+) failures\./\2/')"
  if [ "$n" -eq 0 ]; then failed=$((failed + 1)); continue; fi
  if [ "$rc" -ne 0 ] && [ "$f" -eq 0 ]; then f=1; fi
  passed=$((passed + n - f)) ; failed=$((failed + f))
done

emit_ctrf "nmap-unit-tests" "$passed" "$failed" 0
