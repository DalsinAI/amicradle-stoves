#!/bin/bash
# daletop: rebuilds every program on the open9 list on daletop's open9 os32-gcc16 stove, in the background.
#
#   os32-gcc16/rebuild/run-open9-rebuild.sh [start|status|stop] [--dry-run] [pthread_users.py rebuild options]
#
# start (the default) checks the whole chain first and stops, saying why, on the first thing wrong:
#   this machine is daletop (`hostname -s`); python3, git and a signed-in gh are there; the stove's compiler says
#   16.2.0-open9; the list is there; no rebuild is running already. Then it starts pthread_users.py rebuild under
#   nohup (it keeps going when the terminal closes), writes its pid, and returns. Run it again after a stop or a
#   reboot: repos already built at the same head on the same stove are skipped, so it carries on where it got to.
# status says whether it is running and counts the report's results (built, failed, no-recipe, no-output).
# stop ends a running rebuild (the repo it was on is built again next time).
# --dry-run checks everything and prints the command without starting it.
# Any other options go to pthread_users.py rebuild (for example --only REPO ... or --again).
#
# Paths (daletop's, each can be set in the environment):
#   STOVE   ~/AmiCradle/kitchen/stoves/os32-gcc16            the open9 stove
#   LIST    ~/AmiCradle-dev/scratch/pthread-users/pthread-users.tsv   the scan (195 repos)
#   WORK    ~/AmiCradle-dev/scratch/pthread-rebuild          clones, logs and each repo's out/
#   REPORT  WORK/rebuild-report.tsv, LOG WORK/rebuild.log, PID WORK/rebuild.pid
# Nothing is published: each output stays in WORK/<repo>/out.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
HOST=${REBUILD_HOST:-daletop}
WANT=${REBUILD_RELEASE:-16.2.0-open9}
STOVE=${STOVE:-$HOME/AmiCradle/kitchen/stoves/os32-gcc16}
LIST=${LIST:-$HOME/AmiCradle-dev/scratch/pthread-users/pthread-users.tsv}
WORK=${WORK:-$HOME/AmiCradle-dev/scratch/pthread-rebuild}
REPORT=${REPORT:-$WORK/rebuild-report.tsv}
LOG=${LOG:-$WORK/rebuild.log}
PID=${PID:-$WORK/rebuild.pid}

stop_with() { echo "run-open9-rebuild: $*" >&2; exit 2; }

running() { [ -s "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; }

counts() {
    if [ -s "$REPORT" ]; then
        awk -F'\t' 'NR > 1 { n[$2]++; t++ } END { printf "%d done:", t; for (k in n) printf " %s %d", k, n[k]; print "" }' "$REPORT"
    else
        echo "no report yet ($REPORT)"
    fi
}

ACTION=start
case "${1:-}" in start|status|stop) ACTION=$1; shift ;; esac
DRY=0
ARGS=()
for a in "$@"; do
    if [ "$a" = "--dry-run" ]; then DRY=1; else ARGS+=("$a"); fi
done

[ "$(hostname -s)" = "$HOST" ] || stop_with "this is $(hostname -s), not $HOST: stopped"

case $ACTION in
status)
    if running; then echo "running, pid $(cat "$PID"), log $LOG"; else echo "not running"; fi
    counts
    exit 0 ;;
stop)
    if running; then
        p=$(cat "$PID")
        pkill -TERM -P "$p" 2>/dev/null || true
        kill -TERM "$p"
        echo "stopped pid $p"
    else
        echo "not running"
    fi
    rm -f "$PID"
    exit 0 ;;
esac

for tool in python3 git gh; do
    command -v "$tool" >/dev/null || stop_with "$tool is not installed"
done
gh auth status >/dev/null 2>&1 || stop_with "gh is not signed in (gh auth login)"
GCC="$STOVE/prefix/bin/m68k-amigaos-gcc"
[ -x "$GCC" ] || stop_with "no compiler at $GCC"
VER=$("$GCC" --version | head -1)
case $VER in *"$WANT"*) ;; *) stop_with "the stove says '$VER', not $WANT" ;; esac
[ -s "$LIST" ] || stop_with "no list at $LIST"
[ -f "$HERE/pthread_users.py" ] || stop_with "no pthread_users.py beside this script"
running && stop_with "a rebuild is running already, pid $(cat "$PID") (status / stop)"

CMD=(python3 "$HERE/pthread_users.py" rebuild --stove "$STOVE" --list "$LIST" --work "$WORK" --report "$REPORT" ${ARGS[@]+"${ARGS[@]}"})
echo "stove $STOVE: $VER"
echo "list $LIST: $(($(wc -l < "$LIST") - 1)) repos scanned"
if [ $DRY = 1 ]; then
    printf 'would run:'; printf ' %q' "${CMD[@]}"; echo
    exit 0
fi
mkdir -p "$WORK" "$(dirname "$LOG")" "$(dirname "$PID")"
echo "--- $(date '+%F %T %Z') start" >> "$LOG"
nohup "${CMD[@]}" >> "$LOG" 2>&1 < /dev/null &
echo $! > "$PID"
echo "started, pid $!; log $LOG; report $REPORT"
echo "see how far it got: $0 status"
