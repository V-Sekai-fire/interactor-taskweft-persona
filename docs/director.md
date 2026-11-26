# The art director

`Persona/Director.lean` plans how a story beat is staged: the shots in order, from establishing the place and setting the light to the cut that ends the beat. It is a persona domain like the delivery demo, small enough to run in the guest ELF, and it answers with a shot list or a refusal by name.

## The request

    beat=B mood=M [place=same] [light=M]

- `beat`: `calm`, `joke`, `reveal`, `threat` or `hit` (a battle blow).
- `mood`: `dawn`, `day`, `dusk` or `night`, the light the beat is to be seen in.
- `place=same`: the beat happens where the last one did, so the place is already established.
- `light=M`: the light already set. When it equals `mood`, the beat needs no relight.

An unknown beat or mood is refused as `{"refused":"undeclared_goal"}`.

## The answer

    {"beat":"reveal","mood":"night","plan":["light-night","close-up","hold-beat","push-in-reveal","end-beat"],"reached":true}

`end-beat` closes every plan; a player of the shot list can ignore it.

## How it decides

Each beat has a grammar: its shots in the director's order of preference, what each shot needs before it (a close-up needs the place established and lit, a cut needs a held frame) and what the beat needs before it ends. The planner searches that grammar from the request's state, so continuity changes the plan: a beat in the same place has no establishing shot, and a beat already in its light has no relight. The planner's `requires` tests only `variable >= n`, so "not yet established" and "not yet lit" are variables of their own (`unestablished`, `unlit`) that the establishing shot and the light clear.

| Beat | Shots, in order | Needs before it ends |
| --- | --- | --- |
| calm | establish-wide, light, medium-two-shot, hold-long, dissolve | established, lit, framed, held, cut |
| joke | medium-two-shot, hold-beat, smash-cut | framed, held, cut |
| reveal | establish-wide, light, close-up, hold-beat, push-in-reveal | established, lit, framed, held, cut |
| threat | light, low-angle, hold-long, hard-cut | lit, framed, held, cut |
| hit | over-shoulder, impact-frame, reaction-close | framed, held, cut |

## Where it runs

- The guest ELF: `Sandbox.vmcall("director_ask", request)`.
- The browser: `persona_direct(request)` in `persona.mjs`.
- The witness: `lake exe persona_witness` checks a gold answer per beat, continuity, the refusals and a control that changes one shot.
