#!/bin/bash
# Compiles each suite in Tests/ together with the app sources and runs it.
# No Xcode or XCTest required. Each suite runs with an isolated HOME so your
# real preferences and saved shelves are untouched.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/src"
for f in "$ROOT"/Sources/DropShelf/*.swift; do
  case "$(basename "$f")" in
    main.swift) ;;                     # the app entry point would clash
    *) cp "$f" "$WORK/src/" ;;
  esac
done

status=0
for suite in "$ROOT"/Tests/*.swift; do
  name="$(basename "$suite" .swift)"
  echo "──────── $name ────────"
  cp "$suite" "$WORK/main.swift"
  mkdir -p "$WORK/home-$name"
  if ! swiftc -O -target arm64-apple-macosx13.0 \
        "$WORK"/src/*.swift "$WORK/main.swift" -o "$WORK/$name" 2>"$WORK/$name.log"; then
    echo "  COMPILE FAILED:"; grep -E "error" "$WORK/$name.log" | head -10; status=1; continue
  fi
  if HOME="$WORK/home-$name" "$WORK/$name"; then :; else status=1; fi
  echo
done

if [ "$status" -eq 0 ]; then echo "All suites passed."; else echo "Some suites failed."; fi
exit "$status"
