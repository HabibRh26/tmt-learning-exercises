# Lesson 1: From Empty Directory to a Working Test Run

**Goal:** By the end, you'll have created every file needed for `tmt run` to work, and you'll know *why* each one exists.

**Prerequisites:** `sudo dnf install -y tmt+all`

---

## Task 0 — Create a playground

```bash
mkdir ~/tmt-learn && cd ~/tmt-learn
git init
```

**Why:** tmt works inside git repos. The metadata tree (fmf) is built from the repo root.

**Verify:**
```bash
git status
```

---

## Task 1 — Initialize the fmf root

```bash
tmt init
```

**What just happened:** Look inside your directory.

```bash
ls -la .fmf/
```

You'll see a single file: `.fmf/version` containing just `1`. This tiny file is the flag that tells tmt "this directory tree contains metadata." Without it, tmt sees nothing.

**Verify:**
```bash
tmt tests ls
tmt plans ls
```

Both return empty — the root exists but you haven't defined anything yet.

---

## Task 2 — Write the actual test script

Create the file `tests/smoke/test.sh`:

```bash
mkdir -p tests/smoke
```

Now write this script yourself (use your editor):

```bash
#!/bin/bash
echo "Checking if /etc/os-release exists..."
test -f /etc/os-release && echo "PASS: file exists" || exit 1

echo "Checking if bash is available..."
bash --version > /dev/null && echo "PASS: bash works" || exit 1

echo "All checks passed."
```

Make it executable:

```bash
chmod +x tests/smoke/test.sh
```

**Why:** This is just a shell script. tmt doesn't care *what* your test does — it only cares about the **exit code**. `0` = pass, anything else = fail. This is the fundamental contract.

**Verify:**
```bash
./tests/smoke/test.sh
echo $?    # should print 0
```

---

## Task 3 — Create test metadata

tmt doesn't know your script exists yet. You need to describe it. Create `tests/smoke/main.fmf`:

```yaml
summary: Basic smoke test for OS essentials
test: ./test.sh
duration: 2m
```

**What each key does:**

| Key | Purpose |
|-----|---------|
| `summary` | Human-readable one-liner (shows up in `tmt tests show`) |
| `test` | The command tmt will execute (relative to this file's directory) |
| `duration` | Max time before tmt kills the test as a timeout |

**Why `main.fmf`?** Any file named `*.fmf` contributes to the metadata tree. `main.fmf` is the convention for "this directory's metadata" — like `index.html` for a folder.

**Verify:**
```bash
tmt tests ls
```

You should see `/tests/smoke`. tmt found your test.

```bash
tmt tests show
```

This prints the full metadata. Confirm your summary, test command, and duration appear.

---

## Task 4 — Try to run (and watch it fail)

```bash
tmt run -v
```

**What happens:** tmt complains — it found a test but no **plan**. Tests define *what* to run. Plans define *how* to run it. You need both.

**Lesson:** A test alone is not enough. The plan is the orchestrator.

---

## Task 5 — Create a plan

```bash
mkdir -p plans
```

Create `plans/basic.fmf`:

```yaml
summary: Run smoke tests in a container
discover:
    how: fmf
provision:
    how: container
    image: fedora:latest
execute:
    how: tmt
```

**What each block does:**

| Block | Pipeline step | What it answers |
|-------|---------------|-----------------|
| `discover` | Step 1 | "Where do I find tests?" — `fmf` means scan the repo's `.fmf` tree |
| `provision` | Step 2 | "Where do I run them?" — a fresh Fedora container |
| `execute` | Step 3 | "How do I run them?" — `tmt` executor handles script execution and result collection |

**Why a separate `plans/` directory?** Convention. Plans and tests live apart because plans describe infrastructure, tests describe behavior. Different concerns, different owners.

**Verify:**
```bash
tmt plans ls
```

You should see `/plans/basic`.

```bash
tmt plans show
```

Confirm discover/provision/execute details appear.

---

## Task 6 — Lint before you run

```bash
tmt lint
```

This validates all your metadata. Fix any warnings before proceeding. Green checks = you're good.

---

## Task 7 — Dry run

```bash
tmt run --dry -v
```

**Why:** This walks through the entire pipeline *without actually provisioning or executing anything*. You'll see tmt discover your test, describe what container it would create, and what it would execute. No resources consumed.

**Verify:** Read the output. You should see your test `/tests/smoke` discovered under plan `/plans/basic`.

---

## Task 8 — The real run

```bash
tmt run -vv
```

Watch the output. tmt will:

1. **Discover** — find `/tests/smoke`
2. **Provision** — pull and start `fedora:latest` container
3. **Prepare** — install any dependencies (none in our case)
4. **Execute** — run `./test.sh` inside the container
5. **Report** — show pass/fail
6. **Finish** — tear down the container

**Verify:** You should see a **PASS** result.

---

## Task 9 — Make a test fail (on purpose)

Edit `tests/smoke/test.sh` — add a line that will fail:

```bash
# add this at the end of test.sh
test -f /nonexistent/file && echo "PASS" || exit 1
```

Run again:

```bash
tmt run -vv
```

You should see a **FAIL**. Now inspect:

```bash
tmt run --last report -vvv
```

This shows the detailed output of the failed test — the exact logs from inside the container.

**Lesson:** `--last` re-reads the most recent run's data without re-executing. `-vvv` gives you full output.

---

## Task 10 — Inspect the run directory

```bash
ls /var/tmp/tmt/
```

tmt stores all run data here. Each run gets its own directory with logs, results, and guest info. Poke around — understanding this structure helps when debugging real failures later.

---

## What you built

```
~/tmt-learn/
├── .fmf/
│   └── version            <- "this is an fmf tree"
├── plans/
│   └── basic.fmf          <- HOW to run (discover + provision + execute)
└── tests/
    └── smoke/
        ├── main.fmf        <- WHAT to run (metadata pointing to the script)
        └── test.sh          <- the actual test logic
```

**3 files you created, each with a distinct job:**

| File | Role | Key that identifies it |
|------|------|-----------------------|
| `test.sh` | The actual test logic | (just a script, exit 0/1) |
| `main.fmf` | Test metadata | `test:` key |
| `basic.fmf` | Plan / orchestration | `execute:` key |

---

## Lesson 1 checklist

- [ ] Can explain what `.fmf/version` does
- [ ] Can explain the difference between a test and a plan
- [ ] Know that exit code 0 = pass, non-zero = fail
- [ ] Created and ran a test in a container
- [ ] Used `--dry`, `--last`, `-vvv`, and `lint`
- [ ] Know where tmt stores run data

---

**Next:** Lesson 2 — adding dependencies with `require`, using `prepare` to install packages, and running tests across different OS images.
