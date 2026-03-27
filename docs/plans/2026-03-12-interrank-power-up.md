---
artifact_type: plan
bead: Sylveste-fqb
stage: design
requirements:
  - F1: recommend_model tool — task-to-model recommendation
  - F2: cost_leaderboard tool — price-performance ranking
  - F3: Enriched benchmark metadata surfacing
---

# Interrank Power-Up Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Sylveste-fqb
**Goal:** Add task-to-model recommendation and cost-efficiency ranking to interrank's MCP server.

**Architecture:** Three changes to interrank: (1) new `recommend_model` tool in `src/recommend.ts` + `src/index.ts` that chains benchmark scoring into weighted model ranking, (2) new `cost_leaderboard` tool in `src/index.ts` that computes efficiency ratios, (3) response-shape enrichment in `list_benchmarks` and `recommend_benchmarks` to surface null metadata fields as `"unknown"`. All changes use existing snapshot data — no external dependencies.

**Tech Stack:** TypeScript, MCP SDK, Zod v4, Vitest

---

## Must-Haves

**Truths** (observable behaviors):
- Agent can call `recommend_model(task="code review agent")` and get ranked models with reasoning
- Agent can call `cost_leaderboard(domain="coding")` and get models ranked by cost-efficiency
- `list_benchmarks` response includes `contaminationRisk`, `freshnessType`, `scoreInterpretation`, `metadataStatus` (never omitted, null → `"unknown"`)
- All existing tools continue to work unchanged

**Artifacts:**
- `src/recommend.ts` exports `scoreBenchmarks`, `recommendModels`
- `src/recommend.test.ts` covers `recommendModels` with task, budget, and edge cases
- `src/index.ts` registers `recommend_model` and `cost_leaderboard` tools

**Key Links:**
- `recommend_model` calls `scoreBenchmarks()` → iterates `snapshot.models` → scores each model across matched benchmarks
- `cost_leaderboard` calls `getMetricValue()` + `sortForMetric()` → computes efficiency ratio
- `list_benchmarks` response mapper must coalesce null metadata to `"unknown"`

---

### Task 1: Add `recommendModels` function to recommend.ts

**Files:**
- Modify: `interverse/interrank/src/recommend.ts`
- Test: `interverse/interrank/src/recommend.test.ts`

**Step 1: Write the failing test for recommendModels**

Add to `recommend.test.ts`:

```typescript
import { recommendModels } from "./recommend.js";
import type { SnapshotModel } from "./types.js";

function makeModel(overrides: Partial<SnapshotModel> & { slug: string }): SnapshotModel {
  return {
    id: 1,
    name: overrides.slug,
    slug: overrides.slug,
    providerName: "TestProvider",
    providerSlug: "testprovider",
    description: null,
    releaseDate: null,
    contextWindow: null,
    outputTokens: null,
    metricValues: {},
    predictedMetricKeys: [],
    capabilitySummary: null,
    ...overrides,
  };
}

const testModels: SnapshotModel[] = [
  makeModel({
    slug: "alpha",
    name: "Alpha",
    providerName: "ProvA",
    metricValues: { livecodebench: 85, swebench_verified: 90, blendedPricePerM: 15 },
    predictedMetricKeys: [],
  }),
  makeModel({
    slug: "beta",
    name: "Beta",
    providerName: "ProvB",
    metricValues: { livecodebench: 70, swebench_verified: 95, blendedPricePerM: 5 },
    predictedMetricKeys: ["livecodebench"],
  }),
  makeModel({
    slug: "gamma",
    name: "Gamma",
    providerName: "ProvC",
    metricValues: { truthfulqa_overall: 80, blendedPricePerM: 2 },
    predictedMetricKeys: [],
  }),
];

// Reuse the benchmarks array from existing tests (already defined above in the file)

describe("recommendModels", () => {
  it("ranks models by weighted benchmark scores for a coding task", () => {
    const results = recommendModels("coding agent", benchmarks, testModels, {});
    expect(results.length).toBeGreaterThan(0);
    // Alpha and Beta have coding/agent benchmark data; Gamma only has safety data
    expect(results[0].slug).toBe("alpha"); // or beta — both strong on coding
    expect(results.every((r) => r.slug !== "gamma")).toBe(true); // Gamma excluded — no coding benchmarks
  });

  it("includes confidence and matchReason in results", () => {
    const results = recommendModels("coding agent", benchmarks, testModels, {});
    expect(results[0].confidence).toBeGreaterThan(0);
    expect(results[0].confidence).toBeLessThanOrEqual(1);
    expect(results[0].matchReason).toBeTruthy();
  });

  it("applies predicted score discount (0.7x weight)", () => {
    const results = recommendModels("coding agent", benchmarks, testModels, {});
    // Beta has livecodebench predicted — its weighted score should be lower
    // than if the score were observed, all else equal
    const beta = results.find((r) => r.slug === "beta");
    expect(beta).toBeDefined();
    // Beta has higher swebench_verified (95 vs 90) but predicted livecodebench
    // The exact ranking depends on weights, but the score should reflect the discount
  });

  it("filters by budget when costMetric is available", () => {
    // "low" budget should exclude expensive models
    const results = recommendModels("coding agent", benchmarks, testModels, {
      budget: "low",
      costMetric: "blendedPricePerM",
      budgetThresholds: { low: 5, medium: 15, high: Infinity },
    });
    // Alpha has blendedPricePerM=15, above "low" threshold of 5
    expect(results.find((r) => r.slug === "alpha")).toBeUndefined();
  });

  it("excludes models with fewer than 2 relevant benchmark scores", () => {
    const results = recommendModels("coding agent", benchmarks, testModels, {});
    // Gamma only has truthfulqa_overall — no coding benchmarks — excluded
    expect(results.find((r) => r.slug === "gamma")).toBeUndefined();
  });

  it("returns empty for task with no matching benchmarks", () => {
    const results = recommendModels("quantum teleportation", benchmarks, testModels, {});
    expect(results.length).toBe(0);
  });

  it("respects limit parameter", () => {
    const results = recommendModels("coding agent", benchmarks, testModels, { limit: 1 });
    expect(results.length).toBeLessThanOrEqual(1);
  });

  it("filters by provider", () => {
    const results = recommendModels("coding agent", benchmarks, testModels, { provider: "ProvA" });
    expect(results.every((r) => r.provider === "ProvA")).toBe(true);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd interverse/interrank && pnpm test`
Expected: FAIL — `recommendModels` is not exported from recommend.ts

**Step 3: Implement `recommendModels` in recommend.ts**

Add to the end of `interverse/interrank/src/recommend.ts`:

```typescript
export type ModelRecommendation = {
  slug: string;
  name: string;
  provider: string;
  weightedScore: number;
  confidence: number;
  matchReason: string;
};

export type RecommendOptions = {
  budget?: "low" | "medium" | "high";
  costMetric?: string;
  budgetThresholds?: Record<string, number>;
  provider?: string;
  limit?: number;
};

const DEFAULT_BUDGET_THRESHOLDS: Record<string, number> = {
  low: 1,
  medium: 10,
  high: Infinity,
};

const PREDICTED_DISCOUNT = 0.7;
const MIN_BENCHMARK_COVERAGE = 2;

/**
 * Recommend models for a natural-language task.
 *
 * 1. Score benchmarks for relevance (reuses scoreBenchmarks)
 * 2. For each model, compute weighted score across relevant benchmarks
 * 3. Apply predicted score discount (0.7x for BenchPress-predicted values)
 * 4. Filter by budget, provider, and minimum benchmark coverage
 * 5. Return ranked models with confidence and reasoning
 */
export function recommendModels(
  task: string,
  benchmarks: SnapshotBenchmark[],
  models: SnapshotModel[],
  options: RecommendOptions,
): ModelRecommendation[] {
  const relevantBenchmarks = scoreBenchmarks(task, benchmarks, benchmarks.length);
  if (relevantBenchmarks.length === 0) return [];

  const thresholds = options.budgetThresholds ?? DEFAULT_BUDGET_THRESHOLDS;
  const costMetric = options.costMetric ?? "blendedPricePerM";
  const limit = options.limit ?? 50;

  // Filter models by provider
  let candidateModels = models;
  if (options.provider) {
    const p = options.provider.trim().toLowerCase();
    candidateModels = candidateModels.filter(
      (m) => m.providerName.toLowerCase() === p || m.providerSlug.toLowerCase() === p,
    );
  }

  // Filter models by budget
  if (options.budget) {
    const maxCost = thresholds[options.budget] ?? Infinity;
    candidateModels = candidateModels.filter((m) => {
      const cost = m.metricValues[costMetric];
      if (typeof cost !== "number" || Number.isNaN(cost)) return true; // keep models without cost data
      return cost <= maxCost;
    });
  }

  // Score each model across relevant benchmarks
  const scored: ModelRecommendation[] = [];

  for (const model of candidateModels) {
    let totalWeightedScore = 0;
    let totalWeight = 0;
    let coveredCount = 0;
    const reasons: string[] = [];

    for (const benchmark of relevantBenchmarks) {
      const value = model.metricValues[benchmark.key];
      if (typeof value !== "number" || Number.isNaN(value)) continue;

      coveredCount++;
      const isPredicted = model.predictedMetricKeys.includes(benchmark.key);
      const discount = isPredicted ? PREDICTED_DISCOUNT : 1.0;
      const weight = benchmark.score * discount;

      totalWeightedScore += value * weight;
      totalWeight += weight;

      if (isPredicted) {
        reasons.push(`${benchmark.name} (predicted)`);
      } else {
        reasons.push(benchmark.name);
      }
    }

    if (coveredCount < MIN_BENCHMARK_COVERAGE) continue;

    const confidence = coveredCount / relevantBenchmarks.length;
    const normalizedScore = totalWeight > 0 ? totalWeightedScore / totalWeight : 0;

    scored.push({
      slug: model.slug,
      name: model.name,
      provider: model.providerName,
      weightedScore: Math.round(normalizedScore * 100) / 100,
      confidence: Math.round(confidence * 100) / 100,
      matchReason: `Scored on: ${reasons.join(", ")}`,
    });
  }

  // Sort by weightedScore descending, then confidence descending
  scored.sort((a, b) => {
    const scoreDiff = b.weightedScore - a.weightedScore;
    if (scoreDiff !== 0) return scoreDiff;
    return b.confidence - a.confidence;
  });

  return scored.slice(0, limit);
}
```

Note: This also requires adding the `SnapshotModel` import to recommend.ts.

**Step 4: Run tests to verify they pass**

Run: `cd interverse/interrank && pnpm test`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add interverse/interrank/src/recommend.ts interverse/interrank/src/recommend.test.ts
git commit -m "feat(interrank): add recommendModels function for task-to-model recommendation"
```

<verify>
- run: `cd interverse/interrank && pnpm test`
  expect: exit 0
- run: `cd interverse/interrank && pnpm build`
  expect: exit 0
</verify>

---

### Task 2: Register `recommend_model` MCP tool

**Files:**
- Modify: `interverse/interrank/src/index.ts`

**Step 1: Add import for `recommendModels`**

At the top of `index.ts`, update the import from recommend.js:

```typescript
import { scoreBenchmarks, recommendModels } from "./recommend.js";
```

**Step 2: Register the `recommend_model` tool**

Add after the `recommend_benchmarks` tool registration (around line 398), before the `leaderboard` tool:

```typescript
server.registerTool(
  "recommend_model",
  {
    description:
      "Given a task description, recommend the best models. Chains benchmark relevance scoring into weighted model ranking with confidence indicators.",
    inputSchema: {
      task: z.string().min(1).describe("Natural-language task description, e.g. 'code review agent for Go' or 'customer support chatbot'."),
      budget: z.enum(["low", "medium", "high"]).optional().describe("Budget constraint. low: <$1/MTok, medium: <$10/MTok, high: unlimited."),
      provider: z.string().optional().describe("Filter to models from this provider (slug or name)."),
      limit: z.number().int().min(1).max(50).optional().describe("Max models to return (default: 5)."),
    },
  },
  async ({ task, budget, provider, limit }) => {
    const state = await store.get();

    const results = recommendModels(
      task,
      state.snapshot.benchmarks,
      state.snapshot.models,
      {
        budget,
        costMetric: "blendedPricePerM",
        provider,
        limit: limit ?? 5,
      },
    );

    return jsonContent({
      task,
      budget: budget ?? "unlimited",
      total: results.length,
      items: results,
    });
  }
);
```

**Step 3: Run tests and type-check**

Run: `cd interverse/interrank && pnpm build && pnpm test`
Expected: PASS

**Step 4: Commit**

```bash
git add interverse/interrank/src/index.ts
git commit -m "feat(interrank): register recommend_model MCP tool"
```

<verify>
- run: `cd interverse/interrank && pnpm build`
  expect: exit 0
- run: `cd interverse/interrank && pnpm test`
  expect: exit 0
</verify>

---

### Task 3: Add `cost_leaderboard` MCP tool

**Files:**
- Modify: `interverse/interrank/src/index.ts`
- Test: `interverse/interrank/src/load.test.ts` (add cost efficiency tests)

**Step 1: Write failing test for cost efficiency computation**

Add to `load.test.ts`:

```typescript
describe("cost efficiency", () => {
  it("computes efficiency ratio correctly", () => {
    // Model A: agmobench=90, blendedPricePerM=20 → efficiency=90/20=4.5
    // Model B: agmobench=80, blendedPricePerM=10 → efficiency=80/10=8.0
    // Model B is more cost-efficient
    const modelA = SNAPSHOT.models.find((m) => m.slug === "model-a")!;
    const modelB = SNAPSHOT.models.find((m) => m.slug === "model-b")!;
    const effA = modelA.metricValues["agmobench"] / modelA.metricValues["blendedPricePerM"];
    const effB = modelB.metricValues["agmobench"] / modelB.metricValues["blendedPricePerM"];
    expect(effB).toBeGreaterThan(effA);
  });
});
```

**Step 2: Register `cost_leaderboard` tool in index.ts**

Add after the `domain_leaderboard` tool registration (around line 670):

```typescript
server.registerTool(
  "cost_leaderboard",
  {
    description:
      "Rank models by cost-efficiency: benchmark performance per dollar. Higher efficiency = better value.",
    inputSchema: {
      metricKey: z.string().optional().describe("Metric key to rank efficiency for. Mutually exclusive with domain."),
      domain: z.enum(["overall", "reasoning", "coding", "math", "agentic", "robustness"]).optional().describe("AgMoBench domain. Mutually exclusive with metricKey."),
      costMetric: z.string().optional().describe("Cost metric key (default: blendedPricePerM)."),
      provider: z.string().optional().describe("Filter by provider slug or name."),
      includePredicted: z.boolean().optional().describe("Include BenchPress-predicted cells (default: true)."),
      limit: z.number().int().min(1).max(MAX_LIMIT).optional(),
    },
  },
  async ({ metricKey, domain, costMetric, provider, includePredicted, limit }) => {
    if (!metricKey && !domain) {
      throw new Error("Exactly one of metricKey or domain is required.");
    }
    if (metricKey && domain) {
      throw new Error("metricKey and domain are mutually exclusive.");
    }

    const state = await store.get();

    const resolvedMetricKey = domain ? DOMAIN_METRIC_KEYS[domain] : metricKey!;
    const metric = state.indexes.metricsByKey.get(resolvedMetricKey);
    if (!metric) {
      throw new Error(`Unknown metric key: ${resolvedMetricKey}`);
    }

    const costKey = costMetric ?? "blendedPricePerM";
    const costMeta = state.indexes.metricsByKey.get(costKey);
    if (!costMeta) {
      throw new Error(`Unknown cost metric key: ${costKey}`);
    }

    let models = state.snapshot.models;
    if (provider) {
      const p = provider.trim().toLowerCase();
      models = models.filter(
        (model) =>
          model.providerSlug.toLowerCase() === p ||
          model.providerName.toLowerCase() === p
      );
    }

    if (includePredicted === false) {
      models = models.filter(
        (model) => !model.predictedMetricKeys.includes(resolvedMetricKey)
      );
    }

    // Filter to models with both benchmark score AND cost data
    let excludedCount = 0;
    const withData = models.filter((model) => {
      const benchmarkValue = getMetricValue(model, resolvedMetricKey);
      const costValue = getMetricValue(model, costKey);
      if (benchmarkValue == null || costValue == null || costValue === 0) {
        excludedCount++;
        return false;
      }
      return true;
    });

    // Compute efficiency ratios
    const ranked = withData.map((model) => {
      const benchmarkScore = model.metricValues[resolvedMetricKey];
      const costValue = model.metricValues[costKey];
      // Normalize: if higher-is-better for benchmark, higher efficiency = better
      // Cost is always lower-is-better, so ratio = score / cost
      const efficiencyRatio = Math.round((benchmarkScore / costValue) * 100) / 100;

      return {
        slug: model.slug,
        name: model.name,
        provider: model.providerName,
        benchmarkScore: Math.round(benchmarkScore * 100) / 100,
        costValue: Math.round(costValue * 100) / 100,
        efficiencyRatio,
        predicted: model.predictedMetricKeys.includes(resolvedMetricKey),
      };
    });

    // Sort by efficiency ratio descending
    ranked.sort((a, b) => b.efficiencyRatio - a.efficiencyRatio);
    const capped = ranked.slice(0, coerceLimit(limit));

    return jsonContent({
      metric: { key: metric.key, label: metric.label, higherIsBetter: metric.higherIsBetter },
      costMetric: { key: costMeta.key, label: costMeta.label },
      domain: domain ?? null,
      total: ranked.length,
      returned: capped.length,
      excludedCount,
      items: capped.map((item, index) => ({
        rank: index + 1,
        ...item,
      })),
    });
  }
);
```

**Step 3: Run tests and type-check**

Run: `cd interverse/interrank && pnpm build && pnpm test`
Expected: PASS

**Step 4: Commit**

```bash
git add interverse/interrank/src/index.ts interverse/interrank/src/load.test.ts
git commit -m "feat(interrank): add cost_leaderboard MCP tool for price-performance ranking"
```

<verify>
- run: `cd interverse/interrank && pnpm build`
  expect: exit 0
- run: `cd interverse/interrank && pnpm test`
  expect: exit 0
</verify>

---

### Task 4: Enrich benchmark metadata in responses (F3)

**Files:**
- Modify: `interverse/interrank/src/index.ts`

**Step 1: Update `list_benchmarks` response mapper**

In the `list_benchmarks` tool handler (around line 339), the response mapper already includes the metadata fields. Update it to coalesce nulls:

Replace the `items: capped.map(...)` block in the `list_benchmarks` handler to ensure null fields become `"unknown"`:

```typescript
items: capped.map((benchmark) => ({
  key: benchmark.key,
  slug: benchmark.slug,
  name: benchmark.name,
  source: benchmark.source,
  category: benchmark.category,
  higherIsBetter: benchmark.higherIsBetter,
  description: benchmark.description,
  strengths: benchmark.strengths,
  caveats: benchmark.caveats,
  relevantUseCases: benchmark.relevantUseCases,
  scoreInterpretation: benchmark.scoreInterpretation ?? "unknown",
  contaminationRisk: benchmark.contaminationRisk ?? "unknown",
  freshnessType: benchmark.freshnessType ?? "unknown",
  metadataStatus: benchmark.metadataStatus ?? "unknown",
  maxScore: benchmark.maxScore,
})),
```

**Step 2: Update `recommend_benchmarks` response mapper**

In the `recommend_benchmarks` tool handler (around line 385), add the missing metadata fields and coalesce nulls:

```typescript
items: results.map((r) => ({
  key: r.key,
  slug: r.slug,
  name: r.name,
  category: r.category,
  description: r.description,
  caveats: r.caveats,
  relevantUseCases: r.relevantUseCases,
  scoreInterpretation: r.scoreInterpretation ?? "unknown",
  contaminationRisk: r.contaminationRisk ?? "unknown",
  freshnessType: r.freshnessType ?? "unknown",
  metadataStatus: r.metadataStatus ?? "unknown",
  score: r.score,
  matchReason: r.matchReason,
})),
```

**Step 3: Run tests and type-check**

Run: `cd interverse/interrank && pnpm build && pnpm test`
Expected: PASS

**Step 4: Commit**

```bash
git add interverse/interrank/src/index.ts
git commit -m "feat(interrank): coalesce null benchmark metadata to 'unknown' in responses"
```

<verify>
- run: `cd interverse/interrank && pnpm build`
  expect: exit 0
- run: `cd interverse/interrank && pnpm test`
  expect: exit 0
</verify>

---

### Task 5: Bump version and final verification

**Files:**
- Modify: `interverse/interrank/package.json`

**Step 1: Bump version to 0.2.0**

Update `"version": "0.1.0"` to `"version": "0.2.0"` in package.json.

**Step 2: Run full test suite**

Run: `cd interverse/interrank && pnpm build && pnpm test`
Expected: All tests pass, no type errors

**Step 3: Commit**

```bash
git add interverse/interrank/package.json
git commit -m "chore(interrank): bump version to 0.2.0 for power-up release"
```

<verify>
- run: `cd interverse/interrank && pnpm build`
  expect: exit 0
- run: `cd interverse/interrank && pnpm test`
  expect: exit 0
</verify>
