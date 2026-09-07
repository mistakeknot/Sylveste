VERDICT: PASS
CRITERION: none
RECEIPT: receipt-5ec9c4d939

BEYOND THE GAUGE:
- **Bash 3.2 constraint is unmet by the file as a whole, before and after this change.** `/bin/bash -n scripts/dispatch.sh` fails on macOS bash 3.2 at a pre-existing `[[ -v ... ]]` test near line 897, and the parent commit fails identically. The diff adds no bash-4-only syntax, the shebang resolves to Homebrew bash 5.3, and criterion 3 passed under that bash. The packet's "bash -n PASS" reflects bash 5.3, not /bin/bash.
- **Parser suite was skipped entirely on this host.** gawk is absent, so all ten tests in the parser bats file reported `skip`. Criterion 2's parser half is vacuously satisfied here. The diff does not touch the parser, so exposure is nil, but the suite was not exercised.
- **Auth risk on other operators.** Dropping user scope also drops any `apiKeyHelper` or `env` keys the operator keeps in user settings.json. The brief measured success only on this Mac. A seat on a host whose auth lives in user scope would fail before the model runs.
- **Project and local scope still load.** A project-scope `enabledPlugins` entry carrying an output style would still pollute the seat. Outside the contract, but the same defect class.
- **Role dispatch path confirmed, not just the test's shortcut.** A plain `--role` invocation re-execs with `--role-resolved`, so the override reaches the new condition in real runs. The test uses the resolved flag directly, which exercises the same branch.
- **Test 1(a) "before -p" assertion is weak.** The command always ends in `-p`, so any placement of the flag satisfies it. It still proves presence and single occurrence.
- **Opt-out honours only the literal value 1.** Setting the variable to `true` or `yes` silently keeps the exclusion. This matches the contract but is easy to misconfigure.
