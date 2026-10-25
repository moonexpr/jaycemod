#!/bin/sh
# Compile every Lua file under addons/ with LuaJIT, then run the LuaJIT tests and
# print the summed totals; nonzero if any file fails to compile or any test fails.
cd "$(dirname "$0")/../.." || exit 2
status=0
count=0
for f in $(find addons tests -name '*.lua'); do
	count=$((count + 1))
	luajit -b "$f" /dev/null || status=1
done
echo "compiled $count files"
# the native modules the tests check against their Lua oracles (T.native)
(cd native/foundation && cargo build --release --quiet) || status=1
(cd native/wetsands && cargo build --release --quiet) || status=1
out=$(.devtools/bin/run_lua_tests.sh 2>&1) || status=1
echo "$out" | grep -E '^FAIL'
# a test file without its summary (it died, or never called T.finish) is missing from the totals: name it
echo "$out" | awk '/^== / { if (file && !summed) print "NO SUMMARY " file; file = substr($0, 4); summed = 0 } / passed, / { summed = 1 } END { if (file && !summed) print "NO SUMMARY " file }'
echo "$out" | awk '/passed/ { p += $1; f += $3 } END { print "TOTAL " p " passed, " f " failed" }'
exit $status
