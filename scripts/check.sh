#!/bin/bash
# Run by the automatic build on one of GitHub's Macs. Starts the app, then copies and pastes through it
# the way other apps would, and fails the build if anything comes out wrong or out of order.
set -uo pipefail
cd "$(dirname "$0")/.."

APP=build/Multipaste.app/Contents/MacOS/Multipaste
TOOL=build/pbtool
LOG=build/run.log

xcrun swiftc -O scripts/pbtool.swift -o "$TOOL" || exit 1

MULTIPASTE_LOG=1 "$APP" > "$LOG" 2>&1 &
APP_PID=$!
trap 'echo "--- app log ---"; cat "$LOG"; echo "---------------"; kill "$APP_PID" 2>/dev/null' EXIT
sleep 4

failures=0
expect() {
  if [ "$2" == "$3" ]; then
    echo "ok    $1"
  else
    echo "FAIL  $1: wanted [$2] got [$3]"
    failures=$((failures + 1))
  fi
}
copy() { printf '%s' "$1" | pbcopy; sleep "${2:-1}"; }
sha() { shasum -a 256 | cut -d' ' -f1; }
logged() { grep -q "$1" "$LOG" && echo yes || echo no; }
running() { kill -0 "$APP_PID" 2>/dev/null && echo yes || echo no; }

expect "app started" yes "$(logged started)"

echo "# three copies, then three pastes"
copy one; copy two; copy two; copy three
expect "three copies stacked" yes "$(logged 'copied stack=3')"
expect "the same copy twice counts once" no "$(logged 'copied stack=4')"
a=$(pbpaste); sleep 1; b=$(pbpaste); sleep 1; c=$(pbpaste); sleep 1; d=$(pbpaste); sleep 1
expect "pastes come out in the order copied" "one two three" "$a $b $c"
expect "after the last one, paste keeps giving it" three "$d"

echo "# ordinary copy and paste"
copy a; a=$(pbpaste); sleep 1
copy b; b=$(pbpaste); sleep 1
expect "copy, paste, copy, paste" "a b" "$a $b"

echo "# looking at the clipboard without pasting"
copy p1; copy p2
"$TOOL" formats > /dev/null; sleep 1
a=$(pbpaste); sleep 1; b=$(pbpaste); sleep 1
expect "a look is not a paste" "p1 p2" "$a $b"

echo "# at a quick pace"
copy x1 0.4; copy x2 0.4; copy x3 0.6
a=$(pbpaste); sleep 0.5; b=$(pbpaste); sleep 0.5; c=$(pbpaste); sleep 1
expect "half a second apart" "x1 x2 x3" "$a $b $c"

echo "# images"
for n in 1 2 3; do "$TOOL" make-png $((n * 8)) "build/t$n.png"; done
for n in 1 2 3; do "$TOOL" copy-png "build/t$n.png"; sleep 1; done
for n in 1 2 3; do
  got=$("$TOOL" paste-png | sha); sleep 1
  expect "image $n arrives intact, in order" "$(sha < "build/t$n.png")" "$got"
done

echo "# text copied in several formats"
"$TOOL" copy-rich r1; sleep 1; "$TOOL" copy-rich r2; sleep 1
a=$("$TOOL" paste-rich); sleep 1; b=$("$TOOL" paste-rich); sleep 1
expect "one paste that reads two formats counts once" "r1|<b>r1</b> r2|<b>r2</b>" "$a $b"

echo "# all at once"
copy l1; copy l2; copy l3
kill -USR1 "$APP_PID"; sleep 1
expect "text arrives one per line" "$(printf 'l1\nl2\nl3')" "$(pbpaste)"
for n in 1 2 3; do "$TOOL" copy-png "build/t$n.png"; sleep 1; done
kill -USR1 "$APP_PID"; sleep 1
files=$("$TOOL" paste-files)
expect "three images arrive as three files" 3 "$(printf '%s\n' "$files" | grep -c .)"
n=0
while IFS= read -r file; do
  n=$((n + 1))
  expect "file $n is image $n" "$(sha < "build/t$n.png")" "$(sha < "$file")"
done <<< "$files"

echo "# a password manager's copy"
copy s1
"$TOOL" copy-private secret; sleep 1
expect "it is left on the clipboard untouched" secret "$(pbpaste)"
expect "and not kept" yes "$(logged 'left alone')"
copy s2
expect "the next copy starts fresh" s2 "$(pbpaste)"; sleep 1

echo "# quitting"
copy q1; copy q2
expect "still running" yes "$(running)"
kill "$APP_PID"; sleep 2
expect "it quits when asked" no "$(running)"
expect "the clipboard still works afterwards" q2 "$(pbpaste)"

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
