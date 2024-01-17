#!/bin/env bash
#set -ex

if [[ -z "$1" ]]; then
  echo "Must provide an image name" >&2
fi

if [[ -n "$2" ]]; then
  declare -a tmpcmd=("$2")
else
  declare -a tmpcmd=("docker" "podman")
fi

for run in "${tmpcmd[@]}"; do
  if type "$run" >/dev/null; then
    cmd="$run"
    break
  fi
done

if [[ -z "$cmd" ]]; then
  echo "Podman or docker must be installed" >&2
fi

img="$1"

tmpdir="$(mktemp -d)"
trap "rm -rf $tmpdir" EXIT

fifo="${tmpdir}/fifo"

$cmd save "$img" \
  | tee "$fifo" \
  | tar vt \
  | while read mode _ _ _ _ file; do 
    if [[ "$file" != *.tar || "$mode" != -* ]]; then
      continue
    fi
    echo ">> $file"
    tar Oxf "$fifo" "$file" 2>/dev/null \
      | tar vt 2>/dev/null
  done
