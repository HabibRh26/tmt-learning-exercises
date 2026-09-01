# Lesson 2: Dependencies, Prepare, and Multiple OS Images

**Goal:** By the end, you'll know how to declare package dependencies, run setup commands before tests, and execute the same tests across different OS images.

**Prerequisites:** Complete Lesson 1. You should have `~/tmt-learn/` with a working test and plan.

---

## Task 0 — Start fresh from your existing playground

```bash
cd ~/tmt-learn
```

Make sure your Lesson 1 setup still works:

```bash
tmt tests ls
tmt plans ls
```

You should see `/tests/smoke` and `/plans/basic`.

If you nuked your Lesson 1 directory, go back and redo Tasks 0-5 from Lesson 1 first.

---

## Task 1 — Write a test that needs a package

Create a new test that uses `jq` (a JSON processor). Most minimal containers don't have it pre-installed, so this test will **fail** without proper dependency management.

```bash
mkdir -p tests/json-parse
```

Write `tests/json-parse/test.sh` yourself:

```bash
#!/bin/bash
echo '{"name": "tmt", "version": 2}' | jq '.name'
if [ $? -eq 0 ]; then
    echo "PASS: jq parsed JSON successfully"
    exit 0
else
    echo "FAIL: jq could not parse JSON"
    exit 1
fi
```

Make it executable:

```bash
chmod +x tests/json-parse/test.sh
```

---

## Task 2 — Create metadata WITHOUT `require` (break it first)

Create `tests/json-parse/main.fmf` — deliberately leave out `require`:

```yaml
summary: Parse JSON with jq
test: ./test.sh
duration: 2m
```

**Verify the test is discovered:**

```bash
tmt tests ls
```

You should now see both `/tests/smoke` and `/tests/json-parse`.

---

## Task 3 — Run and watch it fail

```bash
tmt run -vv
```

The `/tests/json-parse` test will **fail** inside the container because `jq` isn't installed. The `/tests/smoke` test should still pass.

**Lesson:** Your test script depends on `jq`, but you never told tmt about that. The container doesn't have it, so it breaks.

Look at the failure output:

```bash
tmt run --last report -vvv
```

You'll see something like `jq: command not found`.

---

## Task 4 — Fix it with `require`

Edit `tests/json-parse/main.fmf` to add the dependency:

```yaml
summary: Parse JSON with jq
test: ./test.sh
duration: 2m
require:
  - jq
```

**What `require` does:** Before running this test, tmt installs all listed packages inside the test environment. This happens during the **prepare** step of the pipeline.

**Verify:**

```bash
tmt tests show /tests/json-parse
```

You should see `require` listed with `jq` under it.

Now run again:

```bash
tmt run -vv
```

Both tests should **PASS**. tmt installed `jq` inside the container before running your test.

---

## Task 5 — Understand `require` vs `recommend`

Edit `tests/json-parse/main.fmf`:

```yaml
summary: Parse JSON with jq
test: ./test.sh
duration: 2m
require:
  - jq
recommend:
  - vim-enhanced
```

| Key | What happens if the package is missing |
|-----|----------------------------------------|
| `require` | tmt **aborts** the test — hard dependency |
| `recommend` | tmt **tries** to install but continues if it fails — soft dependency |

**When to use `recommend`:** Debug tools, editors, optional utilities that make logs nicer but aren't needed for the test to run.

**Verify:**

```bash
tmt tests show /tests/json-parse
```

Confirm both `require` and `recommend` appear.

---

## Task 6 — The `prepare` step (break it first)

`require` handles packages per-test. But what if you need to set up the environment itself — create directories, write config files, download data? That's what `prepare` does in the plan.

First, write a test that **expects** some environment setup. Create it before the setup exists — so it will fail.

```bash
mkdir -p tests/prepare-check
```

Write `tests/prepare-check/test.sh`:

```bash
#!/bin/bash
echo "Checking if prepare step created the workspace..."
test -f /tmp/test-workspace/ready.txt && echo "PASS: workspace ready" || exit 1

echo "Checking if tree is available (installed by prepare)..."
tree --version > /dev/null && echo "PASS: tree installed" || exit 1

echo "All checks passed."
```

```bash
chmod +x tests/prepare-check/test.sh
```

Create `tests/prepare-check/main.fmf`:

```yaml
summary: Verify that the prepare step ran correctly
test: ./test.sh
duration: 2m
```

**Notice:** No `require` here. This test depends on `tree` and a file at `/tmp/test-workspace/ready.txt`, but neither exists yet.

**Run it and watch it fail:**

```bash
tmt run -vv
```

The `prepare-check` test fails — `/tmp/test-workspace/ready.txt` doesn't exist and `tree` isn't installed. The test expected something that nobody set up.

---

## Task 7 — Fix it with `prepare` in the plan

Edit `plans/basic.fmf` to add a `prepare` step:

```yaml
summary: Run smoke tests in a container
discover:
    how: fmf
provision:
    how: container
    image: fedora:latest
prepare:
  - how: install
    package:
      - tree
  - how: shell
    script: |
        mkdir -p /tmp/test-workspace
        echo "prepared at $(date)" > /tmp/test-workspace/ready.txt
execute:
    how: tmt
```

**What each `prepare` block does:**

| `how` | Purpose |
|-------|---------|
| `install` | Install packages — plan-level, applies to all tests in this plan |
| `shell` | Run arbitrary shell commands for setup |

**Run again:**

```bash
tmt run -vv
```

All three tests should **PASS** now. tmt installed `tree` and created the workspace file before any tests ran.

---

## Task 8 — `require` (test) vs `prepare: install` (plan)

You've now seen two ways to install packages. When do you use which?

| | `require` (in test) | `prepare: install` (in plan) |
|---|---|---|
| Defined in | test's `main.fmf` | plan's `.fmf` |
| Scope | Only for that test | For all tests in the plan |
| Moves with the test? | Yes — it's part of the test definition | No — it's tied to the plan |

**Rule of thumb:** If a package is **needed by the test logic** (like `jq` for JSON parsing), use `require`. If it's **needed by the environment** (like `tree` for debugging output), use `prepare: install`.

**Quick exercise:** Think about where each of these would go:

- `curl` needed by a test that checks HTTP endpoints → ?
- `strace` for debugging any test failure → ?
- `python3` needed by a test's helper script → ?

Answers: `require`, `prepare: install`, `require`.

---

## Task 9 — Different plans for different tests (break it first)

Right now, `plans/basic.fmf` uses `discover: how: fmf` with no filter — so it discovers **all** tests. Run this to see:

```bash
tmt run --dry -v plan --name /plans/basic
```

You'll see all three tests (`smoke`, `json-parse`, `prepare-check`) under one plan. But what if you want separate plans for separate tests — different environments, different configurations?

**The problem:** Create a second plan without any filter. Create `plans/json.fmf`:

```yaml
summary: JSON parsing tests
discover:
    how: fmf
provision:
    how: container
    image: fedora:latest
execute:
    how: tmt
```

```bash
tmt run --dry -v
```

Now **both** plans discover **all** tests. Every test runs twice — once per plan. That's wasteful and wrong. The `prepare-check` test has no business running under a plan that doesn't set up its workspace.

---

## Task 10 — Fix it with `discover: test:` filter

Edit `plans/json.fmf` to scope it to only the json-parse test:

```yaml
summary: JSON parsing tests
discover:
    how: fmf
    test:
      - /tests/json-parse
provision:
    how: container
    image: fedora:latest
execute:
    how: tmt
```

Similarly, edit `plans/basic.fmf` to scope it:

```yaml
summary: Run smoke and prepare tests in a container
discover:
    how: fmf
    test:
      - /tests/smoke
      - /tests/prepare-check
provision:
    how: container
    image: fedora:latest
prepare:
  - how: install
    package:
      - tree
  - how: shell
    script: |
        mkdir -p /tmp/test-workspace
        echo "prepared at $(date)" > /tmp/test-workspace/ready.txt
execute:
    how: tmt
```

**Verify:**

```bash
tmt run --dry -v
```

Now each plan discovers only its own tests. The `prepare-check` test only runs under `basic` (which has the prepare step), and `json-parse` only runs under `json`.

**Your plans directory now:**

```
plans/
├── basic.fmf       <- discovers /tests/smoke + /tests/prepare-check
└── json.fmf        <- discovers /tests/json-parse only
```

---

## Task 11 — Alternative: filter by tag instead of path

Listing test paths in every plan works but gets tedious as you add more tests. An alternative is tagging tests and filtering by tag.

Edit `tests/json-parse/main.fmf` — add a tag:

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
```

Edit `tests/smoke/main.fmf` — add a tag:

```yaml
summary: Basic smoke test for OS essentials
test: ./test.sh
duration: 2m
tag:
  - sanity
```

Now you could write a plan that discovers by tag:

```yaml
# example — don't create this file, just understand the pattern
discover:
    how: fmf
    filter: "tag = parsing"
```

This way, adding a new parsing test is just adding `tag: [parsing]` to its `main.fmf` — the plan picks it up automatically without editing the plan file.

| Approach | When to use |
|----------|-------------|
| `discover: test:` with paths | Few tests, explicit control |
| `discover: filter:` with tags | Many tests, tests come and go frequently |

**Verify your tags are set:**

```bash
tmt tests show /tests/json-parse
tmt tests show /tests/smoke
```

Confirm the `tag` field appears in both.

---

## Task 12 — Same tests, different containers

Now a different use case — you want to run the **same** tests on **multiple OS images** to catch distro-specific bugs. Create a CentOS plan that runs the same json-parse test:

Create `plans/centos.fmf`:

```yaml
summary: Run JSON tests on CentOS Stream 9

discover:
    how: fmf
    test:
      - /tests/json-parse

provision:
    how: container
    image: quay.io/centos/centos:stream9

execute:
    how: tmt
```

**Verify:**

```bash
tmt plans ls
```

You should see `/plans/basic`, `/plans/json`, and `/plans/centos`.

Now the `json-parse` test runs on **both** Fedora (via `plans/json.fmf`) and CentOS (via `plans/centos.fmf`). Same test, different environments — zero changes to the test itself.

```bash
tmt run --dry -v plan --name "json|centos"
```

You'll see the same `/tests/json-parse` test discovered under both plans, each with a different container image.

---

## Task 13 — Filter with `plan --name` and `test --name`

Running `tmt run` executes **all** plans. To be selective at the CLI:

Run only the CentOS plan:

```bash
tmt run -vv plan --name /plans/centos
```

Run plans matching a pattern:

```bash
tmt run --dry -v plan --name "json|centos"
```

This runs both `json` and `centos` plans but skips `basic`.

Run a specific test across all plans that include it:

```bash
tmt run -vv test --name /tests/json-parse
```

Combine both:

```bash
tmt run -vv plan --name /plans/centos test --name /tests/json-parse
```

**What `--name` does:** Filters by name. Supports exact paths and regex patterns.

**`plan --name` vs `discover: test:` — what's the difference?**

| | `discover: test:` (in plan file) | `plan --name` / `test --name` (CLI) |
|---|---|---|
| Where | Baked into the plan `.fmf` | Typed at runtime |
| Permanent? | Yes — always applies | No — just this one run |
| Use case | Define what a plan is *for* | Quick one-off filtering |

**Verify each command:** Check the output to confirm only the expected plan/test combinations ran.

---

## Task 14 — Use `adjust` for OS-specific behavior

What if CentOS needs a different package name or an extra setup step? Use `adjust` to conditionally modify metadata.

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

adjust:
  - when: distro == centos-stream
    require+:
      - python3
    because: CentOS Stream needs python3 for our helper scripts
```

**What `adjust` does:** Conditionally modifies metadata based on the environment.

**Key detail:** `require+:` (with the `+`) means **append** to the existing list. Without the `+`, it would **replace** the entire list.

| Syntax | Effect |
|--------|--------|
| `require:` inside adjust | Replaces — only `python3`, `jq` is gone |
| `require+:` inside adjust | Appends — both `jq` and `python3` |

**Common conditions:**

| Condition | Matches |
|-----------|---------|
| `distro == fedora` | Fedora |
| `distro == centos-stream` | CentOS Stream |
| `distro == rhel-9` | RHEL 9 |
| `arch == aarch64` | ARM architecture |

**Verify:**

```bash
tmt tests show /tests/json-parse
```

You should see the `adjust` section in the output.

---

## What you built

```
~/tmt-learn/
├── .fmf/
│   └── version
├── plans/
│   ├── basic.fmf              <- Fedora + prepare, scoped to smoke + prepare-check
│   ├── json.fmf               <- Fedora, scoped to json-parse only
│   └── centos.fmf             <- CentOS Stream 9, scoped to json-parse only
└── tests/
    ├── smoke/
    │   ├── main.fmf            <- tagged: sanity
    │   └── test.sh
    ├── json-parse/
    │   ├── main.fmf            <- require, recommend, tag, adjust
    │   └── test.sh
    └── prepare-check/
        ├── main.fmf
        └── test.sh
```

**New concepts in this lesson:**

| Concept | Where it lives | What it does |
|---------|---------------|--------------|
| `require` | test `main.fmf` | Hard package dependency — test won't run without it |
| `recommend` | test `main.fmf` | Soft package dependency — nice to have |
| `prepare: install` | plan `.fmf` | Install packages for all tests in the plan |
| `prepare: shell` | plan `.fmf` | Run arbitrary setup commands |
| `discover: test:` | plan `.fmf` | Scope a plan to specific tests by path |
| `discover: filter:` | plan `.fmf` | Scope a plan to tests matching a tag/expression |
| `tag` | test `main.fmf` | Label tests for filtering |
| `plan --name` | CLI | Filter which plans to run (at runtime) |
| `test --name` | CLI | Filter which tests to run (at runtime) |
| `adjust` | test or plan `.fmf` | Conditional metadata based on distro/arch |
| `require+:` | inside `adjust` | Append to a list instead of replacing it |

---

## Lesson 2 checklist

- [ ] Saw a test fail because a dependency was missing, then fixed it with `require`
- [ ] Can explain the difference between `require` and `recommend`
- [ ] Saw a test fail because environment setup was missing, then fixed it with `prepare`
- [ ] Can explain `require` (test) vs `prepare: install` (plan) and when to use each
- [ ] Used `prepare: shell` to run setup commands before tests
- [ ] Scoped plans to specific tests using `discover: test:` filter
- [ ] Know the difference between path filtering and tag filtering
- [ ] Ran the same test across multiple OS images using separate plans
- [ ] Used `plan --name` and `test --name` to filter runs at the CLI
- [ ] Can explain `discover: test:` (permanent, in file) vs `--name` (one-off, CLI)
- [ ] Know what `adjust` does and how `require+:` appends instead of replaces

---

**Next:** Lesson 3 — test organization with tiers, FMF inheritance (setting defaults in parent directories), and the `report` step.
