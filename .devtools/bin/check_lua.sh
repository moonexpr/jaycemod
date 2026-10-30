#!/bin/sh
# Check groups of the test suites (tests/suites.lua, one group a major
# system): compile the groups' Lua files with LuaJIT, then run their tests
# under LuaJIT and again with the native twins (WS_NATIVE=1), and print the
# summed totals; nonzero if any file fails to compile or any test fails.
#
#   check_lua.sh GROUP...    the named groups
#   check_lua.sh --changed   the groups the changes touch (uncommitted,
#                            untracked, and committed since the upstream)
#   check_lua.sh --list      the groups
#   check_lua.sh all         every group (the operator's: an agent's hook
#                            refuses it unless the operator asks)
cd "$(dirname "$0")/../.." || exit 2
SUITES=".devtools/bin/suites.lua"
usage() {
	echo "usage: check_lua.sh GROUP... | --changed | --list | all" >&2
	echo "the groups:" >&2
	luajit "$SUITES" list >&2
	exit 2
}
[ $# -gt 0 ] || usage
case "$1" in
--list) luajit "$SUITES" list; exit 0 ;;
--changed)
	groups=$(luajit "$SUITES" changed) || exit 2
	if [ -z "$groups" ]; then
		echo "no group claims the changed files: nothing to check (name a group to run one)"
		exit 0
	fi
	;;
all) groups=$(luajit "$SUITES" list | awk '{ print $1 }') ;;
-*) usage ;;
*) groups="$*" ;;
esac
# shellcheck disable=SC2086 # the groups are words
files=$(luajit "$SUITES" files $groups) || exit 2
# shellcheck disable=SC2086
tests=$(luajit "$SUITES" tests $groups) || exit 2
echo "groups: $(echo $groups)"
status=0
count=0
for f in $files; do
	count=$((count + 1))
	luajit -b "$f" /dev/null || status=1
done
echo "compiled $count files"
# the native modules the tests check against their Lua oracles (T.native)
(cd native/foundation && cargo build --release --quiet) || status=1
(cd native/wetsands && cargo build --release --quiet) || status=1
# shellcheck disable=SC2086
out=$(.devtools/bin/run_lua_tests.sh $tests 2>&1) || status=1
echo "$out" | grep -E '^FAIL'
# a test file without its summary (it died, or never called T.finish) is missing from the totals: name it
echo "$out" | awk '/^== / { if (file && !summed) print "NO SUMMARY " file; file = substr($0, 4); summed = 0 } / passed, / { summed = 1 } END { if (file && !summed) print "NO SUMMARY " file }'
echo "$out" | awk '/passed/ { p += $1; f += $3 } END { print "TOTAL " p " passed, " f " failed" }'
exit $status
