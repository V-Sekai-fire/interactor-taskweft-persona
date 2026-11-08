# GTPyhop test cases

These test cases are ported from [GTPyhop](https://github.com/PCfVW/GTPyhop), the Python goal-task-network
planner this planner descends from (Dana Nau, University of Maryland, The Clear BSD License, copied
beside this file as `LICENSE.txt`). Each case keeps GTPyhop's domain, its problems and its expected plans.
GTPyhop's actions take parameters and its state is a Python object; here the actions are grounded and the
state is pointer variables, which changes the encoding and not the case.

| Case | GTPyhop source | What it checks |
| --- | --- | --- |
| `backtracking_htn` | `examples/backtracking_htn.py` | Backtracking through several methods and tasks, including into an earlier task after a later one fails |
| `blocks_gtn` | `examples/blocks_gtn/` | The failures and simple successes, the two multigoals and the Sussman anomaly. `m_moveblocks`, GTPyhop's Python that loops over the clear blocks, is a KHR_interactivity graph; the order it visits blocks is the problem's codebook, listed in the order GTPyhop's `state.clear` dictionary has them, since JSON objects are unordered |
| `blocks_htn` | `examples/blocks_htn/` | The same states, failures, simple successes, multigoals and Sussman anomaly as `blocks_gtn`, with the top task named `achieve` as GTPyhop's `blocks_htn` does (a task method, not a multigoal method). Both cases are written by `generate_blocks.py <case>`. They also carry GTPyhop's `goal2a`, `goal2b`, the empty plan after `run_lazy_lookahead` (`goal2b-done`) and `goal3` (nineteen blocks, 38 actions), with plans taken from running GTPyhop 2.0.2 (commit ca6fa8a). Only the `pos` part of a multigoal is encoded; `m_moveblocks` does not read its `clear` and `holding` parts |
| `blocks_hgn` | `examples/blocks_hgn/` | GTPyhop's unigoal methods on `pos` (`m_take`, `m_put`) are the task `pos(x,y)`, with an already-true alternative first, then pickup, unstack, putdown, stack in GTPyhop's order; the multigoal method asks `pos(x,hand)` then `pos(x,destination)`. All 16 recorded problems, including the 50-block `rand50` (164 actions). Problems and plans are read from `recorded/blocks_hgn.json`, which `record.py` wrote by running GTPyhop 2.0.2 with `find_plan` wrapped. A block upstream leaves out of `state.clear` (`rand50` builds it with `range(1,50)`) starts not clear and last in the codebook |
| `blocks_goal_splitting` | `examples/blocks_goal_splitting/` | Unigoal methods `m_move1`, `m_get`, `m_put` on `pos` and `m_make_clear` on `clear` are the tasks `pos(x,y)` and `clear(x)`. GTPyhop's built-in `m_split_multigoal` is the task `split`: it decides at split time which goals are unmet (four block slots at most), achieves those in the multigoal's order, then asks again. Its plans are deliberately longer than `blocks_gtn`'s, and a check asserts that. Only the `pos` part of a multigoal is encoded |
