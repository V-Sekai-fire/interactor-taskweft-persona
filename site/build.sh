#!/usr/bin/env bash
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Assembles the Pages source: the README as the page, the playground, the sample documents, and the
# WebAssembly planner from this repository's latest release.
set -euo pipefail
out="${1:?usage: build.sh <out-dir>}"
rm -rf "$out"
mkdir -p "$out/assets" "$out/samples/domains" "$out/samples/problems" "$out/samples/plans"
cp site/_config.yml "$out/"
cp site/playground.js "$out/assets/playground.js"
cp domains/*.jsonld "$out/samples/domains/"
cp problems/*.jsonld "$out/samples/problems/"
cp plans/*.jsonld "$out/samples/plans/"
tag="$(gh release list --repo V-Sekai-fire/interactor-taskweft-persona --limit 1 --json tagName --jq '.[0].tagName')"
gh release download "$tag" --repo V-Sekai-fire/interactor-taskweft-persona --dir "$out/assets" --pattern 'persona.*'
{ cat site/header.md; echo; cat README.md; } > "$out/index.md"
echo "site source in $out, planner from $tag"
