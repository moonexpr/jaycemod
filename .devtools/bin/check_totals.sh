#!/bin/sh
# check_totals.sh BASE: the LuaJIT test total never drops, commit by commit.
#
# For each commit in BASE..HEAD, oldest first, export that commit's tree
# (git archive) to a scratch folder, run the tree's own check_lua.sh, and
# print "sha TOTAL subject". The parent of the first commit is printed first,
# marked (parent). Exit 1 if any commit's passed total is below its first
# parent's, or its check_lua.sh fails; 2 on a usage or git error.
# The working copy is never read: only committed trees are judged.
cd "$(dirname "$0")/../.." || exit 2
base=$1
if [ -z "$base" ]; then
	echo "usage: check_totals.sh BASE" >&2
	exit 2
fi
commits=$(git rev-list --reverse "$base..HEAD") || exit 2
[ -n "$commits" ] || { echo "no commits in $base..HEAD"; exit 0; }

scratch=$(mktemp -d "${TMPDIR:-/tmp}/check_totals.XXXXXX") || exit 2
trap 'rm -rf "$scratch"' EXIT
trap 'exit 2' INT TERM

# total SHA: prints "PASSED STATUS" for that commit's tree, once per commit;
# STATUS is ok, or failed when its check_lua.sh exits nonzero or counts a failure.
total() {
	if [ ! -f "$scratch/$1.total" ]; then
		mkdir "$scratch/$1"
		git archive "$1" | tar -x -C "$scratch/$1" || exit 2
		out=$(sh "$scratch/$1/.devtools/bin/check_lua.sh" all 2>&1)
		code=$?
		line=$(echo "$out" | grep -E '^TOTAL [0-9]+ passed, [0-9]+ failed' | tail -1)
		passed=$(echo "$line" | awk '{ print $2 }')
		failed=$(echo "$line" | awk '{ print $4 }')
		status=ok
		if [ -z "$line" ] || [ "$code" -ne 0 ] || [ "$failed" -ne 0 ]; then status=failed; fi
		echo "${passed:-0} $status" > "$scratch/$1.total"
		rm -rf "${scratch:?}/$1"
	fi
	cat "$scratch/$1.total"
}

# describe SHA TOTAL: "sha TOTAL subject".
describe() {
	echo "$(git log -1 --format=%h "$1") $2 $(git log -1 --format=%s "$1")"
}

first=$(echo "$commits" | head -1)
parent=$(git rev-parse "$first^1") || exit 2
set -- $(total "$parent")
echo "$(describe "$parent" "$1") (parent)"

result=0
for sha in $commits; do
	set -- $(total "$(git rev-parse "$sha^1")")
	before=$1
	set -- $(total "$sha")
	note=""
	if [ "$2" = failed ]; then
		note="  <- check_lua.sh failed"
		result=1
	elif [ "$1" -lt "$before" ]; then
		note="  <- below its parent's $before"
		result=1
	fi
	echo "$(describe "$sha" "$1")$note"
done
exit $result
