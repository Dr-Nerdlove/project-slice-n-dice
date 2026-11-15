#!/bin/sh
# Renders the preview pictures (tools/character_preview.gd) on a machine without a display, in a container
# with a virtual screen and a software renderer. Needs Docker and a Linux Godot 4.7.2 binary.
#   tools/render-preview.sh OUT_DIR
# GODOT_BIN: path of the Godot binary (default: the one `godot` on the PATH points to).
# The repository is copied inside the container; nothing in the working tree is changed.
set -eu
out="$(mkdir -p "$1" && cd "$1" && pwd)"
repo="$(cd "$(dirname "$0")/.." && pwd)"
bin="$(readlink -f "${GODOT_BIN:-$(command -v godot)}")"
docker image inspect godot-render:local >/dev/null 2>&1 || docker build -q -t godot-render:local "$repo/tools/render"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp/home \
  -v "$bin:/godot:ro" -v "$repo:/repo:ro" -v "$out:/out" godot-render:local \
  sh -c 'mkdir -p /tmp/home && cp -r /repo/game /repo/tools /tmp/ && cd /tmp &&
    xvfb-run -a -s "-screen 0 1280x576x24" /godot --path /tmp/game --rendering-driver opengl3 \
      --resolution 1280x576 -s ../tools/character_preview.gd -- /out 2>&1 |
    grep -E "SCRIPT ERROR|^ERROR|^   at:" | grep -v -e audio -e "status < 0" || true'
ls "$out"
