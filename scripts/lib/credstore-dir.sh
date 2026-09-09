#!/bin/bash
# Fail-closed ensure/harden of a root-owned, 0700 credential-store
# directory. Never widens permissions: an existing mode is only ever
# masked down toward 0700, never chmod'd up. Refuses symlinks and
# non-directory paths outright rather than following/overwriting them.
harden_credstore_dir() {
  local dir="$1"

  if [ -L "$dir" ]; then
    echo "refusing: $dir is a symlink, not a real directory" >&2
    return 1
  fi

  if [ -e "$dir" ] && [ ! -d "$dir" ]; then
    echo "refusing: $dir exists and is not a directory" >&2
    return 1
  fi

  if [ ! -e "$dir" ]; then
    install -d -m 0700 -o root -g root "$dir"
    return 0
  fi

  local owner group mode masked
  owner="$(stat -c '%U' "$dir")"
  group="$(stat -c '%G' "$dir")"
  if [ "$owner" != "root" ] || [ "$group" != "root" ]; then
    echo "refusing: $dir not owned by root:root (owner=$owner group=$group)" >&2
    return 1
  fi

  mode="$(stat -c '%a' "$dir")"
  masked="$(printf '%03o' "$(( 8#$mode & 8#700 ))")"
  if [ "$mode" != "$masked" ]; then
    chmod "$masked" "$dir"
  fi
  return 0
}
