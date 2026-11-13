#!/bin/sh
# Sets the app version in every place that holds it, from one number.
# Usage: tools/set-version.sh MAJOR.MINOR.PATCH [SUFFIX]      (a leading "v" is fine)
#   game/project.godot        application/config/version  = "MAJOR.MINOR.PATCH[SUFFIX]"   (what the game shows and
#                                                            compares with the newest release)
#   game/export_presets.cfg   version/name = "MAJOR.MINOR.PATCH"
#                             version/code = MAJOR*10000 + MINOR*100 + PATCH               (Android: must only grow)
# SUFFIX (e.g. "-dev+abc1234") only goes into project.godot, so a dev build is recognisable in the game.
# The release workflow calls this with the git tag; the committed files hold the version of the next release.
set -eu
raw=${1:-}
suffix=${2:-}
v=${raw#v}
case "$v" in
	*[!0-9.]*|""|.*|*.|*..*) echo "Usage: $0 MAJOR.MINOR.PATCH [SUFFIX]" >&2; exit 2 ;;
esac
IFS=. read -r major minor patch extra <<EOF2
$v
EOF2
if [ -z "$patch" ] || [ -n "$extra" ]; then
	echo "Usage: $0 MAJOR.MINOR.PATCH [SUFFIX]" >&2
	exit 2
fi
if [ "$minor" -gt 99 ] || [ "$patch" -gt 99 ]; then
	echo "MINOR and PATCH must be at most 99 (the version code has two digits each)" >&2
	exit 2
fi
code=$((major * 10000 + minor * 100 + patch))
case "$suffix" in
	*[!A-Za-z0-9.+-]*) echo "Bad suffix" >&2; exit 2 ;;
esac
cd "$(dirname "$0")/.."
name="$major.$minor.$patch"
sed -i "s|^config/version=.*|config/version=\"$name$suffix\"|" game/project.godot
sed -i -e "s|^version/name=.*|version/name=\"$name\"|" -e "s|^version/code=.*|version/code=$code|" game/export_presets.cfg
grep -q "^config/version=\"$name$suffix\"\$" game/project.godot
grep -q "^version/code=$code\$" game/export_presets.cfg
echo "Version set to $name$suffix (code $code)"
