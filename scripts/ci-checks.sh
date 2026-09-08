#!/usr/bin/env bash
# Independent zklw recipe for the existing Generator and parity checkers gate.
# Run only in a disposable clone: one acceptance probe replaces its Git hook.
# Python and pytest are supplied by the registry-pinned Ubuntu 24.04 image.
set -euo pipefail
[[ "${CI:-}" == true && -n "${CI_SOURCE_SHA:-}" ]] || {
  echo "fresh CI clone and CI_SOURCE_SHA required" >&2; exit 2;
}
[[ -d .git && "$(git rev-parse HEAD)" == "$CI_SOURCE_SHA" ]] || {
  echo "source checkout does not match admitted commit" >&2; exit 2;
}
python3 --version
python3 -m pytest --version

# Asset-directory resolution tests
python3 -m pytest tests/test_gen_kimi_manifests.py -q

# Autonomy position rendering tests
python3 -m pytest tests/test_gen_autonomy_position.py -q

# Autonomy position checker refuses a kernel-less checkout
set +e
python3 scripts/gen-autonomy-position.py --check
rc=$?
set -e
echo "exit=$rc"
test "$rc" -eq 2 || {
  echo "expected exit 2 (cannot verify) with no kernel present, got $rc" >&2
  echo "rc=0 would mean --check passed having compared nothing;" >&2
  echo "rc=1 would mean it called the block stale without reading a level." >&2
  exit 1
}

# Autonomy position checker refuses an ic that cannot report floors
set -e
printf '#!/usr/bin/env bash\necho %s\n' \
  "'{\"level\":2,\"name\":\"n\",\"derives_auto_advance\":true,\"declared\":false,\"source\":\"s\"}'" \
  > /tmp/ic-no-ops
chmod +x /tmp/ic-no-ops

set +e
IC_BIN=/tmp/ic-no-ops python3 scripts/gen-autonomy-position.py --check
rc=$?
set -e
test "$rc" -eq 2 || {
  echo "expected exit 2 when \`ops\` is absent, got $rc" >&2
  echo "an ic without the floor table must not be treated as authoritative;" >&2
  echo "rendering its answer would erase the canon floor table." >&2
  exit 1
}

# An empty list is a real answer and must NOT be confused with absence.
printf '#!/usr/bin/env bash\necho %s\n' \
  "'{\"level\":2,\"name\":\"n\",\"derives_auto_advance\":true,\"declared\":false,\"source\":\"s\",\"ops\":[]}'" \
  > /tmp/ic-empty-ops
chmod +x /tmp/ic-empty-ops
set +e
IC_BIN=/tmp/ic-empty-ops python3 scripts/gen-autonomy-position.py --check
rc=$?
set -e
test "$rc" -ne 2 || {
  echo "exit 2 for an explicitly empty ops list conflates 'no floors'" >&2
  echo "with 'cannot report floors'; a kernel with no floors is readable." >&2
  exit 1
}

# Pre-commit installer is idempotent and non-destructive
set -e
bash -n scripts/pre-commit-hook.sh
bash -n scripts/install-pre-commit-hook.sh

printf '#!/usr/bin/env sh\n# --- BEGIN FOREIGN BLOCK ---\necho foreign\n# --- END FOREIGN BLOCK ---\n' \
  > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

bash scripts/install-pre-commit-hook.sh
bash scripts/install-pre-commit-hook.sh
bash scripts/install-pre-commit-hook.sh --check

grep -qF "# --- BEGIN FOREIGN BLOCK ---" .git/hooks/pre-commit || {
  echo "installer destroyed a pre-existing block" >&2; exit 1; }
n="$(grep -cF '# --- BEGIN SYLVESTE AUTONOMY POSITION ---' .git/hooks/pre-commit)"
test "$n" -eq 1 || { echo "expected 1 autonomy block, found $n" >&2; exit 1; }
sh -n .git/hooks/pre-commit

# Vacuity guard fails on a plugin-less root
set +e
python3 scripts/gen-kimi-manifests.py --check --root "$(mktemp -d)" --require-plugins 60
rc=$?
set -e
echo "exit=$rc"
test "$rc" -eq 2 || { echo "expected exit 2 from the vacuity guard, got $rc" >&2; exit 1; }

# Parity checker fails on a plugin-less root
set +e
python3 scripts/check-kimi-version-parity.py --root "$(mktemp -d)" --require-plugins 1
rc=$?
set -e
echo "exit=$rc"
test "$rc" -eq 2 || { echo "expected exit 2 from the parity vacuity guard, got $rc" >&2; exit 1; }

# Parity checker rejects a bump without regeneration
set -e
demo="$(mktemp -d)"
mkdir -p "$demo/.claude-plugin"
printf '{"name":"demo","version":"1.2.3"}\n' > "$demo/.claude-plugin/plugin.json"
printf '{"name":"demo","version":"1.2.3"}\n' > "$demo/kimi.plugin.json"
python3 scripts/check-kimi-version-parity.py --root "$demo" --require-plugins 1

# Bump the source and leave the generated manifest behind — the exact
# failure that let 21 of 62 manifests drift.
printf '{"name":"demo","version":"1.2.4"}\n' > "$demo/.claude-plugin/plugin.json"
set +e
python3 scripts/check-kimi-version-parity.py --root "$demo" --require-plugins 1
rc=$?
set -e
echo "exit=$rc"
test "$rc" -eq 1 || { echo "expected exit 1 for a bump without regeneration, got $rc" >&2; exit 1; }
