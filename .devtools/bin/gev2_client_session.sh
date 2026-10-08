#!/usr/bin/env bash
# Game events v2's early client sessions (docs/game-events-v2-plan.md §3 and
# A.6 item 14), each run unattended as one background process.
#
#   gev2_client_session.sh [--dry-run] t1     T1
#   gev2_client_session.sh [--dry-run] t2t4   T2 and T4
#
# t1:   set the sent- markers in wetsand/cl_spectate.lua (include) and
#       features/capture/cl.lua (CompileFile); srcds.py start --map
#       koth_viaduct --no-lua-refresh; the server half of client_t1; rewrite
#       both markers to disk-; gmod_client.py start; the client half.
# t2t4: srcds.py start --map koth_viaduct (refresh on); gmod_client.py start;
#       client_t4 on the server and the client; client_t2 as `base`; then a
#       plain save of features/capture/cl.lua with a save- marker, probed on
#       the connected client and on a relaunched one; the restore (with
#       refresh on, itself a save); a refresh- marker, probed after the save
#       alone, then after lua_refresh_file, then on a relaunched client. Each
#       save is followed by a wait, and each client_t2 result's marker lines
#       (the global the client runs, the text on disk, the cache) are printed,
#       so the disk-marker line tells which text was served.
#
# Run it from the worktree whose tools it should use; the markers go into
# main's files (/Users/jc/Repositories/sandcastle/addon/...), because the
# server loads main through the sandcastle symlink. In the background, e.g.:
#
#   cd /Users/jc/Repositories/sandcastle-gev2-a-tools
#   mkdir -p .devtools/artifacts/gev2-research/client
#   .devtools/bin/gev2_client_session.sh t1 >> .devtools/artifacts/gev2-research/client/session-t1.log 2>&1
#
# (as a background job: Bash's run_in_background, or `nohup ... &`). To end it
# early, `kill -TERM <its pid>`: the current step finishes, then cleanup runs.
#
# Safeguards:
# - Start: no marker set (gev2_marker.py status is empty), no
#   gmod_client.pid, gmod_client.launch or srcds.pid in the artifacts (exit
#   2); `gmod_client.py check` passes (else exit 3). main's `git status
#   --short` and HEAD are saved.
# - Every `gmod_client.py start`, the T2 relaunches included, aborts the
#   session on a non-zero exit; exit 3 (the operator is busy) ends it with 3
#   and is never retried.
# - After every `gmod_client.py stop`, a read-only ps must show no
#   gmod_win64.exe within GONE_WAIT s, else the session aborts (exit 4).
#   Nothing here signals anything; only gmod_client.py closes its client.
# - Cleanup runs once, on exit or on INT, TERM or HUP, with set +e, in this
#   order: gev2_marker.py restore, gmod_client.py stop, srcds.py stop. Then
#   main's status must equal the saved one (A.6 item 14), and if HEAD moved,
#   check_no_markers.py must find no marker line in the new commits. Any
#   problem there exits 4.
# - --dry-run runs the read-only checks for real (marker status, the
#   artifacts, gmod_client.py check, ps, git) and prints every other step
#   instead of running it: it launches, marks and signals nothing.
#
# Exit: 0 done; 1 (or the step's own code) a step failed; 2 usage or a start
# check; 3 the client's preflight refused; 4 a cleanup or end check failed;
# 128+n a signal.
#
# The GEV2_SESSION_* variables below are test seams (test_gev2_client_session.py
# points them at fakes); a real session sets none of them.
set -euo pipefail

readonly USAGE="usage: gev2_client_session.sh [--dry-run] t1|t2t4"
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="${GEV2_SESSION_TOOLS:-$BIN}"
MAIN="${GEV2_SESSION_MAIN:-/Users/jc/Repositories/sandcastle}"
ARTIFACTS="${GEV2_SESSION_ARTIFACTS:-$(cd "$BIN/../.." && pwd)/.devtools/artifacts}"
PS="${GEV2_SESSION_PS:-/bin/ps}"
SETTLE="${GEV2_SESSION_SETTLE:-8}"         # s after each save, for autorefresh to act
GONE_WAIT="${GEV2_SESSION_GONE_WAIT:-30}"  # s for gmod_win64.exe and its launcher to go after stop
export GIT_OPTIONAL_LOCKS=0                # git status never takes main's index.lock

readonly GAMEMODE="$MAIN/addon/gamemodes/sandcastle/gamemode"
readonly SPECTATE="$GAMEMODE/wetsand/cl_spectate.lua"
readonly CAPTURE="$GAMEMODE/features/capture/cl.lua"
readonly CAPTURE_REFRESH="gamemodes/sandcastle/gamemode/features/capture/cl.lua"  # lua_refresh_file's form (research §3)
readonly MAP="koth_viaduct"
readonly CLIENT_OUT="$ARTIFACTS/gev2-research/client"
readonly RECORDS="gmod_client.pid gmod_client.launch srcds.pid"
readonly EXIT_START=2 EXIT_BUSY=3 EXIT_UNSAFE=4

DRY_RUN=0
SESSION=""
STARTED=0
CLEANED=0
STATUS_BEFORE=""
HEAD_BEFORE=""

say() { printf '%s gev2_client_session: %s\n' "$(date -u +%H:%M:%SZ)" "$*"; }
die() { local code=$1; shift; say "ABORT: $*"; exit "$code"; }

tool() { python3 "$TOOLS/$1" "${@:2}"; }

# The command as a shell would take it, without the leading `tool`.
shown() {
  local args=("$@")
  [[ "${args[0]}" == tool ]] && args=("${args[@]:1}")
  local text
  text="$(printf '%q ' "${args[@]}")"
  printf '%s' "${text% }"
}

# A step that launches, marks or stops something: printed, not run, in a dry run.
run() {
  if (( DRY_RUN )); then say "dry-run: would run: $(shown "$@")"; return 0; fi
  say "run: $(shown "$@")"
  "$@"
}

settle() {
  if (( DRY_RUN )); then say "dry-run: would wait $SETTLE s"; return 0; fi
  say "waiting $SETTLE s"
  sleep "$SETTLE"
}

# 0 once a read-only ps shows no gmod_win64.exe, within GONE_WAIT s.
gmod_gone() {
  local waited=0 table found
  while :; do
    table="$("$PS" -axo command=)" || { say "ps failed"; return 1; }
    found="$(printf '%s\n' "$table" | grep -i 'gmod_win64\.exe' || true)"
    [[ -z "$found" ]] && return 0
    if (( waited >= GONE_WAIT )); then
      say "after ${GONE_WAIT} s these still name gmod_win64.exe (nothing here signals them):"
      printf '%s\n' "$found"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

client_start() {
  local rc=0
  run tool gmod_client.py start || rc=$?
  if (( rc == EXIT_BUSY )); then
    die "$EXIT_BUSY" "gmod_client.py start refused (exit 3: the operator's game, a GMod, or no Steam in the bottle); not retried"
  fi
  if (( rc != 0 )); then
    die "$rc" "gmod_client.py start failed (exit $rc); see $CLIENT_OUT/gmod_client.log"
  fi
}

client_stop() {
  run tool gmod_client.py stop || die "$EXIT_UNSAFE" "gmod_client.py stop failed; see $CLIENT_OUT/gmod_client.log"
  gmod_gone || die "$EXIT_UNSAFE" "a gmod_win64.exe still runs after gmod_client.py stop; look before any launch"
}

# The marker lines of one client_t2 result, so the log shows which text was served.
t2_probe() {
  local label=$1 result="$CLIENT_OUT/client_t2-$1.txt"
  run tool gev2_probe.py run --client --label "$label" client_t2
  (( DRY_RUN )) && return 0
  if [[ -f "$result" ]]; then
    grep -E 'WETSAND_T2|in cache' "$result" | sed "s/^/  $label: /" || true
  fi
}

start_checks() {
  local marked name
  marked="$(tool gev2_marker.py status)" || die "$EXIT_START" "gev2_marker.py status failed"
  [[ -z "$marked" ]] || die "$EXIT_START" "markers are set already ($marked); restore them first"
  for name in $RECORDS; do
    [[ ! -e "$ARTIFACTS/$name" ]] || die "$EXIT_START" "$ARTIFACTS/$name exists: an earlier client or server may still be recorded"
  done
  say "check: gmod_client.py check"
  tool gmod_client.py check || die "$EXIT_BUSY" "gmod_client.py check refused a launch; launched nothing"
  STATUS_BEFORE="$(git -C "$MAIN" status --short)" || die "$EXIT_START" "git status failed on $MAIN"
  HEAD_BEFORE="$(git -C "$MAIN" rev-parse HEAD)" || die "$EXIT_START" "git rev-parse failed on $MAIN"
  say "main at $HEAD_BEFORE; its status at the start:"
  printf '%s\n' "${STATUS_BEFORE:-(clean)}"
  STARTED=1
}

# 0 when main's status is unchanged and its new commits, if any, carry no marker line.
end_checks() {
  local status_now head_now problems=0
  status_now="$(git -C "$MAIN" status --short)" || { say "git status failed on $MAIN"; return 1; }
  if [[ "$status_now" != "$STATUS_BEFORE" ]]; then
    say "main's git status changed during the session (before, then now):"
    printf '%s\n' "${STATUS_BEFORE:-(clean)}" "---" "${status_now:-(clean)}"
    problems=$((problems + 1))
  fi
  head_now="$(git -C "$MAIN" rev-parse HEAD)" || { say "git rev-parse failed on $MAIN"; return 1; }
  if [[ "$head_now" != "$HEAD_BEFORE" ]]; then
    say "main moved from $HEAD_BEFORE to $head_now; checking the new commits for marker lines"
    tool check_no_markers.py --repo "$MAIN" range "$HEAD_BEFORE..$head_now" || {
      say "a new commit on main carries a marker line (or git could not tell)"
      problems=$((problems + 1))
    }
  fi
  (( problems == 0 ))
}

cleanup() {
  local rc=$?
  if [[ "${1:-EXIT}" != EXIT ]]; then rc=$((128 + $(kill -l "$1"))); fi
  set +e
  if (( CLEANED )); then exit "$rc"; fi
  CLEANED=1
  trap '' INT TERM HUP  # cleanup is the safeguard: it runs to the end
  local problems=0
  if (( STARTED )); then
    say "cleanup: restore the markers, close the client, stop the server"
    run tool gev2_marker.py restore || { say "gev2_marker.py restore reported problems"; problems=$((problems + 1)); }
    run tool gmod_client.py stop || { say "gmod_client.py stop failed"; problems=$((problems + 1)); }
    gmod_gone || { say "a gmod_win64.exe still runs after gmod_client.py stop"; problems=$((problems + 1)); }
    run tool srcds.py stop || { say "srcds.py stop failed"; problems=$((problems + 1)); }
    end_checks || problems=$((problems + 1))
  fi
  if (( problems > 0 )); then
    say "FAILED: $problems cleanup or end check problem(s); the session exited $rc before cleanup"
    exit "$EXIT_UNSAFE"
  fi
  if (( rc == 0 )); then say "session $SESSION done; cleanup clean"; else say "session $SESSION failed (exit $rc); cleanup clean"; fi
  exit "$rc"
}

session_t1() {
  local nonce=$1
  run tool gev2_marker.py set "$SPECTATE" "WETSAND_T1_INCLUDE = \"sent-$nonce\""
  run tool gev2_marker.py set "$CAPTURE" "WETSAND_T1_COMPILE = \"sent-$nonce\""
  run tool srcds.py start --map "$MAP" --no-lua-refresh
  run tool gev2_probe.py run client_t1
  run tool gev2_marker.py restore
  run tool gev2_marker.py set "$SPECTATE" "WETSAND_T1_INCLUDE = \"disk-$nonce\""
  run tool gev2_marker.py set "$CAPTURE" "WETSAND_T1_COMPILE = \"disk-$nonce\""
  client_start
  run tool gev2_probe.py run --client client_t1
  say "T1: the server sent sent-$nonce, the disk holds disk-$nonce; see $CLIENT_OUT/client_t1.txt"
}

session_t2t4() {
  local nonce=$1
  run tool srcds.py start --map "$MAP"
  client_start
  run tool gev2_probe.py run client_t4
  run tool gev2_probe.py run --client client_t4
  t2_probe base
  # A plain save.
  run tool gev2_marker.py set "$CAPTURE" "WETSAND_T2 = \"save-$nonce\""
  settle
  t2_probe save-connected
  client_stop
  client_start
  t2_probe save-rejoined
  run tool gev2_marker.py restore
  settle  # with refresh on, a restore is itself a save
  t2_probe restored
  # lua_refresh_file, after its own save.
  run tool gev2_marker.py set "$CAPTURE" "WETSAND_T2 = \"refresh-$nonce\""
  settle
  t2_probe refresh-saved
  run tool srcds.py rcon "lua_refresh_file $CAPTURE_REFRESH"
  settle
  t2_probe refresh-connected
  client_stop
  client_start
  t2_probe refresh-rejoined
  say "T2 and T4: see $CLIENT_OUT/client_t2-*.txt and client_t4.txt"
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    t1|t2t4) [[ -z "$SESSION" ]] || { echo "$USAGE"; exit 2; }; SESSION=$1 ;;
    *) echo "$USAGE"; exit 2 ;;
  esac
  shift
done
[[ -n "$SESSION" ]] || { echo "$USAGE"; exit 2; }

trap 'cleanup EXIT' EXIT
trap 'cleanup INT' INT
trap 'cleanup TERM' TERM
trap 'cleanup HUP' HUP

say "session $SESSION from $TOOLS against $MAIN$( (( DRY_RUN )) && echo ' (dry run: launches nothing)')"
start_checks
"session_$SESSION" "$(date -u +%Y%m%dT%H%M%SZ)-$$"
