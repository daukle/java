#!/bin/sh
# Every case is run against a real daukle, because this plugin's output is a
# real compiler's, and a stub of daukle.exec would be testing the stub.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work="$root/test/.work"

daukle=${DAUKLE:-}
if [ -z "$daukle" ]; then
  for candidate in \
    "$root/.daukle/build/daukle" \
    "$root/.daukle/build/daukle.exe" \
    "$root/.daukle/build/Release/daukle.exe" \
    "$root/.daukle/build/Debug/daukle.exe"
  do
    [ -x "$candidate" ] && daukle=$candidate && break
  done
fi
if [ -z "$daukle" ] || [ ! -x "$daukle" ]; then
  echo "no daukle binary: set DAUKLE, or check out daukle/daukle into .daukle and build it" >&2
  exit 1
fi

passed=0
failed=0
skipped=0

fail() {
  echo "FAIL $1: $2" >&2
  failed=$((failed + 1))
}

# This plugin is multi-file, so the whole plugin directory is staged rather
# than the single plugin.lua the other repositories copy.
stage_plugin() {
  mkdir -p "$1/plugins/java"
  cp "$root/plugin.lua" "$1/plugins/java/plugin.lua"
  if [ -d "$root/lib" ]; then
    cp -R "$root/lib" "$1/plugins/java/lib"
  fi
}

run_case() {
  case_dir=$1
  name=$(basename "$case_dir")

  for manifest in "$case_dir"/daukle*.toml; do
    manifest_name=$(basename "$manifest")
    sandbox="$work/$name-$manifest_name"
    rm -rf "$sandbox"
    mkdir -p "$(dirname "$sandbox")"
    cp -R "$case_dir" "$sandbox"
    rm -rf "$sandbox/expected" "$sandbox/expect-error.txt" \
           "$sandbox/task.txt" "$sandbox/produces.txt" \
           "$sandbox/expect-task-error.txt"
    stage_plugin "$sandbox"

    if [ -f "$case_dir/expect-error.txt" ]; then
      if (cd "$sandbox" && "$daukle" sync "$manifest_name" >stdout.txt 2>stderr.txt); then
        fail "$name/$manifest_name" "expected a failure, got success"
        continue
      fi
      clause=$(cat "$case_dir/expect-error.txt")
      if [ -z "$clause" ]; then
        fail "$name/$manifest_name" "the expected-clause file is empty, so this case asserts nothing"
        continue
      fi
      if ! grep -qF "$clause" "$sandbox/stderr.txt" "$sandbox/stdout.txt"; then
        fail "$name/$manifest_name" "message does not carry: $clause"
        continue
      fi
      passed=$((passed + 1))
      continue
    fi

    if [ -f "$case_dir/task.txt" ]; then
      if [ "$manifest_name" != "daukle.toml" ]; then
        fail "$name/$manifest_name" "a task case's manifest must be daukle.toml"
        continue
      fi
      # A task provisions a real JDK, which is a large download. It runs by
      # default only on Linux, where one CI job pays for it and the toolchain
      # cache keeps later runs free; elsewhere it is opt-in.
      if [ "$(uname -s)" != "Linux" ] && [ "${DAUKLE_JAVA_E2E:-}" != "1" ]; then
        echo "skip $name/$manifest_name: set DAUKLE_JAVA_E2E=1 to run it here" >&2
        skipped=$((skipped + 1))
        continue
      fi
      task=$(cat "$case_dir/task.txt")
      if [ -f "$case_dir/expect-task-error.txt" ] && [ -f "$case_dir/produces.txt" ]; then
        fail "$name/$manifest_name" "a case carries both expect-task-error.txt and produces.txt; they are mutually exclusive"
        continue
      fi
      if [ -f "$case_dir/expect-task-error.txt" ]; then
        if (cd "$sandbox" && "$daukle" "$task" >stdout.txt 2>stderr.txt); then
          fail "$name/$manifest_name" "expected task $task to fail, got success"
          continue
        fi
        clause=$(cat "$case_dir/expect-task-error.txt")
        if [ -z "$clause" ]; then
          fail "$name/$manifest_name" "the expected-clause file is empty, so this case asserts nothing"
          continue
        fi
        if ! grep -qF "$clause" "$sandbox/stderr.txt" "$sandbox/stdout.txt"; then
          fail "$name/$manifest_name" "message does not carry: $clause"
          continue
        fi
        passed=$((passed + 1))
        continue
      fi
      if ! (cd "$sandbox" && "$daukle" "$task" >stdout.txt 2>stderr.txt); then
        fail "$name/$manifest_name" "task $task failed"
        sed -n '1,40p' "$sandbox/stderr.txt" >&2
        continue
      fi
      if ! grep -q . "$case_dir/produces.txt"; then
        fail "$name/$manifest_name" "produces.txt lists nothing, so this case asserts nothing"
        continue
      fi
      produced_ok=0
      while IFS= read -r produced || [ -n "$produced" ]; do
        [ -z "$produced" ] && continue
        if [ ! -s "$sandbox/$produced" ]; then
          fail "$name/$manifest_name" "$produced is missing or empty"
          produced_ok=1
        fi
      done < "$case_dir/produces.txt"
      [ "$produced_ok" -eq 0 ] && passed=$((passed + 1))
      continue
    fi

    # Twice, because applying twice must equal applying once for every case,
    # not only for the one a test remembered to say it about.
    if ! (cd "$sandbox" && "$daukle" sync "$manifest_name" >/dev/null 2>&1); then
      fail "$name/$manifest_name" "sync failed"
      continue
    fi
    if ! compare_expected "$case_dir" "$sandbox" "$name/$manifest_name (first)"; then
      continue
    fi
    if ! (cd "$sandbox" && "$daukle" sync "$manifest_name" >/dev/null 2>&1); then
      fail "$name/$manifest_name" "second sync failed"
      continue
    fi
    if ! compare_expected "$case_dir" "$sandbox" "$name/$manifest_name (second)"; then
      continue
    fi
    passed=$((passed + 1))
  done
}

compare_expected() {
  expected_root=$1/expected
  actual_root=$2
  label=$3
  ok=0
  # An empty expected/ would compare nothing and pass, which is the one way a
  # case can look green while asserting nothing at all.
  if [ -z "$(cd "$expected_root" && find . -type f)" ]; then
    fail "$label" "expected/ holds no files, so this case asserts nothing"
    return 1
  fi
  for expected in $(cd "$expected_root" && find . -type f); do
    if ! cmp -s "$expected_root/$expected" "$actual_root/$expected"; then
      fail "$label" "$expected differs"
      diff -u "$expected_root/$expected" "$actual_root/$expected" >&2 || true
      ok=1
    fi
  done
  return $ok
}

rm -rf "$work"
for case_dir in "$root"/test/cases/*/; do
  run_case "${case_dir%/}"
done

echo "$passed passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
