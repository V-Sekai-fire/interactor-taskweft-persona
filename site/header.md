---
layout: default
title: interactor-taskweft-persona
---

<div id="playground" class="playground" markdown="0">
  <noscript>The playground needs a script. The README below describes the same planner.</noscript>
</div>
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
</style>
<script src="{{ '/assets/playground.js' | relative_url }}" defer></script>
