# MiniZinc Challenge blocks-world (parked)

`blocks_frontier.mjs` generates random instances of the MiniZinc Challenge 2022 blocks-world model
(`MiniZinc/mzn-challenge`, `2022/blocks-world/blocks.mzn`: n cubes, at most k piles, minimise moves), finds the true
minimum with an independent breadth-first search, and replays a plan against the model's rules.

Result with the breadth-first entry point that PR 17 proposed (closed, since RECTGTN is a backtracking GTN planner):
for n = 3 to 7 on 3 piles, 20 random instances all matched the reference and replayed validly. Cost climbed from about
15 ms at n = 5 to about 4 s at n = 7. The five official instances are 16 cubes on 4 piles.

Next steps are in the issue "MiniZinc Challenge: blocks-world on the GTN blocks methods".
