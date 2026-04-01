# Philosophy

Derived from the mission: sovereign inference, frontier optimization, research platform.

## Principles

### 1. Economics Before Elegance
Every optimization must justify itself in tokens/second, quality maintenance, or cost reduction. A beautiful technique that doesn't move a metric is research debt, not progress. Measure first, optimize second, ship third.

### 2. Own the Loop
We build a custom inference pipeline — not because NIH, but because the esoteric techniques (early exit, reservoir routing, thermal scheduling) require hooks inside the forward pass that no off-the-shelf server exposes. Control of the inference loop is a strategic requirement, not a preference.

### 3. Experiments Are First-Class
Every non-trivial change to the inference pipeline enters as an interlab campaign with baseline, treatment, metric, and kill criterion. The system must be able to tell you whether a change helped — not just that it ran.

### 4. Fail to Cloud, Not to Silence
When local inference can't handle a task (confidence too low, model too small, thermal pressure), the system escalates to cloud. It never silently degrades quality. The cascade is a feature, not a fallback.

### 5. Privacy Is a Routing Dimension
Code classification (public/internal/sensitive) is a first-class routing signal alongside complexity and latency. Some code must stay local regardless of quality tradeoffs. This is a hard constraint, not a preference.

### 6. Compose, Don't Monolith
Each optimization layer (routing, early exit, cache management, thermal scheduling) is independent and toggleable. They compose naturally but can be disabled individually. An experiment that fails in one layer must not poison another.
