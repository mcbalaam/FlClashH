#!/usr/bin/env bash
set -euo pipefail

src="${1:?usage: fix_pacman_package.sh <package> <output>}"
out="${2:?usage: fix_pacman_package.sh <package> <output>}"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT

bsdtar -xf "$src" -C "$dir"

# flutter_distributor writes `key=value` and no pkgrel, which current libalpm
# rejects as a missing package name or an invalid version.
awk '
function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
function emit(k, v) {
  k = trim(k)
  v = trim(v)
  if (k == "") return
  if (k == "groups") k = "group"
  else if (k == "depends") k = "depend"
  else if (k == "optdepends") k = "optdepend"
  else if (k == "conflicts") k = "conflict"
  if (v ~ /^\(.*\)$/) {
    v = substr(v, 2, length(v) - 2)
    n = split(v, parts, ",")
    for (i = 1; i <= n; i++) {
      part = trim(parts[i])
      if (part != "") print k " = " part
    }
    return
  }
  print k " = " v
}
/^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
{
  eq = index($0, "=")
  if (eq == 0) { print; next }
  key = substr($0, 1, eq - 1)
  value = substr($0, eq + 1)
  if (key == "pkgver" && value !~ /-[0-9]+$/) value = value "-1"
  emit(key, value)
}
' "$dir/.PKGINFO" >"$dir/.PKGINFO.new"
mv "$dir/.PKGINFO.new" "$dir/.PKGINFO"

# fakeroot makes the installed tree root-owned, which the TUN Helper requires.
fakeroot -- bash -c '
  set -euo pipefail
  cd "$1"
  LANG=C bsdtar -czf .MTREE \
    --format=mtree \
    --options="!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link" \
    .PKGINFO .INSTALL usr opt
  tar --owner=0 --group=0 --numeric-owner -cf - \
    .MTREE .INSTALL .PKGINFO usr opt | xz -z >"$2"
' bash "$dir" "$out"
