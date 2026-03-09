# Design Doctrine

> For the full design philosophy (core bets, autonomy model, failure stance, etc.), see [`PHILOSOPHY.md`](../PHILOSOPHY.md).

## Philosophy Decision Filters

Apply these during brainstorming, planning, and code review. Each distills a core bet from PHILOSOPHY.md into a concrete question:

- **Evidence over narrative:** Does this produce a durable receipt? If it didn't produce a receipt, it didn't happen.
- **Earned authority:** Does this assume trust not yet demonstrated? Trust is progressive — don't skip levels.
- **Composition over capability:** Is this a small scoped unit or a monolith? Many small agents with explicit scope beat generalists.
- **Measurement before optimization:** Are we instrumenting first? Having any measurement is vastly better than none.
- **Disagreement is signal:** Are we suppressing useful conflict? Agreement is cheap (consensus bias). Disagreement drives the learning loop.
- **Efficiency = quality:** Does this waste tokens/context? Wasted tokens dilute context, increase hallucination, and slow feedback.
- **Strong defaults, replaceable policy:** Is this a hardcoded behavior or a policy overlay? Opinions are defaults, not mandates.

## Plugin Design Principle

Hooks handle per-file automatic enforcement (zero cooperation needed). Skills handle session-level strategic decisions. Never duplicate the same behavior in both — single enforcement point per concern.

## Philosophy Anti-Patterns

Reject proposals that exhibit these (from PHILOSOPHY.md):

- **Premature abstraction** — cementing wrong patterns is worse than messy scripts. Strangler-fig, never rewrite.
- **Consensus bias** — agreement != correctness. Multi-model diversity is an epistemic hedge.
- **Goodhart optimization** — optimizing a proxy metric that can be gamed. Gate pass rates are gameable; post-merge defect rates are not.
- **Review theater** — review that slows without catching bugs. If gates slow you down more than they catch bugs, they're miscalibrated.
- **Capability hoarding** — one agent doing everything instead of composed small agents. Route to the best model for the job.

## Brainstorming

1. **Check prior art first** — before designing new infrastructure, search `docs/research/assess-*.md` for already-evaluated tools and run a conditional web search for mature open-source alternatives. See `agents/operational-guides.md` for the full prior art pipeline.
2. Start from outcomes and failure modes, not implementation details.
3. Generate at least three options: conservative, balanced, and aggressive.
4. Explicitly call out assumptions, unknowns, and dependency risk across modules.
5. Prefer ideas that improve clarity, reversibility, and operational visibility.

## Planning

1. **Verify no prior art exists** — search assessment docs and existing plugins before writing tasks that build new systems. If a tool has an "adopt" verdict, default to integration over reimplementation.
2. Convert selected direction into small, testable, reversible slices.
3. Define acceptance criteria, verification steps, and rollback path for each slice.
4. Sequence dependencies explicitly and keep integration contracts narrow.
5. Reserve optimization work until correctness and reliability are proven.

## Operational Decision Filters

- Does this reduce ambiguity for future sessions?
- Does this improve reliability without inflating cognitive load?
- Is the change observable, measurable, and easy to verify?
- Can we revert safely if assumptions fail?
