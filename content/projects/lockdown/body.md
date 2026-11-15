## Overview

Lockdown is a small game built to prove a prototype engine. Rust owns the
simulation; the Bevy engine owns the window, input, camera and rendering.
The same simulation library drives both the playable game and a headless
runner, so anything the game does can be recorded, replayed and inspected
without a display.

## Technical approach

**A deterministic world.** The simulation runs on fixed 60 Hz ticks with
integer state: positions in micrometres, angles in fractions of a turn from
integer trigonometry tables. Every operation is checked, and a tick that
would overflow is rejected and leaves the world unchanged. Floating point
exists only in the view.

**Replay as evidence.** A session is a trace: a starting state, one command
per tick, and the canonical state after each tick. Replay feeds in the
commands alone and compares every tick, field by field, so the first
divergence is reported exactly.

**Gameplay as content.** Scenarios are declarative JSON, and mechanics are
rule packs: typed triggers, bounded conditions and bounded effects, which
cannot run code. A change to the rules is proposed, evaluated against
protected requirements, and only then promoted. An accepted revision is
installed into the *running* game at a tick boundary, without a restart,
and the installation is recorded in the trace.

## Current capabilities

- One unified world with movement, hitscan weapons, typed damage,
  structural failure with debris, electrical pulses, power distribution,
  devices, doors and objectives.
- Byte-for-byte reproducible recordings, verified by headless replay.
- Counterfactual comparison: two runs side by side, reporting the first
  tick at which they diverge.
- A development interface of typed tools, also served over the Model
  Context Protocol, through which a change can be proposed, verified,
  promoted or rolled back.
- Live installation of accepted rule changes into a running session.
- A first-person graybox view.

## Limitations and status

Lockdown is an early prototype, developed in gated phases. The game itself
is a graybox, not a finished game.

- The development interface is exercised by a scripted driver in its
  automated gates. Work on AI-driven authoring and on characters driven by
  a local model is ongoing, and its results so far are mixed.
- The formal gates run on Linux in Docker, with software rendering.

The source repository is not public.
