---
artifact_type: brainstorm
bead: Sylveste-6i0.12
stage: discover
---
# Skaffen Image Support (@image references)

## What We're Building

Add image input support to Skaffen via the existing `@filepath` syntax. When a user references an image file (`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`), Skaffen auto-detects it by extension, base64-encodes the file, and sends it as an `image` content block alongside the text prompt to the Anthropic API.

**Scope:** File references only. No clipboard paste, no PDF, no URL fetching. v1 parity with the most common competitor feature.

## Why This Approach

### Auto-detect by extension (zero new syntax)

Skaffen already has `@filepath` expansion in `expandAtMentions()`. Adding image support means extending the same function to detect image extensions and produce image `ContentBlock`s instead of text inlines. Users don't learn new syntax — `@screenshot.png` just works.

### Placeholder badge display

Terminals can't render images reliably. Instead of chasing protocol-specific rendering (kitty, iTerm2, sixel), show a compact badge: `[🖼 screenshot.png (245KB)]`. Confirms the image was sent without depending on terminal capabilities.

### Narrow change surface

The codebase is already well-positioned:
- `ContentBlock` is polymorphic (JSON pass-through to API)
- Session JSONL persistence is schema-agnostic
- The `@mention` expansion pattern exists
- No legacy text-only assumptions anywhere critical

Core changes: 3 files modified, 1 new type added.

## Key Decisions

### 1. Image detection: extension-based

```
imageExts = {".png", ".jpg", ".jpeg", ".gif", ".webp"}
```

If `@path` has an image extension, route to image handling. Otherwise, existing text expansion.

### 2. Content block format

```go
type ImageSource struct {
    Type      string `json:"type"`       // "base64"
    MediaType string `json:"media_type"` // "image/png", etc.
    Data      string `json:"data"`       // base64 string
}
```

Added as optional field on existing `ContentBlock`.

### 3. Size limit: 5MB

Anthropic's limit. Check before base64 encoding, return user-friendly error if exceeded.

### 4. Token estimation: ~1600 tokens per image

Approximate cost for token budgeting. Not exact (depends on resolution) but good enough for context management.

### 5. TUI display: badge

`[🖼 filename.ext (size)]` — compact, terminal-safe, confirms image was processed.

### 6. Print mode: same behavior

`skaffen --mode print --prompt "@screenshot.png describe this"` works identically — image is loaded, encoded, sent.

## Open Questions (for planning)

1. **Multiple images per message** — should `@img1.png @img2.png compare these` work? (Probably yes — Anthropic API supports multiple image blocks per message.)
2. **Image in session replay** — when loading a saved session, should we re-encode images from disk or store the base64 in JSONL? (Store in JSONL — files may be deleted.)
