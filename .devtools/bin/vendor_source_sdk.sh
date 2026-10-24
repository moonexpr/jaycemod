#!/bin/sh
# Copies the Source SDK 2013 files native/ builds against from a local clone
# (default ~/Repositories/source-sdk-2013) into native/vendor/source-sdk-2013,
# with the SDK's LICENSE and third-party notices its licence requires, and
# records the clone's commit in the folder's COMMIT file.
#   .devtools/bin/vendor_source_sdk.sh [path to the clone]
set -eu
SDK=${1:-$HOME/Repositories/source-sdk-2013}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DEST=$ROOT/native/vendor/source-sdk-2013
FILES="
LICENSE
thirdpartylegalnotices.txt
src/game/server/nav.h
src/game/server/nav_area.h
src/game/server/nav_pathfind.h
src/game/server/tf/nav_mesh/tf_nav_area.h
src/game/server/NextBot/Path/NextBotPath.h
"
for f in $FILES; do
	mkdir -p "$DEST/$(dirname "$f")"
	cp "$SDK/$f" "$DEST/$f"
done
git -C "$SDK" rev-parse HEAD > "$DEST/COMMIT"
echo "vendored $(echo $FILES | wc -w | tr -d ' ') files from $SDK at $(cat "$DEST/COMMIT")"
