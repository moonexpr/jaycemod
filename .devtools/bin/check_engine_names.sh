#!/bin/sh
# Whether Garry's Mod already defines a console name: searches the strings of
# GMod's binaries (bin/win64/*.dll, garrysmod/bin/*.dll) and its shipped Lua
# (garrysmod/lua, garrysmod/gamemodes) for each name given, whole-word.
#   check_engine_names.sh NAME...   prints "NAME: free" or "NAME: taken (where)"
# Nonzero if any name is taken. GMOD_DIR overrides the install path.
GMOD_DIR=${GMOD_DIR:-"$HOME/Library/Application Support/CrossOver/Bottles/Team Fortress 2/drive_c/Steam/steamapps/common/GarrysMod"}
[ -d "$GMOD_DIR" ] || { echo "no GMod install at $GMOD_DIR" >&2; exit 2; }
strings_file=$(mktemp)
trap 'rm -f "$strings_file"' EXIT
for dll in "$GMOD_DIR"/bin/win64/*.dll "$GMOD_DIR"/garrysmod/bin/*.dll; do
	[ -f "$dll" ] && strings -a "$dll" | sed "s|^|$(basename "$dll"): |"
done > "$strings_file"
status=0
for name in "$@"; do
	where=$(grep -wF -- "$name" "$strings_file" | cut -d: -f1 | sort -u | tr '\n' ' ')
	lua=$(grep -rlwF -- "$name" "$GMOD_DIR/garrysmod/lua" "$GMOD_DIR/garrysmod/gamemodes" 2>/dev/null | head -3 | tr '\n' ' ')
	if [ -z "$where$lua" ]; then
		echo "$name: free"
	else
		echo "$name: taken ($where$lua)"
		status=1
	fi
done
exit $status
