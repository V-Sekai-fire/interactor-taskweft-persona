#!/usr/bin/env bash
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Assembles the Pages source: the command battle, its domain and first problem, and the WebAssembly
# planner from this repository's latest release.
set -euo pipefail
out="${1:?usage: build.sh <out-dir>}"
rm -rf "$out"
mkdir -p "$out/assets" "$out/samples/domains" "$out/samples/problems"
cp site/_config.yml "$out/"
mkdir -p "$out/_layouts"
cp site/_layouts/default.html "$out/_layouts/"
cp site/404.md "$out/404.md"
cp site/battle.js "$out/assets/battle.js"
cp domains/command-battle.jsonld "$out/samples/domains/"
cp problems/command-battle-round-1.jsonld "$out/samples/problems/"
tag="$(gh release list --repo V-Sekai-fire/interactor-taskweft-persona --limit 1 --json tagName --jq '.[0].tagName')"
gh release download "$tag" --repo V-Sekai-fire/interactor-taskweft-persona --dir "$out/assets" --pattern 'persona.*'
cp site/index.md "$out/index.md"
echo "site source in $out, planner from $tag"
