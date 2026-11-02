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
