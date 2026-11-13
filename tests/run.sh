#!/bin/sh
# Runs the headless test suite (or the bot soak run with "soak").
# Usage: tests/run.sh [soak]      Needs `godot` on the PATH (or set GODOT=/path/to/godot).
# Prints only FAIL lines and a summary; exits non-zero on failed checks, script errors or zero checks.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GODOT=${GODOT:-godot}
cd "$ROOT" || exit 2

# Global class names need an import pass on a fresh checkout.
if [ ! -d game/.godot ]; then
	"$GODOT" --headless --path game --import >/dev/null 2>&1
fi

if [ "$1" = "soak" ]; then
	"$GODOT" --headless --path game -s "$ROOT/tests/soak.gd" 2>&1
	exit $?
fi

OUT=$("$GODOT" --headless --path game -s "$ROOT/tests/test_sim.gd" 2>&1)
GODOT_EXIT=$?
OUT_NET=$("$GODOT" --headless --path game -s "$ROOT/tests/test_net.gd" 2>&1)
NET_EXIT=$?
OUT=$(printf '%s\n%s' "$OUT" "$OUT_NET")
[ "$NET_EXIT" -gt "$GODOT_EXIT" ] && GODOT_EXIT=$NET_EXIT
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
