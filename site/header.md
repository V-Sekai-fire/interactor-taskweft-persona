---
layout: default
title: interactor-taskweft-persona
---

<div id="battle" class="battle" markdown="0">
  <noscript>The command battle needs a script.</noscript>
</div>
<hr class="section-rule">
<div id="playground" class="playground" markdown="0">
  <noscript>The playground needs a script. The README below describes the same planner.</noscript>
</div>
<hr class="section-rule">
<style>
  .battle { margin: 0 0 1rem; padding: .6rem .8rem; border: 1px solid #ddd;
    border-left: 5px solid #1a5fb4; background: #f7faff; font: 14px/1.45 system-ui, sans-serif; }
  .bt-title { margin: 0 0 .4rem; padding: 0; border: 0; font-size: 1rem; }
  .bt-run { margin: 0 0 .3rem; font-weight: 600; }
  .bt-row { display: flex; flex-wrap: wrap; gap: .4rem; margin: .3rem 0; }
  .battle button { padding: .3rem .7rem; font: inherit; cursor: pointer; }
  .battle button:disabled { cursor: not-allowed; opacity: .45; }
  .battle button.bt-on, .battle button.bt-persona { background: #1a5fb4; color: #fff; border-color: #1a5fb4; }
  .bt-unit { display: grid; grid-template-columns: 4.5rem 1fr 11rem; gap: .5rem; align-items: center; margin: .2rem 0; }
  .bt-unit.bt-down { opacity: .5; }
  .bt-name { font-weight: 600; }
  .bt-bar { height: .7rem; background: #e3e8ef; border-radius: 3px; overflow: hidden; min-width: 4rem; }
  .bt-fill { display: block; height: 100%; background: #2e8b57; }
  .bt-num { font-variant-numeric: tabular-nums; color: #333; white-space: nowrap; }
  .bt-status { margin: .4rem 0 0; font-weight: 600; }
  .bt-forecast { margin: .2rem 0 0; color: #666; font-size: 13px; }
  .bt-log { margin: .3rem 0 0; padding-left: 1.4rem; max-height: 12rem; overflow: auto; font-size: 13px; }
  .bt-head { display: flex; align-items: center; justify-content: space-between; gap: .5rem; }
  .bt-head .bt-title { margin: 0; }
  .battle button.bt-toggle[aria-pressed="true"] { background: #1a5fb4; color: #fff; border-color: #1a5fb4; }
  .bt-console { margin: .5rem 0 0; }
  .bt-pane { display: block; margin: .5rem 0 .15rem; font-size: 12px; font-weight: 600; color: #444; }
  .bt-console textarea { display: block; width: 100%; box-sizing: border-box; height: 12rem; resize: vertical;
    font: 12px/1.35 Menlo, monospace; white-space: pre; overflow: auto; }
</style>
<style>
  .playground { margin: 0 0 1.5rem; padding: .6rem .8rem; border: 1px solid #ddd;
    border-left: 5px solid #1a5fb4; background: #f7faff; font: 14px/1.45 system-ui, sans-serif; }
  .pg-title { margin: 0 0 .4rem; padding: 0; border: 0; font-size: 1rem; }
  .pg-row { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
  .pg-row select { flex: 1 1 14rem; min-width: 0; max-width: 100%; padding: .3rem; }
  .playground button { padding: .3rem .7rem; font: inherit; cursor: pointer; }
  .playground button[aria-pressed="true"] { background: #1a5fb4; color: #fff; }
  .pg-status { margin: .4rem 0 0; color: #666; font-size: 13px; }
  .pg-refused { color: #c0392b; font-weight: 600; }
  .pg-steps { margin: .3rem 0 0; padding-left: 1.4rem; max-height: 16rem; overflow: auto; }
  .pg-console textarea { width: 100%; box-sizing: border-box; font: 12px/1.35 Menlo, monospace; }
  hr.section-rule { height: 0; margin: 1rem 0; border: 0; border-top: 1px solid #ccd3dd; }
</style>
<script src="{{ '/assets/playground.js' | relative_url }}" defer></script>
<script src="{{ '/assets/battle.js' | relative_url }}" defer></script>
