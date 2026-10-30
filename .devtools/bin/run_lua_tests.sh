#!/bin/sh
# Run the given test files (tests/*_test.lua) under LuaJIT from the repo
# root, then again with the native twins installed (WS_NATIVE=1); nonzero if
# any fail. check_lua.sh hands it a group's tests (tests/suites.lua).
#   run_lua_tests.sh tests/math_box_test.lua ...
cd "$(dirname "$0")/../.." || exit 2
if [ $# -eq 0 ]; then
	echo "usage: run_lua_tests.sh TEST_FILE... (a group's: check_lua.sh GROUP...)" >&2
	exit 2
fi
status=0
for t in "$@"; do
	echo "== $t"
	luajit "$t" || status=1
done
# again with the native twins over the globals, as a server with native/
# loads them: each module's whole suite held against its native twin
for t in "$@"; do
	echo "== native $t"
	WS_NATIVE=1 luajit "$t" || status=1
done
exit $status
