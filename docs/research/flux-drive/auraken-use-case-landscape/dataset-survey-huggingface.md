---
artifact_type: research
bead: sylveste-muf
date: 2026-03-31
topic: HuggingFace dataset survey for lens selection calibration
---

# HuggingFace Dataset Survey: Lens Selection Calibration

Survey of preprocessed datasets from Reddit, StackExchange, advice forums, and related sources for calibrating Auraken's framework selection system (291 lenses across systems dynamics, complexity science, decision science, design thinking, etc.).

## Executive Summary

**Best-in-class sources for Auraken calibration (ranked by coverage and quality):**

1. **open-index/arctic** -- Full Reddit archive (2.1B items, 2005-2026), filterable by subreddit via DuckDB/Parquet. The canonical source for building custom extracts from any target subreddit.
2. **HuggingFaceGECLM/REDDIT_threaded** -- 15.2M threaded conversations from 50 curated subreddits including relationship_advice, personalfinance, philosophy, suggestmeabook, LifeProTips, changemyview, socialskills.
3. **OsamaBsher/AITA-Reddit-Dataset** -- 270K moral dilemma posts with crowd verdicts. Highest-signal labeled dataset for ethical reasoning lens calibration.
4. **kellycyy/daily_dilemmas** -- 1,360 everyday moral dilemmas with 17 topic groups and value taxonomies. Perfect for regression test anchors.
5. **HuggingFaceH4/stack-exchange-preferences** -- 10.8M Q&A pairs from StackExchange with preference scores, filterable by site.
6. **nbertagnolli/counsel-chat** -- 2,780 therapist-answered questions with topic labels. Gold standard for coaching/counseling lens calibration.

**Pushshift status:** Original Pushshift API is restricted to verified Reddit moderators only (since 2023 API controversy). Arctic Shift (open-index/arctic on HuggingFace) is the successor, covering through Feb 2026.

---

## Tier 1: High-Relevance Datasets

### 1. open-index/arctic (Arctic Shift Reddit Archive)

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/open-index/arctic |
| **Size** | 2.1B items (863M comments, 1.2B submissions) / 224 GB |
| **Date range** | 2005-12 through 2026-02 |
| **Format** | Monthly Parquet shards |
| **License** | Other/Permissive (subject to Reddit ToS) |
| **Relevance** | **HIGH** |

**Schema (submissions):** id, author, subreddit, title, selftext, score, created_utc, num_comments, url, over_18, link_flair_text, author_flair_text

**Schema (comments):** id, author, subreddit, body, score, created_utc, link_id, parent_id, distinguished, author_flair_text

**Why it matters:** This is the universal source. Every target subreddit (r/askphilosophy, r/DecisionMaking, r/careerguidance, r/personalfinance, r/relationships, r/ADHD, r/Stoicism, r/BuyItForLife, r/buildapc, r/suggestmeabook, etc.) can be extracted via DuckDB queries against Parquet files without downloading the full archive. Monthly shards allow date-range filtering.

**Filtering example:**
```sql
SELECT title, selftext, score, num_comments
FROM read_parquet('hf://datasets/open-index/arctic/data/submissions/2024/**/*.parquet')
WHERE subreddit IN ('askphilosophy', 'DecisionMaking', 'careerguidance', 'personalfinance')
  AND score > 5
  AND length(selftext) > 100
```

**Quality issues:** Raw dumps -- no deduplication, includes deleted/removed posts (selftext = "[removed]"), bot posts, low-effort content. Needs aggressive filtering by score, selftext length, and removal of meta-posts.

**Auraken calibration use:** Build custom extracts for every target domain. Primary source for coverage index analysis. Extract high-upvote posts from each target subreddit to build domain-stratified test sets.

---

### 2. HuggingFaceGECLM/REDDIT_threaded

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/HuggingFaceGECLM/REDDIT_threaded |
| **Size** | 15.2M threaded conversations across 50 subreddits |
| **License** | Undefined |
| **Relevance** | **HIGH** |

**Schema:** start_date, end_date, thread_id, subreddit, subreddit_id, total_score, text (full thread), num_messages, avg_score

**Key subreddits with row counts:**
- relationship_advice: 1.55M
- personalfinance: 848K
- buildapc: 1.89M
- explainlikeimfive: 653K
- suggestmeabook: 175K
- LifeProTips: 237K
- philosophy: 44.8K
- changemyview: 135K
- socialskills: 103K
- IWantToLearn: 42.9K

**Why it matters:** Pre-threaded conversations (question + responses collapsed into single text field) are exactly what Auraken needs -- the full context a user might provide, plus how others responded. The `num_messages` and `avg_score` fields enable quality filtering. 50 subreddits span decision-making, relationships, finance, self-improvement, and product recommendations.

**Quality issues:** Thread text is concatenated into a single field -- may need parsing to separate OP from responses. No individual comment scores within threads.

**Auraken calibration use:** Primary source for context-depth gating calibration. Thread length (num_messages) directly maps to "how much context before lens recommendations become useful." Coverage index across 50 subreddits for domain breadth testing.

---

### 3. HuggingFaceGECLM/REDDIT_comments

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/HuggingFaceGECLM/REDDIT_comments |
| **Size** | 592M comments across 50 subreddits / 109 GB |
| **Date range** | 2006 to Jan 2023 |
| **License** | Undefined |
| **Relevance** | **HIGH** |

**Schema (22 fields):** body, author, created_utc, score, subreddit_name_prefixed, link_id, parent_id, permalink, controversiality, gilded, total_awards_received, etc.

**Key subreddits:** relationship_advice (38.9M), LifeProTips (12.8M), changemyview (11.6M), buildapc (21.8M), books (10.2M), and 45 more.

**Why it matters:** Individual comments with scores, controversiality flags, and threading info. Complements the threaded dataset by allowing finer-grained analysis of which response types match which problem types.

**Quality issues:** Needs anonymization (contains usernames). Raw comment text includes Reddit formatting, links, bot responses.

---

### 4. OsamaBsher/AITA-Reddit-Dataset

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/OsamaBsher/AITA-Reddit-Dataset |
| **Size** | 270,709 posts |
| **Date range** | 2013 to April 2023 |
| **License** | Not specified |
| **Relevance** | **HIGH** |

**Schema:** id, title, text (38-29.7K chars), verdict (NTA/YTA/ESH/NAH), comment1, comment2, score (0-81K)

**Why it matters:** The r/AmITheAsshole subreddit is a rich source of interpersonal dilemmas with crowd-sourced moral judgments. The verdict labels (NTA, YTA, ESH, NAH) provide a natural taxonomy for ethical reasoning lens calibration. Each post describes a real-world scenario involving relationships, workplace, family, or social dynamics -- exactly the domains where Auraken's lenses should differentiate.

**Quality issues:** Verdict distribution is skewed toward NTA. Some posts are creative writing exercises. The two comments may not represent the full range of perspectives.

**Auraken calibration use:** Near-miss scenario discovery (ESH and NAH cases often require multiple competing lenses). Regression test anchors for ethical reasoning lenses. Context-depth gating (short vs. long posts).

---

### 5. kellycyy/daily_dilemmas

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/kellycyy/daily_dilemmas |
| **Size** | 1,360 dilemmas / 2,720 rows (2 actions per dilemma) |
| **License** | CC-BY-4.0 |
| **Relevance** | **HIGH** |

**Schema:** dilemma_idx, basic_situation, dilemma_situation, action_type (to_do/not_to_do), action, negative_consequence, values_aggregated, topic (0-58), topic_group (17 categories)

**17 topic groups:** Workplace, Family, Close Relationships, Committed Relationships, School, Young People, Pregnancy, Personal/Career, Crime/Addiction, Self-Image/Social, Wildlife/Environment, Religion/Custom, Business/Organization, Friend, Daily Life, Special Events, Role/Duty/Responsibility

**Why it matters:** Pre-labeled with a rich taxonomy of dilemma types, affected parties, and human values. The 17 topic groups map directly to Auraken's domain coverage requirements. Values taxonomy (301 entries) enables value-to-lens mapping validation.

**Quality issues:** Relatively small (1,360 dilemmas). Scenarios are curated/synthetic rather than organic user questions.

**Auraken calibration use:** Primary anchor scenario suite for regression testing. Topic group taxonomy as seed for coverage index. Values-to-lens mapping validation.

---

### 6. nbertagnolli/counsel-chat

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/nbertagnolli/counsel-chat |
| **Size** | 2,780 Q&A pairs |
| **License** | Not specified |
| **Relevance** | **HIGH** |

**Schema:** questionID, questionTitle, questionText, questionLink, topic, therapistInfo, therapistURL, answerText, upvotes (0-12), views (1-16,700)

**Topic categories include:** depression, anxiety, trauma, self-esteem, relationships, and other counseling domains.

**Why it matters:** Real questions from real people answered by licensed therapists, with topic labels. This is the gold standard for validating that Auraken's coaching/counseling lenses activate appropriately. The topic labels provide ground truth for topic-to-lens mapping.

**Quality issues:** Small dataset. Topic label granularity may not match Auraken's lens granularity.

---

### 7. HuggingFaceH4/stack-exchange-preferences

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/HuggingFaceH4/stack-exchange-preferences |
| **Size** | 10.8M Q&A pairs / 22 GB |
| **License** | CC-BY-SA 4.0 |
| **Relevance** | **HIGH** |

**Schema:** qid, question (18-48.3K chars), answers (array with answer_id, author, pm_score, selected, text), date, metadata

**Sites included:** All English-language StackExchange sites (excluding Spanish, Japanese, Portuguese, Russian). This includes Workplace, Interpersonal Skills, Philosophy, and 170+ other communities.

**Filtering:** The metadata field includes site information. Filter for `workplace.stackexchange.com`, `interpersonal.stackexchange.com`, `philosophy.stackexchange.com`.

**Why it matters:** StackExchange questions are more structured than Reddit posts, with accepted answers and vote-based ranking. Workplace SE and Interpersonal Skills SE contain exactly the kind of professional/social dilemmas where systems-thinking frameworks are valuable.

**Quality issues:** Preference scores are derived (log2 formula), not raw community votes. Filtering by site requires examining metadata.

---

### 8. common-pile/stackexchange

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/common-pile/stackexchange |
| **Size** | ~30.4M rows |
| **License** | CC-BY-SA 3.0 / CC-BY-SA 4.0 (per-document) |
| **Relevance** | **HIGH** |

**Schema:** id, text (full Q&A thread), source, added, created, metadata (license, site, url, authors, sort, include_comments)

**Filtering:** `metadata.site` field contains the SE domain. Filter for `workplace.stackexchange.com`, `interpersonal.stackexchange.com`, `philosophy.stackexchange.com`.

**Why it matters:** More recent than H4 dataset (includes data through Dec 2024). Thread format (question + all answers + comments as single document) mirrors how Auraken would receive context. Per-document licensing is clean.

**Quality issues:** Requires parsing the combined text field to separate question from answers.

---

## Tier 2: Medium-Relevance Datasets

### 9. Akhil-Theerthala/Personal-Finance-Queries

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/Akhil-Theerthala/Personal-Finance-Queries |
| **Size** | 20,000 rows |
| **License** | MIT |
| **Relevance** | **MEDIUM** |

**Schema:** category (8 classes), subreddit, query, answer

**Categories:** Debt Management & Credit, Estate Planning & Legacy, Investing & Wealth Building, Insurance & Risk Management, Retirement Planning, Budgeting & Cash Flow Management, Savings & Emergency Funds, FinancialPlanning

**Why it matters:** Pre-categorized personal finance questions with LLM-filtered quality. The 8 categories provide a ready-made taxonomy for financial lens calibration.

**Quality issues:** LLM-filtered (potential bias). Only 20K rows. Answers may be LLM-generated.

---

### 10. Amod/mental_health_counseling_conversations

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/Amod/mental_health_counseling_conversations |
| **Size** | 3,510 Q&A pairs |
| **License** | RAIL-D (Responsible AI License) |
| **Relevance** | **MEDIUM** |

**Schema:** Context (client question, 25-2,700 chars), Response (counselor response, 0-32,700 chars)

**Why it matters:** Real counseling conversations between clients and licensed professionals. Useful for validating that Auraken's empathy/emotional reasoning lenses activate correctly.

**Quality issues:** Small. No topic labels (unlike counsel-chat). RAIL-D license may restrict some uses.

---

### 11. solomonk/reddit_mental_health_posts

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/solomonk/reddit_mental_health_posts |
| **Size** | 151,000 posts |
| **License** | Not specified |
| **Relevance** | **MEDIUM** |

**Schema:** author, body, created_utc, id, num_comments, score, subreddit, title, upvote_ratio, url

**Subreddits:** r/adhd, r/aspergers, r/depression, r/ocd, r/ptsd

**Why it matters:** Neurodivergent problem-solving patterns. Posts from r/adhd and r/aspergers contain problem descriptions that require different cognitive frameworks than neurotypical advice-seeking. Useful for testing whether Auraken's lenses handle neurodivergent contexts appropriately.

**Quality issues:** No responses/answers included -- posts only.

---

### 12. Peraboom/ADHD_Related_Concerns

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/Peraboom/ADHD_Related_Concerns |
| **Size** | 37,100 posts |
| **License** | Other |
| **Relevance** | **MEDIUM** |

**Schema:** author, body, created_utc, id, num_comments, score, subreddit, title, upvote_ratio, url

**Subreddit:** r/ADHD only

**Why it matters:** ADHD-specific problem descriptions for neurodivergent lens calibration.

---

### 13. Manel/Reddit_Stoicism_QA_610

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/Manel/Reddit_Stoicism_QA_610 |
| **Size** | 610 Q&A pairs |
| **License** | MIT |
| **Relevance** | **MEDIUM** |

**Schema:** instruction (question), response (answer), titles, context (unused), category (all "general_qa")

**Why it matters:** r/Stoicism questions with answers. Users applying philosophical frameworks to real problems -- directly analogous to what Auraken does. Good for validating that Stoic/philosophical lenses activate correctly.

**Quality issues:** Very small (610 rows). Single category label.

---

### 14. Oguzz07/reddit-advice-dataset

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/Oguzz07/reddit-advice-dataset |
| **Size** | 886 rows |
| **License** | Not specified |
| **Relevance** | **MEDIUM** |

**Schema:** instruction (advice request), response (advice given)

**Source:** r/Advice

**Quality issues:** Extremely small. Instruction-response format loses metadata.

---

### 15. McAuley-Lab/Amazon-Reviews-2023

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/McAuley-Lab/Amazon-Reviews-2023 |
| **Size** | 571.5M reviews, 54.5M users, 48.2M items |
| **Date range** | May 1996 to Sept 2023 |
| **License** | Not specified |
| **Relevance** | **MEDIUM** |

**Schema (reviews):** rating, title, text, images, asin, parent_asin, user_id, timestamp, verified_purchase, helpful_vote

**Schema (metadata):** main_category (33 categories), title, average_rating, rating_number, features, description, price, categories, details, bought_together

**Why it matters:** For the product recommendation / discovery domain. The 33 categories and "bought_together" links can calibrate recommendation-oriented lenses. The reviews with "helpful_vote" counts identify situations where users articulate decision criteria.

**Quality issues:** Massive -- needs aggressive filtering to extract decision-relevant reviews (those describing tradeoffs, comparisons, use-case reasoning). Most reviews are simple ratings, not decision narratives.

---

### 16. Psychotherapy-LLM/PsychoCounsel-Preference

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/Psychotherapy-LLM/PsychoCounsel-Preference |
| **Size** | 36,700 rows |
| **License** | CC-BY-NC-4.0 |
| **Relevance** | **MEDIUM** |

**Schema:** question, chosen (preferred response), rejected (non-preferred), chosen_model, rejected_model, plus 7 quality dimensions (empathy, relevance, clarity, safety, exploration, autonomy, staging) rated 1-5 for both chosen and rejected.

**Why it matters:** The 7-dimension rating system (especially exploration, autonomy, staging) aligns with how Auraken should evaluate lens applicability. The preference pairs can calibrate which response styles work better for different problem types.

**Quality issues:** LLM-generated responses (not human). CC-BY-NC restricts commercial use.

---

### 17. hendrycks/ethics (ETHICS Benchmark)

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/hendrycks/ethics |
| **Size** | 134,417 rows |
| **License** | MIT |
| **Relevance** | **MEDIUM** |

**Schema:** 5 subcategories -- Commonsense (label + input), Deontology (label + scenario + excuse), Justice (label + scenario), Utilitarianism (baseline + less_pleasant), Virtue (label + scenario)

**Why it matters:** The 5 ethical reasoning frameworks (commonsense, deontology, justice, utilitarianism, virtue) map directly to ethical reasoning lenses in Auraken. Pre-labeled with framework type.

**Quality issues:** Scenarios are short and synthetic. Binary labels lack nuance. Not "real-world problems" in the way Reddit posts are.

---

### 18. Psychotherapy-LLM/CBT-Bench

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/Psychotherapy-LLM/CBT-Bench |
| **Size** | Multiple configs (hundreds of examples) |
| **License** | Not specified |
| **Relevance** | **MEDIUM** |

**Schema:** Cognitive distortions (10 categories), core beliefs (3 major, 19 fine-grained), pairwise comparisons, LLM execution results

**Why it matters:** CBT taxonomy of cognitive distortions (catastrophizing, all-or-nothing thinking, etc.) is directly relevant for lenses that address thinking patterns. The taxonomy could inform which cognitive bias lenses should activate.

**Quality issues:** Small. Focused narrowly on CBT rather than general problem-solving.

---

## Tier 3: Supplementary Datasets

### 19. rexarski/eli5_category

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/rexarski/eli5_category |
| **Size** | 105,004 Q&A pairs |
| **License** | Unknown (Pushshift-derived) |
| **Relevance** | **LOW** |

**Schema:** q_id, subreddit, category (11 categories), title, selftext, answers (with scores)

**Categories:** Biology, Chemistry, Culture, Earth Science, Economics, Engineering, Mathematics, Other, Physics, Psychology, Technology

**Why it matters:** Categorized explanatory questions. The category labels provide coverage testing across knowledge domains. However, ELI5 questions are "explain this" not "help me decide" -- lower relevance for lens selection calibration.

---

### 20. launch/CMV (ChangeMyView)

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/launch/CMV |
| **Size** | 133 rows |
| **License** | Apache 2.0 |
| **Relevance** | **LOW** (too small; use REDDIT_threaded changemyview split instead) |

**Schema:** Original post (array), comments (array), label (moderate/challenge)

**Note:** The REDDIT_threaded dataset has 135K changemyview threads. The REDDIT_comments dataset has 11.6M changemyview comments. Use those instead.

---

### 21. agentlans/reddit-ethics

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/agentlans/reddit-ethics |
| **Size** | Curated subset (sampled from AITA) |
| **License** | Not specified |
| **Relevance** | **LOW** (derivative of AITA dataset above) |

---

### 22. ninoscherrer/moralchoice

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/ninoscherrer/moralchoice |
| **Size** | 1,767 hypothetical scenarios |
| **License** | Not specified |
| **Relevance** | **LOW** |

**Description:** 687 low-ambiguity + 680 high-ambiguity moral scenarios based on Gert's common morality framework. Useful for ethical lens calibration but scenarios are synthetic/hypothetical.

---

### 23. demelin/moral_stories

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/demelin/moral_stories |
| **Size** | Not specified (moderate) |
| **License** | Not specified |
| **Relevance** | **LOW** |

**Description:** Context segments grounding actions in social scenarios with normative and divergent paths.

---

### 24. mattwesney/Reasoning_Problem_Solving_Dataset

| Field | Value |
|-------|-------|
| **URL** | https://huggingface.co/datasets/mattwesney/Reasoning_Problem_Solving_Dataset |
| **Size** | 151,261 pairs, 96K sub-topics |
| **License** | Gated (requires access request) |
| **Relevance** | **LOW** |

**Taxonomy includes:** High-stakes Decision Making, Behavioral Economics, Game Theory, Decomposition, Heuristic approaches, Time-based Problem-solving, Spatial Logic, Event-driven Reasoning.

**Why low relevance:** Despite the rich taxonomy, this is an LLM-generated reasoning dataset, not real-world problems. The taxonomy itself may be useful for mapping to Auraken's lens categories.

---

## Pushshift / Reddit Archive Status

| Source | Status (as of March 2026) | Access |
|--------|--------------------------|--------|
| **Pushshift API** | Restricted to verified Reddit moderators only | Requires Reddit moderator registration + approval |
| **Pushshift data dumps** | Historical dumps available but no longer updated | Archived on Internet Archive |
| **Arctic Shift** | Active successor, data through Feb 2026 | Full public access via web, API, and HuggingFace |
| **open-index/arctic (HF)** | 2.1B items, Dec 2005 - Feb 2026 | Free download/streaming, DuckDB queries |
| **fddemarco/pushshift-reddit (HF)** | 550M submissions (older snapshot) | Free download |

**Recommendation:** Use `open-index/arctic` as the canonical Reddit data source. It is the most complete, most recent, and most accessible option. The Arctic Shift project (https://github.com/ArthurHeitmann/arctic_shift) continues to collect data independently of Pushshift.

---

## StackExchange Data Dump Status

| Source | Coverage | Notes |
|--------|----------|-------|
| **common-pile/stackexchange** | Through Dec 2024, 30.4M rows | Filter by `metadata.site` for target sites |
| **HuggingFaceH4/stack-exchange-preferences** | Older dump, 10.8M pairs | Preference-scored, filterable by site |
| **habedi/stack-exchange-dataset** | 82.2K rows, CS/DS/PoliSci only | Too narrow |
| **StackExchange official dumps** | Since July 2024, site-by-site only | Requires login, no bulk download |

**Key sites for Auraken calibration:**
- `workplace.stackexchange.com` -- professional dilemmas, management, workplace dynamics
- `interpersonal.stackexchange.com` -- social skills, conflict resolution, communication
- `philosophy.stackexchange.com` -- conceptual reasoning, ethics, epistemology
- `productivity.stackexchange.com` -- time management, workflow, habits

---

## Gap Analysis: What's Missing

### Subreddits not found as standalone preprocessed datasets
These subreddits have no dedicated HuggingFace datasets but can be extracted from Arctic Shift:

- r/askphilosophy (available in Arctic but not as standalone)
- r/DecisionMaking
- r/getdisciplined
- r/productivity
- r/needadvice
- r/internetparents
- r/careerguidance (mb7419/career-guidance-reddit exists but timed out)
- r/cscareerquestions
- r/jobs
- r/relationships (distinct from r/relationship_advice which is well-covered)
- r/financialindependence
- r/Parenting
- r/BuyItForLife
- r/goodvalue
- r/headphones, r/running
- r/selfimprovement
- r/CBT (subreddit, not the therapy technique)
- r/autism

### Dataset types not found
- **Advice classification taxonomy datasets:** No existing labeled dataset maps "problem type" to "recommended reasoning approach." This is essentially what Auraken needs to create.
- **Context-depth calibration datasets:** No datasets specifically designed to test "how much context is needed before a recommendation becomes useful."
- **Multi-framework comparison datasets:** No dataset where the same problem is analyzed through multiple frameworks with quality ratings.

---

## Recommended Extraction Pipeline

### Phase 1: Build domain-stratified test set from Arctic Shift
```
Target: 500-1000 posts per domain, 15+ domains
Filter: score > 10, selftext > 200 chars, not [removed]
Domains: map target subreddits to Auraken's lens categories
Output: Parquet with subreddit, title, selftext, score, num_comments
```

### Phase 2: Curate labeled anchor scenarios
```
Source: daily_dilemmas (1,360) + AITA top-scored (sample 2K) + counsel-chat (2,780)
Label: manually assign expected top-3 lenses per scenario
Output: JSON with scenario, expected_lenses, domain, complexity_rating
```

### Phase 3: Build coverage index baseline
```
Source: REDDIT_threaded (50 subreddits) + StackExchange (3 target sites)
Method: Run Auraken's selector on stratified sample, track which lenses activate
Output: Coverage matrix (domain x lens activation frequency)
```

### Phase 4: Near-miss scenario extraction
```
Source: AITA ESH/NAH posts + changemyview delta-awarded threads
Method: Posts where multiple competing frameworks apply
Output: Annotated set with "lens A vs lens B" decision points
```

---

## License Summary

| Dataset | License | Commercial OK? |
|---------|---------|----------------|
| open-index/arctic | Reddit ToS | Unclear |
| REDDIT_threaded | Undefined | Unclear |
| REDDIT_comments | Undefined | Unclear |
| AITA-Reddit-Dataset | Not specified | Unclear |
| daily_dilemmas | CC-BY-4.0 | Yes |
| counsel-chat | Not specified | Unclear |
| stack-exchange-preferences | CC-BY-SA 4.0 | Yes (with attribution) |
| common-pile/stackexchange | CC-BY-SA 3.0/4.0 | Yes (with attribution) |
| Personal-Finance-Queries | MIT | Yes |
| mental_health_counseling | RAIL-D | Restricted |
| Stoicism_QA_610 | MIT | Yes |
| Amazon-Reviews-2023 | Not specified | Unclear |
| PsychoCounsel-Preference | CC-BY-NC-4.0 | No |
| ETHICS | MIT | Yes |
| ELI5-Category | Unknown | Unclear |

**Note:** For internal calibration/testing (not redistribution), license restrictions are less relevant. For publishing benchmark results or redistributing derived datasets, CC-BY-SA and MIT are safest.
