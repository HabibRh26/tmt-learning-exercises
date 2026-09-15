# Lesson 3: Tiers, FMF Inheritance, and Reporting Results

**Goal:** By the end, you'll know how to organize tests by importance using tiers, eliminate repetition with FMF inheritance, and get results out in different formats.

**Prerequisites:** Complete Lesson 2. You should have `~/tmt-learn/` with smoke, json-parse, and prepare-check tests, plus basic, json, and centos plans.

---

## Task 0 — Verify your Lesson 2 setup

```bash
cd ~/tmt-learn
tmt tests ls
tmt plans ls
```

You should see three tests (`/tests/smoke`, `/tests/json-parse`, `/tests/prepare-check`) and three plans (`/plans/basic`, `/plans/json`, `/plans/centos`).

---

## Part 1 — Tiers

## Task 1 — Add tiers to your tests

Tiers are a way to rank tests by importance. The convention:

| Tier | Meaning | When to run |
|------|---------|-------------|
| 0 | Critical / gating | Every PR, every commit |
| 1 | Functional | Nightly |
| 2 | Extended / extras | Weekly or on-demand |
| 3 | Stress / long-running | Release qualification |

Edit `tests/smoke/main.fmf`:

```yaml
summary: Basic smoke test for OS essentials
test: ./test.sh
duration: 2m
tag:
  - sanity
tier: 0
```

Edit `tests/json-parse/main.fmf`:

```yaml
summary: Parse JSON with jq
test: ./test.sh
duration: 2m
require:
  - jq
recommend:
  - vim-enhanced
tag:
  - parsing
tier: 1

adjust:
  - when: distro == centos-stream
    require+:
      - python3
    because: CentOS Stream needs python3 for our helper scripts
```

Edit `tests/prepare-check/main.fmf`:

```yaml
summary: Verify that the prepare step ran correctly
test: ./test.sh
duration: 2m
tier: 2
```

**Verify:**

```bash
tmt tests show
```

Confirm each test shows its `tier` value.

---

## Task 2 — Filter tests by tier

List only critical tests:

```bash
tmt tests ls --filter "tier: 0"
```

You should see only `/tests/smoke`.

List everything below tier 2:

```bash
tmt tests ls --filter "tier < 2"
```

You should see `/tests/smoke` (tier 0) and `/tests/json-parse` (tier 1).

---

## Task 3 — Create a gating plan that only runs tier 0

In real CI, you want a plan that runs only critical tests on every PR. Create `plans/gating.fmf`:

```yaml
summary: Gating tests — must pass before merge
discover:
    how: fmf
    filter: "tier: 0"
provision:
    how: container
    image: fedora:latest
execute:
    how: tmt
```

**Verify:**

```bash
tmt run --dry -v plan --name /plans/gating
```

Only `/tests/smoke` should be discovered. This is the kind of plan that would block a PR merge if any test fails.

**Compare with a nightly plan.** Create `plans/nightly.fmf`:

```yaml
summary: Nightly — all tier 0 and tier 1 tests
discover:
    how: fmf
    filter: "tier < 2"
provision:
    how: container
    image: fedora:latest
execute:
    how: tmt
```

```bash
tmt run --dry -v plan --name /plans/nightly
```

This discovers `/tests/smoke` and `/tests/json-parse` but skips `prepare-check` (tier 2).

**The pattern:**

| Plan | Filter | Runs when |
|------|--------|-----------|
| `gating.fmf` | `tier: 0` | Every PR |
| `nightly.fmf` | `tier < 2` | Every night |
| `basic.fmf` | specific test paths | On-demand / weekly |

---

## Part 2 — FMF Inheritance

## Task 4 — Spot the repetition (the problem)

Look at your three test `main.fmf` files:

```bash
tmt tests show
```

Every single test has `duration: 2m`. If you had 50 tests, that's `duration: 2m` copy-pasted 50 times. If you wanted to change the default to `3m`, you'd edit 50 files.

---

## Task 5 — Set defaults in a parent `main.fmf`

FMF supports inheritance — a `main.fmf` in a parent directory sets defaults for all children. Create `tests/main.fmf` (note: in the `tests/` directory, not inside any test folder):

```yaml
duration: 2m
```

Now **remove** `duration: 2m` from each test's `main.fmf`:

Edit `tests/smoke/main.fmf`:

```yaml
summary: Basic smoke test for OS essentials
test: ./test.sh
tag:
  - sanity
tier: 0
```

Edit `tests/json-parse/main.fmf`:

```yaml
summary: Parse JSON with jq
test: ./test.sh
require:
  - jq
recommend:
  - vim-enhanced
tag:
  - parsing
tier: 1

adjust:
  - when: distro == centos-stream
    require+:
      - python3
    because: CentOS Stream needs python3 for our helper scripts
```

Edit `tests/prepare-check/main.fmf`:

```yaml
summary: Verify that the prepare step ran correctly
test: ./test.sh
tier: 2
```

**Verify:**

```bash
tmt tests show /tests/smoke
```

You should still see `duration: 2m` — even though it's not in the test's own `main.fmf`. It's inherited from `tests/main.fmf`.

```bash
tmt tests show /tests/json-parse
tmt tests show /tests/prepare-check
```

Same — all three inherit `duration: 2m`.

---

## Task 6 — Override an inherited value

What if one test needs more time? Edit `tests/prepare-check/main.fmf`:

```yaml
summary: Verify that the prepare step ran correctly
test: ./test.sh
tier: 2
duration: 5m
```

**Verify:**

```bash
tmt tests show /tests/prepare-check
tmt tests show /tests/smoke
```

`prepare-check` shows `duration: 5m` (overridden). `smoke` still shows `duration: 2m` (inherited). The child wins when it sets the same key.

**How inheritance works:**

```
tests/
├── main.fmf              <- duration: 2m (default for all tests below)
├── smoke/
│   └── main.fmf          <- no duration → inherits 2m
├── json-parse/
│   └── main.fmf          <- no duration → inherits 2m
└── prepare-check/
    └── main.fmf          <- duration: 5m → overrides to 5m
```

fmf walks **up** from a test's directory to the repo root, collecting `main.fmf` files at each level. Values merge top-down, with deeper files overriding shallower ones.

---

## Task 7 — Stack multiple levels of inheritance

You can go deeper. Create a subdirectory of tests with its own defaults:

```bash
mkdir -p tests/network/ping-check
```

Create `tests/network/main.fmf` (mid-level defaults):

```yaml
tag:
  - network
tier: 1
```

Create `tests/network/ping-check/test.sh`:

```bash
#!/bin/bash
ping -c 1 localhost > /dev/null && echo "PASS: ping works" || exit 1
```

```bash
chmod +x tests/network/ping-check/test.sh
```

Create `tests/network/ping-check/main.fmf`:

```yaml
summary: Check that ping works
test: ./test.sh
```

**Verify:**

```bash
tmt tests show /tests/network/ping-check
```

This test inherits:
- `duration: 2m` from `tests/main.fmf` (grandparent)
- `tag: [network]` and `tier: 1` from `tests/network/main.fmf` (parent)
- `summary` and `test` from its own `main.fmf`

Three levels, zero repetition.

---

## Part 3 — Report Step

## Task 8 — The default report (display)

You've been seeing this all along — the terminal output after `tmt run`. That's `report: how: display`, which is the default when you don't specify a report step.

Run a test and watch the output:

```bash
tmt run -vv plan --name /plans/gating
```

At the end you'll see a pass/fail summary. That's the display reporter.

---

## Task 9 — Generate an HTML report

Edit `plans/gating.fmf` to add an HTML report:

```yaml
summary: Gating tests — must pass before merge
discover:
    how: fmf
    filter: "tier: 0"
provision:
    how: container
    image: fedora:latest
execute:
    how: tmt
report:
    how: html
```

Run it:

```bash
tmt run -vv plan --name /plans/gating
```

tmt will tell you where the HTML report was saved — look for a path like `/var/tmp/tmt/run-XXX/.../report/index.html`.

Open it:

```bash
xdg-open /var/tmp/tmt/run-XXX/plans/gating/report/index.html
```

(Replace `XXX` with the actual run number from the output.)

You'll see a browsable report with test names, pass/fail status, duration, and logs.

---

## Task 10 — Generate a JUnit XML report

JUnit XML is what CI systems (Jenkins, GitLab CI, GitHub Actions) consume. Edit `plans/nightly.fmf`:

```yaml
summary: Nightly — all tier 0 and tier 1 tests
discover:
    how: fmf
    filter: "tier < 2"
provision:
    how: container
    image: fedora:latest
execute:
    how: tmt
report:
    how: junit
```

Run it:

```bash
tmt run -vv plan --name /plans/nightly
```

Find the generated file:

```bash
find /var/tmp/tmt/ -name "junit.xml" -newer /tmp/ 2>/dev/null | tail -1
```

Look at it:

```bash
cat <path-to-junit.xml>
```

You'll see XML with `<testcase>` elements — each one has a test name, time, and pass/fail status. This is what you'd feed to your CI system.

---

## Task 11 — Re-inspect a previous run

You don't need to re-run tests to get a report. Use `--last` to re-read the most recent run's data:

```bash
tmt run --last report -vvv
```

This shows the full report from the last run — including test output and logs — without executing anything again.

You can also change the report format on an existing run:

```bash
tmt run --last report --how html
```

This generates an HTML report from the last run's data, even if the run originally used a different format.

**Lesson:** Run data persists in `/var/tmp/tmt/`. You can always go back and re-inspect or re-report.

---

## What you built

```
~/tmt-learn/
├── .fmf/
│   └── version
├── plans/
│   ├── basic.fmf              <- scoped to smoke + prepare-check, has prepare
│   ├── json.fmf               <- scoped to json-parse
│   ├── centos.fmf             <- CentOS Stream 9, scoped to json-parse
│   ├── gating.fmf             <- tier 0 only, HTML report
│   └── nightly.fmf            <- tier < 2, JUnit report
└── tests/
    ├── main.fmf                <- inherited defaults: duration: 2m
    ├── smoke/
    │   ├── main.fmf            <- tier: 0, inherits duration
    │   └── test.sh
    ├── json-parse/
    │   ├── main.fmf            <- tier: 1, require, adjust, inherits duration
    │   └── test.sh
    ├── prepare-check/
    │   ├── main.fmf            <- tier: 2, overrides duration to 5m
    │   └── test.sh
    └── network/
        ├── main.fmf            <- mid-level: tag: network, tier: 1
        └── ping-check/
            ├── main.fmf        <- inherits from two parents
            └── test.sh
```

**New concepts in this lesson:**

| Concept | Where it lives | What it does |
|---------|---------------|--------------|
| `tier` | test `main.fmf` | Ranks test importance (0 = critical, 3 = extended) |
| `filter: "tier: 0"` | plan `discover` | Discovers only tests matching a condition |
| FMF inheritance | parent `main.fmf` | Sets defaults that child directories inherit |
| Override | child `main.fmf` | Child value wins over parent |
| `report: how: display` | plan `.fmf` | Terminal output (default) |
| `report: how: html` | plan `.fmf` | Browsable HTML report |
| `report: how: junit` | plan `.fmf` | JUnit XML for CI systems |
| `--last report` | CLI | Re-inspect or re-report a previous run |

---

## Lesson 3 checklist

- [ ] Added tiers to tests and can explain the tier 0/1/2/3 convention
- [ ] Filtered tests by tier using `--filter` and `discover: filter:`
- [ ] Created a gating plan that only runs critical (tier 0) tests
- [ ] Spotted repetition across test files and fixed it with a parent `main.fmf`
- [ ] Overrode an inherited value in a specific test
- [ ] Built a 3-level inheritance chain (grandparent -> parent -> child)
- [ ] Generated an HTML report and opened it in a browser
- [ ] Generated a JUnit XML report
- [ ] Used `--last report` to re-inspect a previous run without re-executing

---

**Next:** Lesson 4 — `environment` variables, `context` for parameterized runs, and the BeakerLib test framework.
