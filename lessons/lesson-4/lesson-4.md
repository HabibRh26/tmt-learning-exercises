# Lesson 4: Environment Variables, Context, and BeakerLib

**Goal:** By the end, you'll know how to pass configuration to tests via environment variables, parameterize runs with context, and write structured tests using BeakerLib.

**Prerequisites:** Complete Lesson 3. You should have `~/tmt-learn/` with tiered tests, FMF inheritance, and multiple plans.

---

## Task 0 — Verify your setup

```bash
cd ~/tmt-learn
tmt tests ls
tmt plans ls
```

You should see your tests and plans from previous lessons.

---

## Part 1 — Environment Variables

## Task 1 — Write a test that reads an env var (break it first)

Create a test that checks a URL — but the URL comes from an environment variable, not hardcoded:

```bash
mkdir -p tests/url-check
```

Write `tests/url-check/test.sh`:

```bash
#!/bin/bash
echo "Checking URL: $TARGET_URL"

if [ -z "$TARGET_URL" ]; then
    echo "FAIL: TARGET_URL is not set"
    exit 1
fi

curl -s -o /dev/null -w "%{http_code}" "$TARGET_URL" | grep -q "200"
if [ $? -eq 0 ]; then
    echo "PASS: $TARGET_URL returned 200"
    exit 0
else
    echo "FAIL: $TARGET_URL did not return 200"
    exit 1
fi
```

```bash
chmod +x tests/url-check/test.sh
```

Create `tests/url-check/main.fmf`:

```yaml
summary: Check that a URL returns HTTP 200
test: ./test.sh
require:
  - curl
tier: 1
```

**Run it:**

```bash
tmt run -vv test --name /tests/url-check plan --name /plans/gating
```

It **fails** — `TARGET_URL` is not set. The test doesn't know what URL to check.

---

## Task 2 — Fix it with `environment` in the test

Edit `tests/url-check/main.fmf`:

```yaml
summary: Check that a URL returns HTTP 200
test: ./test.sh
require:
  - curl
tier: 1
environment:
    TARGET_URL: https://httpbin.org/status/200
```

**What `environment` does:** Sets environment variables that tmt exports before running this test. Your script sees `$TARGET_URL` as if you had run `export TARGET_URL=...` before it.

**Verify:**

```bash
tmt tests show /tests/url-check
```

Confirm `environment` appears with `TARGET_URL`.

**Run again:**

```bash
tmt run -vv test --name /tests/url-check plan --name /plans/gating
```

It should **PASS** — the test now has a URL to check.

---

## Task 3 — Override from the plan

What if different plans need different URLs? The plan's `environment` overrides the test's default.

Create `plans/staging.fmf`:

```yaml
summary: Run URL checks against staging
discover:
    how: fmf
    test:
      - /tests/url-check
provision:
    how: container
    image: fedora:latest
execute:
    how: tmt
environment:
    TARGET_URL: https://httpbin.org/status/201
```

**Run it:**

```bash
tmt run -vv plan --name /plans/staging
```

Check the output — the test sees `TARGET_URL=https://httpbin.org/status/201` (from the plan), not `https://httpbin.org/status/200` (from the test). This will **fail** because the test expects HTTP 200 but gets 201.

**Lesson:** The plan overrides the test's environment. Same test script, different configuration per plan.

Fix the test to accept any 2xx:

Edit `tests/url-check/test.sh`:

```bash
#!/bin/bash
echo "Checking URL: $TARGET_URL"

if [ -z "$TARGET_URL" ]; then
    echo "FAIL: TARGET_URL is not set"
    exit 1
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET_URL")
if [[ "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
    echo "PASS: $TARGET_URL returned $HTTP_CODE"
    exit 0
else
    echo "FAIL: $TARGET_URL returned $HTTP_CODE (expected 2xx)"
    exit 1
fi
```

Run again — now it should **PASS**.

---

## Task 4 — Override from the CLI

The CLI overrides everything — both test and plan values:

```bash
tmt run -vv -e TARGET_URL=https://httpbin.org/status/404 plan --name /plans/staging
```

This **fails** — you forced a 404 URL from the command line.

**Precedence (highest wins first):**

| Source | Precedence |
|--------|------------|
| CLI (`-e KEY=VALUE`) | Highest — overrides everything |
| Plan (`environment:`) | Middle — overrides test defaults |
| Test (`environment:`) | Lowest — the default |

**When to use each:**

| Source | Use case |
|--------|----------|
| Test `environment:` | Sensible defaults that work out of the box |
| Plan `environment:` | Per-environment config (staging vs prod URLs) |
| CLI `-e` | Quick one-off overrides during debugging |

---

## Part 2 — Context

## Task 5 — The problem: same test, different modes

Imagine you want to run your smoke test in two modes:
- **quick** — just check if `/etc/os-release` exists
- **thorough** — also check file contents, permissions, and format

Without context, you'd write two separate test scripts. That means duplicated logic.

---

## Task 6 — Define context in plans

Context lets you pass named dimensions to your tests. The test can then use `adjust` to change behavior based on context values.

Create `plans/quick-smoke.fmf`:

```yaml
summary: Quick smoke tests
discover:
    how: fmf
    test:
      - /tests/smoke
provision:
    how: container
    image: fedora:latest
execute:
    how: tmt
context:
    mode: quick
```

Create `plans/thorough-smoke.fmf`:

```yaml
summary: Thorough smoke tests
discover:
    how: fmf
    test:
      - /tests/smoke
provision:
    how: container
    image: fedora:latest
execute:
    how: tmt
context:
    mode: thorough
```

Two plans, same test, different context.

---

## Task 7 — Use `adjust` to respond to context

Now make the smoke test behave differently based on context. Edit `tests/smoke/main.fmf`:

```yaml
summary: Basic smoke test for OS essentials
test: ./test.sh
tag:
  - sanity
tier: 0

adjust:
  - when: mode == thorough
    duration: 5m
    environment:
        CHECK_DEPTH: thorough
  - when: mode == quick
    duration: 1m
    environment:
        CHECK_DEPTH: quick
```

Update `tests/smoke/test.sh` to use `CHECK_DEPTH`:

```bash
#!/bin/bash
echo "Running in mode: ${CHECK_DEPTH:-quick}"

echo "Checking if /etc/os-release exists..."
test -f /etc/os-release && echo "PASS: file exists" || exit 1

echo "Checking if bash is available..."
bash --version > /dev/null && echo "PASS: bash works" || exit 1

if [ "$CHECK_DEPTH" = "thorough" ]; then
    echo "--- Thorough checks ---"

    echo "Checking /etc/os-release is readable..."
    test -r /etc/os-release && echo "PASS: file is readable" || exit 1

    echo "Checking /etc/os-release contains ID=..."
    grep -q "^ID=" /etc/os-release && echo "PASS: has ID field" || exit 1

    echo "Checking /etc/os-release contains VERSION_ID=..."
    grep -q "^VERSION_ID=" /etc/os-release && echo "PASS: has VERSION_ID field" || exit 1
fi

echo "All checks passed."
```

**Verify:**

```bash
tmt run --dry -v plan --name /plans/quick-smoke
tmt run --dry -v plan --name /plans/thorough-smoke
```

Check the output — the test metadata should show different `duration` and `environment` values depending on which plan you use.

**Run both:**

```bash
tmt run -vv plan --name /plans/quick-smoke
```

```bash
tmt run -vv plan --name /plans/thorough-smoke
```

The quick run skips the extra checks. The thorough run includes them. One test script, two behaviors.

---

## Task 8 — Set context from the CLI

You can also override context at runtime:

```bash
tmt run -vv -c mode=thorough plan --name /plans/quick-smoke
```

Even though the plan says `mode: quick`, the CLI override makes it run in thorough mode.

**Context vs environment — what's the difference?**

| | `context` | `environment` |
|---|---|---|
| Purpose | Controls **metadata** (via adjust) | Passes **values** to the test script |
| Affects | duration, require, test command, etc. | Only what the script reads from `$ENV_VAR` |
| Where it's used | In `adjust: when:` conditions | In the test script as `$VARIABLE` |

They often work together: `context` triggers an `adjust` block, which sets `environment` variables that the script reads.

---

## Part 3 — BeakerLib

## Task 9 — What BeakerLib gives you

So far, all your tests are plain shell scripts. They work, but:
- You write your own pass/fail messages
- You write your own cleanup logic
- Logs are just whatever you `echo`
- No structured phases or assertions

BeakerLib is a shell library that gives you all of this for free:

| Plain shell | BeakerLib equivalent |
|-------------|---------------------|
| `echo "PASS: file exists"` | `rlAssertExists /etc/os-release` |
| `if [ $? -ne 0 ]; then exit 1; fi` | `rlRun "curl http://example.com" 0 "Curl should succeed"` |
| Manual cleanup at end of script | `rlPhaseStartCleanup` — always runs |
| `echo` for logging | `rlLog "message"` — goes to structured journal |

---

## Task 10 — Write a BeakerLib test

```bash
mkdir -p tests/bkr-smoke
```

Write `tests/bkr-smoke/test.sh`:

```bash
#!/bin/bash
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart

rlPhaseStartSetup "Setup"
    rlRun "tmp=\$(mktemp -d)" 0 "Create temp directory"
    rlRun "pushd $tmp"
rlPhaseEnd

rlPhaseStartTest "Check os-release exists"
    rlAssertExists /etc/os-release
rlPhaseEnd

rlPhaseStartTest "Check os-release content"
    rlAssertGrep "ID=" /etc/os-release
    rlAssertGrep "VERSION_ID=" /etc/os-release
rlPhaseEnd

rlPhaseStartCleanup "Cleanup"
    rlRun "popd"
    rlRun "rm -rf $tmp" 0 "Remove temp directory"
rlPhaseEnd

rlJournalEnd
```

```bash
chmod +x tests/bkr-smoke/test.sh
```

**What each part does:**

| Part | Purpose |
|------|---------|
| `. /usr/share/beakerlib/beakerlib.sh` | Load the library |
| `rlJournalStart` / `rlJournalEnd` | Start and stop the structured log |
| `rlPhaseStartSetup` | Setup phase — runs first |
| `rlPhaseStartTest "name"` | A named test phase — can have multiple |
| `rlPhaseStartCleanup` | Cleanup phase — **always runs**, even if tests fail |
| `rlRun "command" 0 "description"` | Run a command, expect exit code 0, log with description |
| `rlAssertExists` | Assert a file exists |
| `rlAssertGrep` | Assert a pattern is found in a file |

---

## Task 11 — Add metadata with `framework: beakerlib`

Create `tests/bkr-smoke/main.fmf`:

```yaml
summary: BeakerLib smoke test for OS essentials
test: ./test.sh
framework: beakerlib
require:
  - beakerlib
tier: 0
```

**What `framework: beakerlib` does:** Tells tmt this test uses BeakerLib, so tmt:
- Looks for the BeakerLib journal after execution (not just the exit code)
- Determines pass/fail from the journal's phase results
- Collects the full structured journal in the run directory

Without `framework: beakerlib`, tmt treats it as a plain shell test and only checks the exit code.

**Verify:**

```bash
tmt tests show /tests/bkr-smoke
```

Confirm `framework: beakerlib` appears.

**Run it:**

```bash
tmt run -vv test --name /tests/bkr-smoke plan --name /plans/gating
```

You should see **PASS** with more structured output than usual.

---

## Task 12 — Inspect the BeakerLib journal

After running, look at the journal:

```bash
tmt run --last report -vvv
```

You'll see the results broken down by phase — Setup, each Test phase, Cleanup — with individual pass/fail for each assertion.

Also find the journal file directly:

```bash
find /var/tmp/tmt/ -name "journal.txt" -newer /tmp/ 2>/dev/null | tail -1
```

Read it:

```bash
cat <path-to-journal.txt>
```

Compare this to the `output.txt` from a plain shell test — the BeakerLib journal has structured phases, timestamps, assertion results, and pass/fail counts. This is what makes BeakerLib tests much easier to debug when they fail.

---

## Task 13 — Compare: plain shell vs BeakerLib

You now have two smoke tests that check the same things:

| | `/tests/smoke` (plain shell) | `/tests/bkr-smoke` (BeakerLib) |
|---|---|---|
| Framework | `shell` (default) | `beakerlib` |
| Pass/fail | Exit code only | Per-phase, per-assertion |
| Cleanup | You handle it yourself | `rlPhaseStartCleanup` always runs |
| Logging | `echo` statements | Structured journal |
| Dependencies | None | `require: [beakerlib]` |

**When to use which:**

| Use plain shell when | Use BeakerLib when |
|----------------------|--------------------|
| Quick one-off checks | Complex multi-step tests |
| Few assertions | Many assertions to track individually |
| No cleanup needed | Cleanup must always run (even on failure) |
| Minimal dependencies | You want structured, machine-readable logs |

---

## What you built

```
~/tmt-learn/
├── .fmf/
│   └── version
├── plans/
│   ├── basic.fmf              <- scoped to smoke + prepare-check, has prepare
│   ├── json.fmf               <- scoped to json-parse
│   ├── centos.fmf             <- CentOS Stream 9
│   ├── gating.fmf             <- tier 0 only, HTML report
│   ├── nightly.fmf            <- tier < 2, JUnit report
│   ├── staging.fmf            <- URL check with custom environment
│   ├── quick-smoke.fmf        <- context: mode: quick
│   └── thorough-smoke.fmf     <- context: mode: thorough
└── tests/
    ├── main.fmf                <- inherited defaults: duration: 2m
    ├── smoke/
    │   ├── main.fmf            <- tier 0, adjust for context
    │   └── test.sh             <- reads CHECK_DEPTH
    ├── json-parse/
    │   ├── main.fmf            <- require, adjust for distro
    │   └── test.sh
    ├── prepare-check/
    │   ├── main.fmf            <- tier 2
    │   └── test.sh
    ├── url-check/
    │   ├── main.fmf            <- environment: TARGET_URL
    │   └── test.sh             <- reads $TARGET_URL
    ├── network/
    │   ├── main.fmf            <- mid-level inheritance
    │   └── ping-check/
    │       ├── main.fmf
    │       └── test.sh
    └── bkr-smoke/
        ├── main.fmf            <- framework: beakerlib
        └── test.sh             <- uses rlRun, rlAssert*, phases
```

**New concepts in this lesson:**

| Concept | Where it lives | What it does |
|---------|---------------|--------------|
| `environment` | test or plan `.fmf` | Pass env vars to the test script |
| `-e KEY=VALUE` | CLI | Override environment from command line |
| Env precedence | CLI > plan > test | Higher source wins |
| `context` | plan `.fmf` | Named dimensions for parameterized runs |
| `-c key=value` | CLI | Override context from command line |
| `adjust` + context | test `main.fmf` | Change metadata based on context values |
| `framework: beakerlib` | test `main.fmf` | Use BeakerLib instead of plain shell |
| `rlRun` | test script | Run command with expected exit code and logging |
| `rlAssertExists/Grep` | test script | Structured assertions |
| `rlPhaseStart*` | test script | Organize test into Setup/Test/Cleanup phases |

---

## Lesson 4 checklist

- [ ] Wrote a test that reads from an environment variable
- [ ] Set a default env var in the test's `main.fmf` with `environment:`
- [ ] Overrode the env var from a plan and from the CLI (`-e`)
- [ ] Know the precedence: CLI > plan > test
- [ ] Used `context` in plans to parameterize the same test
- [ ] Used `adjust` with `when: mode == ...` to change test behavior based on context
- [ ] Overrode context from the CLI (`-c`)
- [ ] Can explain the difference between `context` and `environment`
- [ ] Wrote a BeakerLib test with Setup, Test, and Cleanup phases
- [ ] Set `framework: beakerlib` in test metadata
- [ ] Inspected the BeakerLib journal
- [ ] Know when to use plain shell vs BeakerLib

---

**Next:** Lesson 5 — `provision: how: virtual` for full VMs, multi-host testing with `guest:`, and the `finish` step for cleanup.
