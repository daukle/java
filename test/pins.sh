#!/bin/sh
# Every pinned digest, against the .sha256.txt Adoptium publishes beside the
# asset.
#
# The e2e cases provision ONE JDK, because each costs roughly 200 MB. That left
# every other row in lib/jdks.lua asserted by nothing at all, and a transcribed
# digest is exactly the kind of claim this project keeps finding wrong. This
# covers every row for one small GET each. D-112.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
table="$root/lib/jdks.lua"

if [ "${DAUKLE_JAVA_E2E:-}" != "1" ]; then
  echo "skip pins: set DAUKLE_JAVA_E2E=1 to check the pins against Adoptium" >&2
  exit 0
fi

# The table's own spelling is the input, so a row added without a digest cannot
# pass by being skipped: it is not parsed, and the count below then disagrees
# with the number of host rows in the file.
rows=$(sed -n 's/^    \["\([a-z0-9_]*\)\/\([a-z0-9_]*\)"\][ ]*= "\([0-9a-f]\{64\}\)",$/\1 \2 \3/p' "$table")
declared=$(grep -c '^    \["[a-z0-9_]*/[a-z0-9_]*"\]' "$table")
parsed=$(printf '%s\n' "$rows" | grep -c . || true)

if [ "$parsed" -eq 0 ] || [ "$parsed" -ne "$declared" ]; then
  echo "pins: $declared host rows in lib/jdks.lua and $parsed parsed; a row this cannot" \
       "read is a row nothing checks" >&2
  exit 1
fi

# Keyed the way the table is, so a major added to RELEASES without a matching
# DIGESTS block is a parse count mismatch above rather than a silent pass.
majors=$(sed -n 's/^  \["\([0-9]*\)"\] = { full = "\([^"]*\)", underscored = "\([^"]*\)" },$/\1 \2 \3/p' "$table")
major_count=$(printf '%s\n' "$majors" | grep -c . || true)
if [ "$major_count" -eq 0 ]; then
  echo "pins: no release rows parsed out of lib/jdks.lua" >&2
  exit 1
fi

# daukle names the host; Adoptium names the file, and the two disagree on
# x86_64. The same translation the plugin does, kept here deliberately rather
# than shared: a check that reuses the code it checks proves only consistency.
asset_os() {
  case $1 in
    linux) echo linux ;;
    windows) echo windows ;;
    macos) echo mac ;;
    *) echo "" ;;
  esac
}

asset_arch() {
  case $1 in
    x86_64) echo x64 ;;
    aarch64) echo aarch64 ;;
    *) echo "" ;;
  esac
}

asset_ext() {
  case $1 in
    windows) echo zip ;;
    *) echo tar.gz ;;
  esac
}

# Which major a host row belongs to: the rows appear under their major's block,
# so the nearest preceding ["<digits>"] key is the answer.
major_of_line() {
  sed -n "1,${1}p" "$table" | sed -n 's/^  \["\([0-9]*\)"\] = {$/\1/p' | tail -1
}

failed=0
checked=0
old_ifs=$IFS
line=0
# No pipeline: a `while read` fed by one runs in a subshell on every POSIX sh
# and loses the counters, leaving a check that is always green.
IFS='
'
for row in $(grep -n '^    \["[a-z0-9_]*/[a-z0-9_]*"\][ ]*= "[0-9a-f]\{64\}",$' "$table"); do
  IFS=$old_ifs
  line=${row%%:*}
  body=${row#*:}
  host=$(printf '%s' "$body" | sed -n 's/^    \["\([^"]*\)"\].*$/\1/p')
  pinned=$(printf '%s' "$body" | sed -n 's/^.*= "\([0-9a-f]\{64\}\)",$/\1/p')
  os_name=${host%%/*}
  arch=${host##*/}
  major=$(major_of_line "$line")

  full=$(printf '%s\n' "$majors" | awk -v m="$major" '$1 == m { print $2 }')
  underscored=$(printf '%s\n' "$majors" | awk -v m="$major" '$1 == m { print $3 }')
  if [ -z "$full" ] || [ -z "$underscored" ]; then
    echo "FAIL $major $host: no release row for major \"$major\"" >&2
    failed=$((failed + 1))
    IFS='
'
    continue
  fi

  file="OpenJDK${major}U-jdk_$(asset_arch "$arch")_$(asset_os "$os_name")_hotspot_${underscored}.$(asset_ext "$os_name")"
  url="https://github.com/adoptium/temurin${major}-binaries/releases/download/jdk-${full}/${file}.sha256.txt"

  published=$(curl -sSL --fail "$url" 2>/dev/null | awk '{ print $1 }' || true)
  if [ -z "$published" ]; then
    echo "FAIL java $major $host: $url returned nothing" >&2
    failed=$((failed + 1))
  elif [ "$published" != "$pinned" ]; then
    echo "FAIL java $major $host: pinned $pinned, Adoptium publishes $published" >&2
    failed=$((failed + 1))
  else
    checked=$((checked + 1))
  fi
  IFS='
'
done
IFS=$old_ifs

echo "$checked of $declared pinned JDK assets match Adoptium, $failed failed"
[ "$failed" -eq 0 ]
