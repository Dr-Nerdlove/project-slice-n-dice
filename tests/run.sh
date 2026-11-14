#!/bin/sh
# Runs the headless test suites (or the bot soak run with "soak").
# Usage: tests/run.sh [soak | SUITE...]     SUITE is sim, net, update or view (default: all four).
# Needs `godot` on the PATH (or set GODOT=/path/to/godot).
# GAME_DIR=/path/to/copy runs the tests against a copy of game/ instead of the repository's (the tests stay
# the ones in tests/); TEST_PORT_OFFSET=N moves the localhost ports and the user:// file of the tests by N,
# so several runs can go on at the same time. TEST_STOP_ON_FAIL=1 makes the net suite stop after the first
# failing test group (a speed-up for tests/sabotage.py; the check count is then lower).
# Prints only FAIL lines and a summary; exits non-zero on failed checks, script errors or zero checks.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GODOT=${GODOT:-godot}
GAME=${GAME_DIR:-$ROOT/game}
cd "$ROOT" || exit 2

# Global class names need an import pass on a fresh checkout.
if [ ! -d "$GAME/.godot" ]; then
	"$GODOT" --headless --path "$GAME" --import >/dev/null 2>&1
fi

if [ "$1" = "soak" ]; then
	"$GODOT" --headless --path "$GAME" -s "$ROOT/tests/soak.gd" 2>&1
	exit $?
fi

SUITES=${*:-sim net update view}
OUT=""
GODOT_EXIT=0
for suite in $SUITES; do
	case "$suite" in
		sim | net | update | view) ;;
		*) echo "unknown suite '$suite' (sim, net, update, view, or soak)" >&2; exit 2 ;;
	esac
	O=$("$GODOT" --headless --path "$GAME" -s "$ROOT/tests/test_$suite.gd" 2>&1)
	E=$?
	[ "$E" -gt "$GODOT_EXIT" ] && GODOT_EXIT=$E
	OUT=$(printf '%s\n%s' "$OUT" "$O")
done
PASS=$(printf '%s\n' "$OUT" | grep -c '^PASS')
FAIL=$(printf '%s\n' "$OUT" | grep -c '^FAIL')
printf '%s\n' "$OUT" | grep '^FAIL'
ERR=$(printf '%s\n' "$OUT" | grep -c 'SCRIPT ERROR\|Parse Error\|^ERROR:')
if [ "$ERR" -gt 0 ]; then
	printf '%s\n' "$OUT" | grep -A2 'SCRIPT ERROR\|Parse Error\|^ERROR:' | head -20
fi
echo "checks: $PASS passed, $FAIL failed, $ERR engine errors (godot exit $GODOT_EXIT)"
if [ $((PASS + FAIL)) -eq 0 ] || [ "$FAIL" -gt 0 ] || [ "$ERR" -gt 0 ] || [ "$GODOT_EXIT" -ne 0 ]; then
	exit 1
fi
