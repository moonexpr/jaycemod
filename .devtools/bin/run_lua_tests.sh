#!/bin/sh
# Run every tests/*_test.lua under LuaJIT from the repo root, then again
# with the native twins installed (WS_NATIVE=1); nonzero if any fail.
cd "$(dirname "$0")/../.." || exit 2
status=0
for t in tests/*_test.lua; do
	echo "== $t"
	luajit "$t" || status=1
done
# again with the native twins over the globals, as a server with native/
# loads them: each module's whole suite held against its native twin
for t in tests/*_test.lua; do
	echo "== native $t"
	WS_NATIVE=1 luajit "$t" || status=1
done
exit $status
