#!/bin/sh
# Publishes main to the public mirror (moonexpr/sandcastle-public) without
# the material that is not ours to share: both vendor trees (native/vendor,
# gamemode/vendor), the Combine voice pack's WAVs and TF2 Classified's VIP
# HUD materials; and without assistant attribution: commits by Claude are
# John's, and Claude's and Copilot's trailer lines are dropped. The filter
# rewrites the same commits to the same hashes every run, so each push
# fast-forwards the one before; --force replaces the mirror's history, for
# when the filter itself changes. Never add the mirror as a remote of this
# checkout: a push from here carries the whole history.
#   .devtools/bin/publish_public.sh [--force] [remote]
set -eu
FORCE=
if [ "${1:-}" = --force ]; then FORCE=--force; shift; fi
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
REMOTE=${1:-git@github.com:moonexpr/sandcastle-public.git}
EXCLUDED='(^|/)vendor/|\.wav$|(^|/)materials/hud/vip_[^/]*$'
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git clone -q --no-local --single-branch --branch main "$ROOT" "$WORK/public"
cd "$WORK/public"
echo 'John Chandara <john.chandara@icloud.com> Claude <noreply@anthropic.com>' >"$WORK/mailmap"
git filter-repo --force --quiet --invert-paths \
	--path-regex '(^|/)vendor/' \
	--path-regex '\.wav$' \
	--path-regex '(^|/)materials/hud/vip_[^/]*$' \
	--mailmap "$WORK/mailmap" \
	--message-callback '
import re
attribution = re.compile(rb"^(co-authored-by: .*(claude|anthropic|copilot).*|claude-session: .*|.*generated with \[claude code\].*|https://claude\.ai/code/session_\S+)$", re.I)
kept = [line for line in message.split(b"\n") if not attribution.match(line.strip())]
return b"\n".join(kept).rstrip() + b"\n"
'
if git log --name-only --format= | grep -qE "$EXCLUDED"; then
	echo "publish_public.sh: an excluded path survived the filter" >&2
	exit 1
fi
if git log --format='%an %ae %cn %ce%n%B' | grep -qiE 'anthropic\.com|co-authored-by: .*copilot|claude-session:'; then
	echo "publish_public.sh: attribution survived the filter" >&2
	exit 1
fi
git push -q $FORCE "$REMOTE" main
