# DOC-3 — `vmtest-harness/` Implementation Plan

**Status:** Plan — sequencing only, **no implementation**
**Implements:** [DOC-1](../02-design/01-vm-install-harness.md) and [DOC-2](../02-design/02-harness-contracts.md), in that order of authority.
**Creates:** nothing. `vmtest-harness/` does not exist and is **not** created by this PR. This document describes how a future engineer creates it.
**Progress record:** [MANIFEST.md](./MANIFEST.md) — the only durable state between execution sessions.

## Purpose

DOC-1 settles **what** the harness does and **why**. DOC-2 settles **every
interface**. Neither settles **order**, and order is the whole risk: the harness's
headline transport — host `git ls-files` → `tar` → `tart exec -i` → guest unpack →
build — has **never been measured end-to-end** (DOC-1 §14, DOC-2 open items,
devil's-advocate critique #9). A plan that builds `lib/` first and reaches that
transport in week two commits the entire module layout to a mechanism nobody has
seen work.

This document sequences the build so the unverified thing is verified **first**,
against the real payload, before anything is designed around it. It targets an
engineer with **zero codebase context**, executing **autonomously**, in sessions
that may be interrupted at any point.

It does **not** re-open a settled decision. Where DOC-1 or DOC-2 states a rule,
this plan cites it and moves on. Where DOC-2 leaves something genuinely
under-specified, this plan **flags it in §F** rather than inventing a contract —
that is the established register of this doc set, and a plan that quietly filled
the gaps would be the least honest document in the set.

---

## How to execute this plan

1. **Read DOC-1 and DOC-2 in full before starting.** They are ~2,700 lines
   combined. There is no shortcut; every task in this plan cites a DOC-2 section
   number, and a task executed without reading its contract will be wrong in a way
   the acceptance check may not catch.
2. **Read [MANIFEST.md](./MANIFEST.md) next.** It states which phases are done,
   what was observed, and what deviated. If it disagrees with this plan, the
   MANIFEST wins for *history*; this plan wins for *what to do next*.
3. **Execute phases in order.** A phase may not begin until the previous phase's
   checkpoint has been observed to pass and the MANIFEST records the observation.
   Phase 1 is the one exception to nothing: it is the risk retirement, and if it
   fails, §P1-T10 says exactly what happens instead.
4. **Within a phase, execute tasks in ID order** unless a task's `Depends` line
   says otherwise.
5. **Commit after every task**, conventional commits, scope `vmtest-harness`.
   Example: `feat(vmtest-harness): add lib/vm.sh tart boundary (P2-T4)`.
6. **The last numbered task of every phase updates the MANIFEST.** It is a task,
   not a habit. It has an acceptance check like any other.

### Scope guardrails — things that are *not* in this plan, by decision

Do not build them, do not "while I'm here" them. Each is an explicit DOC-1 §13
non-goal: golden image or bake script; Cirrus CLI or `.cirrus.yml`; any GitHub
Actions workflow; cargo registry pre-warming; `--dir` mounts in either direction;
a Rust crate or any `cargo test` integration; `install.sh` or prebuilt-tarball
coverage; upgrade scenarios (DOC-1 §12.1 — designed *for*, not built); Linux
support (DOC-1 §12.2 — same).

Two invariants are worth restating because violating either silently destroys the
harness's claim:

- **`lib/vm.sh` is the only file that may contain the string `tart`** (DOC-1 §3.2,
  DOC-2 §12.2). This is mechanically checkable and P2-T4 checks it.
- **The host repo is never mounted, in either direction** (DOC-1 §6.4). Source is
  always copied to guest-local disk. This single rule is what closes the isolation
  hole (DOC-1 §11).

### The stop rule

If a task requires you to *decide* something this plan and DOC-2 do not settle:
**stop, record it in the MANIFEST's Deviations field for the current phase, and
flag it.** Do not invent a contract to keep moving. Every under-specification
already known at planning time is listed in §F with a decision rule attached; a
gap not in §F is a new finding and is worth more than the hour it costs.

---

## A. Ordering and its rationale

**Implementation order is (c) local source → (b) branch → (a) released.** This is
DOC-1 **D4**, as corrected on 2026-07-31, and the corrected justification is the
opposite of the one D4 originally gave.

**(c) is first because its transport is the unverified one.** What the research
measured is a *generic channel property* — 200,000 lines through `tart exec`
untruncated, exit codes propagating exactly through `-i`
([`vm-install-probe-findings.md:179`](../01-research/vm-install-probe-findings.md),
DOC-1 §5.1). What it did **not** measure is the sequence pattern (c) needs. The
112s `trusty-search` build of measurement K3 reached its source tree by a
**guest-side `git clone`** (`GIT_CLONE_MS=50131`, `:942`) — that is **pattern
(b)'s** transport, not (c)'s. The tar pipeline has no end-to-end run anywhere in
the record.

> **Recorded product-owner decision, 2026-07-31 (DOC-1 D4).** *Building pattern (c)
> IS the measurement.* The alternative — write a standalone tar-transport probe,
> measure it, then build (c) — was considered and rejected: the probe would be most
> of `lib/source.sh` with none of its value, and a second artifact to keep honest.

That decision is what shapes **Phase 1**. Phase 1 is a **thin vertical slice**: a
single disposable script that boots a guest, streams the tracked worktree, unpacks
it, and builds **one** crate. It exists to make the transport fail **before**
`lib/` is built around it, not after. Nothing in Phase 1 survives except two
measurements, one pinned digest, and the knowledge that the pipeline works.

**(b) reuses (c)'s scaffolding with no new mechanism** — guest-side `git clone`
(the repo is public, DOC-1 §6.2) plus the same `cargo install --path` install step
(DOC-2 §12.2 `install_from_branch`/`install_from_path`). Its transport is the one
that *was* measured, which is also why DOC-1 D4 names it the fallback if (c)'s
transport does not work.

**(a) adds only a pattern-aware oracle path** — `cargo install <package> --locked`
from crates.io (DOC-1 §6.3), no delivery step at all
(`source_deliver_released` is a no-op that exists so scenarios stay symmetric,
DOC-2 §12.2). No new infrastructure.

### A.1 The D2/D3 reversal — carry this correctly or the plan is wrong

**`trusty-mpm` is published at v1.0.2.** `crates/trusty-mpm/Cargo.toml` has **no
`publish` key**, so cargo defaults to `publish = true`, and `cargo search
trusty-mpm --limit 5` returned `trusty-mpm = "1.0.2"` on 2026-07-31 (DOC-1 D2 as
amended; DOC-2 §9.5).

Consequences this plan carries end-to-end:

- Pattern (a) covers **all seven crates** (DOC-1 D3), not six.
- `tm` and `trusty-mpm` are asserted **PRESENT** under (a), (b) and (c) alike
  (DOC-1 §7.5 as amended). `expect_a = present` on both rows (DOC-2 §9.3).
- **A pattern-(a) run that does not find `tm` is a FAILURE**, where under the
  superseded D2 it was the expected result.
- All **twelve** in-scope binaries are expected present under all three patterns.
  Seven crates produce twelve binaries (DOC-2 §9.3) — that is not a typo, and
  §7.4's Single-Install gate is why the count matters.
- The `expect_*` columns and the pattern-aware oracle **stay** (DOC-2 §9.5). No
  in-scope row diverges across patterns *today*; the columns are the recording
  mechanism for the next divergence, and collapsing them would mean re-inventing
  them.

Any text you encounter — in this repo or in a stale doc — implying a six-crate
pattern-(a) scope, or a known-absent `tm`, is **wrong**. One such text is known and
is fixed in P8-T5.

### A.2 Phase map

| Phase | Delivers | VM? | Retires |
|---|---|---|---|
| **P1** | Disposable transport spike; real base-image digest | yes | **The transport risk.** DOC-1 §14's headline gap |
| **P2** | Driver, config, exit codes, run registry, `lib/vm.sh`, preflight, `clean` | no | Host-side contract risk |
| **P3** | N1 probe, provisioning, toolchain hand-off, `lib/source.sh` (local), delivery-only scenario | yes | Guest bring-up risk |
| **P4** | `expected-binaries.tsv`, `--check-table` | no | Expectation-table drift |
| **P5** | Pattern (c) installs + the full oracle; RC-2 pinned | yes | Oracle risk; **first full-stack timing** |
| **P6** | Pattern (b) | yes | — |
| **P7** | Pattern (a) | yes | — |
| **P8** | Hardening, docs, measurement write-back | mixed | Doc drift |

---

## B. Global task format

Every task states, without exception:

- **Files** — create/modify, full repo-relative paths.
- **Contract** — the DOC-2 section (and DOC-1 section where relevant) that defines
  it. Every task traces to one.
- **Do** — what to build.
- **Acceptance** — a command and its observable result. Not "it works".
- **Depends** — task IDs required first.

Task IDs are stable. `P3-T4` means phase 3, task 4, forever, and the MANIFEST
references them by that ID.

---

## PHASE 1 — Transport spike (thin vertical slice)

**Goal:** stream the tracked worktree of this repo into a clean Tart guest and
build **one** crate from the unpacked tree, end-to-end, in one disposable script.

**Why this shape.** DOC-1 D4 accepts an unverified transport as the first
implementation target. This phase honours that while limiting the blast radius: if
the pipeline does not work, it fails here, in a 200-line script, before `lib/`
exists to be rewritten. Nothing built in Phase 1 is production code; P3-T4 promotes
the one function that survives and deletes the rest.

**Checkpoint — PASS CONDITION.**

> `bash vmtest-harness/spike/spike-transport.sh` **exits 0** and its final three
> log lines report: (i) a streamed byte count greater than 80,000,000; (ii) the
> guest's `trusty-search --version` output on stdout; (iii) `tart list` containing
> **no** `vmtest-spike-*` entry after teardown.

### P1-T1 — Verify the host dependency set

- **Files:** none (record in MANIFEST).
- **Contract:** DOC-2 §JSON parsing dependency ("the complete host dependency set
  is `tart`, `git`, `jq`, `cargo`, and bash ≥ 3.2"); DOC-1 §4.1.
- **Do:** confirm each tool is present and record its version. Run DOC-2's exact
  functional `jq` smoke test — a `jq` on `PATH` that is a broken symlink or a
  differently-named tool passes `command -v` and fails several minutes into a run.
- **Acceptance:**
  ```sh
  tart --version && git --version && jq --version && cargo --version
  printf '{"a":1}' | jq -e '.a == 1' >/dev/null && echo JQ_OK
  echo "${BASH_VERSINFO[0]}"        # >= 3
  ```
  All exit 0; `JQ_OK` printed; bash major ≥ 3.
- **Depends:** —

### P1-T2 — Spike scaffold: clone, size, boot, poll ready

- **Files:** create `vmtest-harness/spike/spike-transport.sh`.
- **Contract:** DOC-1 §4.3 (full sequence), §8.5 (`--cpu 8 --memory 16384`);
  DOC-2 §10.1 boot-ready poll (**2 s interval, 150 s maximum**), §10.4 (**there is
  no `timeout(1)` on macOS** — background, record PID, poll `kill -0`).
- **Do:** `tart clone` the base image to `vmtest-spike-<utc>-<pid>`, `tart set
  --cpu 8 --memory 16384`, background `tart run --no-graphics`, then poll
  `tart exec <vm> /bin/sh -c 'exit 0'` every 2 s until it returns 0 or 150 s
  elapse. **Poll for the observable condition; never sleep a fixed interval**
  (DOC-1 §4.3). Log elapsed seconds to ready.
- **Acceptance:** script prints `READY after <n>s` with `n` between 10 and 150
  (measured baseline: 34.4 s first boot, 18.0 s subsequent — DOC-2 §10.1), and
  `tart list` shows the VM `running`.
- **Depends:** P1-T1

### P1-T3 — Capture the real base-image digest and write `base-image.pin`

**This task is a hard prerequisite for every later phase that depends on a pinned
base — P2-T5 (preflight), and transitively P3, P5, P6, P7.** It is placed here
because capturing the true digest **requires a live Tart run**, and this is the
first phase that boots a VM.

- **Files:** create `vmtest-harness/base-image.pin`.
- **Contract:** DOC-2 §3.1 (a checked-in file, not a shell constant), §3.2
  (`key<TAB>value`, unknown keys are a preflight error), §3.3 (comparison), §3.4
  (roll procedure — **not** performed here).
- **Do:**
  1. Determine whether `tart` exposes an **untruncated 64-hex digest**. Try, in
     order: `tart list --format json`, `tart list --quiet`, `tart list`. The
     research recorded the digest only **truncated** — `sha256:a8e1...`
     (`vm-install-probe-findings.md:652`, `:685`) — and the full value **was never
     recorded anywhere**. DOC-2 §3.3 flags the introspection invocation as a
     genuine unknown.
  2. **If a full digest is obtainable:** write the pin file in DOC-2 §3.2's exact
     format with the real `digest`, today's `pinned_on`, your handle as
     `pinned_by`, and a `note` naming the `tart` version.
  3. **If it is not obtainable:** do **not** guess and do **not** ship the
     placeholder as if it were a pin. Adopt DOC-2 §3.3's **by-construction
     variant** — clone the pinned OCI reference directly, so the pin is enforced by
     construction with no comparison to get wrong — record `digest` as the value
     you *can* obtain, add `enforcement<TAB>by-construction` to the file, and
     record the finding verbatim in the MANIFEST. Both branches are specified;
     neither requires you to invent anything.
- **Acceptance:**
  ```sh
  grep -Eq '^digest'$'\t''sha256:[0-9a-f]{64}$' vmtest-harness/base-image.pin && echo PIN_REAL
  ```
  prints `PIN_REAL`; **or** the file carries `enforcement<TAB>by-construction` and
  the MANIFEST records why, with the verbatim `tart list` output that proves the
  digest is not retrievable.
- **Depends:** P1-T2

### P1-T4 — N1 precondition probe, inside the spike

- **Files:** modify `vmtest-harness/spike/spike-transport.sh`.
- **Contract:** DOC-2 §6.2 **N1**; DOC-1 §4.2 (position: boot-before-provision).
- **Do:** for each of `cargo`, `rustc`, `rustup`, run `command -v <tool>` under the
  **measured base PATH** literal
  `/bin:/usr/bin:/usr/sbin:/usr/local/bin:/opt/homebrew/bin`
  (`vm-install-probe-findings.md:213`). Assert **non-zero exit and empty stdout**
  for all three. Log which exit code each produced. Assert non-zero rather than a
  specific code: 127 was measured for *invoking* `cargo`, not for `command -v
  cargo`, and pinning a code measured for a different command is exactly the false
  precision this doc set avoids (DOC-2 §6.2).
- **Acceptance:** script prints `N1 PASS` and, for each tool, the observed
  non-zero exit code. A base image that already has cargo fails here — which is a
  **finding** (image drift), not a nuisance.
- **Depends:** P1-T2

### P1-T5 — Provision the spike guest

- **Files:** modify `vmtest-harness/spike/spike-transport.sh`.
- **Contract:** DOC-2 §11.2 (per-tool strategy table), §11.1 (what is actually
  preinstalled), §11.3 (fail, do not repair).
- **Do:** **`mise` and `gh` are PREINSTALLED and must be reused, never installed**
  — DOC-1 §3.3's phrasing is wrong on both and DOC-2 §11.5 amends it. Detect mise
  under `/opt/homebrew/`, assert **no second mise at `$HOME/.local/bin/mise`**, and
  assert `mise --version` returns 0. Then `mise use -g rust@1.91` and
  `mise use -g uv@latest`. **Never run `curl https://mise.run | sh`** (creates a
  second, conflicting mise) and **never `mise self-update`** (hard-fails on a
  Homebrew-managed mise).
- **Acceptance:** the guest reports `rustc 1.91.1` when queried from
  `/Users/admin` under the full guest PATH; total provisioning wall clock is
  logged and is within 3× the measured 30.079 s (`PROVISION_MS=30079`).
- **Depends:** P1-T4

### P1-T6 — **THE SLICE**: stream the worktree and unpack it

This is the task the whole phase exists for.

- **Files:** modify `vmtest-harness/spike/spike-transport.sh`.
- **Contract:** DOC-1 §6.1 (file set, payload, "log the actual streamed byte
  count"); DOC-2 §12.2 `source_deliver_local`; DOC-2 §Shell discipline
  (`pipefail` — without it, a `tar` that fails mid-stream is invisible if
  `tart exec` exits 0, giving a silently truncated tree that then fails to build
  for an unrelated-looking reason).
- **Do:** on the host, enumerate with `git ls-files -co --exclude-standard`, pipe
  through `tar`, pipe through `tart exec -i` to a guest-side unpack into
  `/Users/admin/vmtest-src`. Count the bytes crossing the pipe and log the count.
  The file set is right for two reasons: it **includes uncommitted work** (the
  entire point of pattern (c)) and it **excludes `target/` by construction**,
  because `target/` is gitignored and `--exclude-standard` honours that — not a
  hand-maintained exclude list that can rot.
- **Acceptance:** all four hold —
  ```sh
  # host
  git ls-files -co --exclude-standard | wc -l          # -> H
  # guest, via tart exec
  find /Users/admin/vmtest-src -type f | wc -l         # -> G
  ```
  (1) `G == H`; (2) the logged byte count is > 80,000,000 (DOC-1 §6.1 measured
  ~81 MiB across 5,306 files by `git archive`, a **lower bound** since `-o` adds
  untracked-but-not-ignored files); (3) `test -d /Users/admin/vmtest-src/target`
  is **false**; (4) the pipeline's exit status is 0 with `pipefail` set.
- **Depends:** P1-T5

### P1-T7 — Build one crate from the unpacked tree

- **Files:** modify `vmtest-harness/spike/spike-transport.sh`.
- **Contract:** DOC-2 §7.3 (guest environment prelude: `PATH`,
  `CARGO_TARGET_DIR`, `SKIP_UI_BUILD=1`), §7.4 (worked `tart exec` invocation);
  DOC-1 §8.4 (assert `rustc --version` in the crate directory immediately before
  the build), §8.6 (shared `CARGO_TARGET_DIR`), §7.3 (installs go through cargo
  only — **never `cp`**, for cdhash reasons).
- **Do:** build **`trusty-search`** with `cargo install --path
  /Users/admin/vmtest-src/crates/trusty-search`, under the full prelude, using
  `/bin/sh -c` and **never `-lc`** (a login shell reads rc files, which DOC-1 §5.3
  forbids depending on).
  > **Judgment call, labelled.** `trusty-search` is chosen over `tga` because it is
  > the crate whose in-guest source build was actually measured — 112 s, 409
  > crates, 8 vCPU, under `SKIP_UI_BUILD=1` (`vm-install-probe-findings.md:934`).
  > A failure is therefore attributable to the transport rather than to an
  > unmeasured build. `tga` would add a confounder: its
  > `rust-toolchain.toml` pins `channel = "stable"`, resolving to rustc **1.97.1**
  > inside the crate directory versus the workspace-pinned **1.91.1** at the root
  > (DOC-1 §8.4, measurement K5), so a `tga` spike would also be downloading a
  > second toolchain. That drift is real and P5-T1 asserts it; it does not belong
  > in the risk-retirement slice.
- **Acceptance:** `cargo install --path` exits 0; then in the guest
  `command -v trusty-search` prints a path under `/Users/admin/.cargo/bin`, and
  `trusty-search --version` exits 0. Log the build wall clock and compare it to
  the measured 112 s.
- **Depends:** P1-T6

### P1-T8 — Teardown and host-cleanliness assertion

- **Files:** modify `vmtest-harness/spike/spike-transport.sh`.
- **Contract:** DOC-1 §8.1 (**never** bare-`tart stop` treated as completion —
  write loss reproduced **4 of 5 attempts**, the confirmed root cause of a golden
  image shipping broken), §8.2 (never `tart suspend`); DOC-2 §10.1
  `wait_for_stopped` (**1 s interval, 120 s maximum**), §Shell discipline (trap
  rule).
- **Do:** initiate shutdown, then **poll `tart list` for the observable `stopped`
  state**, then `tart delete`. See **§F-9** — DOC-2 never names what *initiates*
  the shutdown, and the decision rule is there; do not improvise past it.
- **Acceptance:** after the script exits, `tart list | grep vmtest-spike` produces
  **no output**, and the script's exit status is 0.
- **Depends:** P1-T7

### P1-T9 — Record the two measurements this phase produces

- **Files:** modify `docs/research/tart-vm-testing-harness/03-plan/MANIFEST.md`
  (Measurements field of Phase 1).
- **Contract:** DOC-1 §6.1 ("the implementation should log the actual streamed
  byte count so this stops being an estimate"), DOC-1 §14 (the transport gap),
  DOC-2 open items (full base-image digest).
- **Do:** record verbatim — streamed byte count and file count; boot-to-ready
  seconds; provisioning seconds; `trusty-search` build seconds; the base-image
  digest and how it was obtained. These replace three estimates in the doc set and
  are written back to DOC-1/DOC-2 in P8-T4.
- **Acceptance:** MANIFEST Phase 1 `Measurements` contains five numeric values and
  the digest, each with the command that produced it.
- **Depends:** P1-T8

### P1-T10 — Contingency: what happens if the transport does not work

- **Files:** modify MANIFEST (Deviations for Phase 1).
- **Contract:** DOC-1 D4's recorded product-owner decision of 2026-07-31; DOC-1
  §14.
- **Do:** if P1-T6 or P1-T7 fails and the cause is the transport (not a host
  misconfiguration): **do not repair, do not retry, do not invent a workaround.**
  Record the failure verbatim, mark Phase 1 `blocked`, and **stop**. DOC-1 D4
  names the fallback explicitly — pattern (b), whose transport *was* measured at
  `GIT_CLONE_MS=50131`, becomes the first implemented pattern and the order becomes
  (b) → (c) → (a). That re-ordering **changes a settled decision** and therefore
  requires product-owner sign-off before Phase 2 begins; it is not yours to make.
- **Acceptance:** either this task is recorded `N/A — transport verified`, or the
  MANIFEST carries the verbatim failure output, the phase state `blocked`, and an
  explicit note that sign-off is pending.
- **Depends:** P1-T6, P1-T7

### P1-T11 — Update the MANIFEST

- **Files:** modify `docs/research/tart-vm-testing-harness/03-plan/MANIFEST.md`.
- **Contract:** MANIFEST.md §Schema.
- **Do:** set Phase 1 state, paste the **observed result** of the checkpoint
  (actual terminal output, not a claim), list files delivered, record deviations.
- **Acceptance:** `git diff --stat` shows MANIFEST.md modified; the Phase 1
  `Observed result` field contains pasted output including the byte count and the
  post-teardown `tart list`; state is one of `complete` / `blocked`.
- **Depends:** P1-T9, P1-T10

---

## PHASE 2 — Host-side skeleton: driver, config, registry, `lib/vm.sh`, preflight, `clean`

**Goal:** everything the harness does **before it touches a guest**, plus the
complete `tart` boundary module. No provisioning, no install, no oracle.

**Why here.** Phase 1 proved the transport with a script that cheats on every
contract — no exit codes, no registry, no config, no trap. Phase 2 builds the
contracts that the rest of the harness is allowed to assume. It is entirely
host-side and therefore fast to iterate: no phase after this one should be
debugging argument parsing while a VM boots.

**Checkpoint — PASS CONDITION.**

> All three hold, in one session:
> 1. `vmtest run local --dry-run` **exits 0**, prints an effective-configuration
>    banner in which every key carries an origin marker (`default` / `env` /
>    `flag`), and `tart list` afterwards shows **no new VM**.
> 2. `VMTEST_CPU=4 vmtest run local --dry-run` prints `cpu 4 (env)`, and
>    `vmtest run local --cpu 2 --dry-run` prints `cpu 2 (flag)`.
> 3. `vmtest clean --dry-run` correctly classifies a hand-created stopped
>    `vmtest-*` VM as `ORPHANED (would delete)` and a `keep`-marked one as
>    `KEPT (would not delete)`, deleting neither.

### P2-T1 — Driver skeleton, `die()`, traps, cleanup

- **Files:** create `vmtest-harness/vmtest`.
- **Contract:** DOC-2 §2 (exit-code table), §12.4 (`die`, write-once
  `VMTEST_EXIT`, "first classified failure wins"), §Shell discipline (bash **3.2**
  target, `set -euo pipefail` set **once** at the top of the driver before sourcing
  any `lib/` file, the trap/cleanup rule and its five properties).
- **Do:** shebang `#!/usr/bin/env bash`; assert `[ "${BASH_VERSINFO[0]}" -ge 3 ]`;
  `set -euo pipefail`; implement `die()` exactly as DOC-2 §12.4 gives it; install
  the three traps (`EXIT`, `INT`→130, `TERM`→143 — the explicit `exit` in the
  signal traps is **not decoration**: after a trap handler returns, bash may resume
  the interrupted command); implement `vmtest_cleanup` satisfying all five listed
  properties, including capturing `$?` on its **very first line** and using
  `${VAR:-}` for every variable it touches (`set -u` and traps interact badly).
  Subcommand dispatch for `run` / `clean` / `--check-table`; unknown → **exit 2**.
  - **bash 3.2 is the target and it shapes the code.** No `declare -A`, no
    namerefs, no `mapfile`, no `${var,,}`, no `globstar`, no `wait -n`. This is
    *why* §3, §8 and §9 all use the same `key<TAB>value` TSV — the TSV files are
    the substitute for a hash, not a stylistic preference.
  - Two gotchas DOC-2 states so you do not rediscover them: `set -e` is
    **suppressed inside a condition**, so a lib function whose failure must abort
    must never be called in `if`/`&&`/`||`/`!` context; and `local x=$(cmd)`
    **swallows** `cmd`'s status — declare first, assign second.
- **Acceptance:** `bash -n vmtest-harness/vmtest` is silent; `vmtest-harness/vmtest`
  with no arguments exits **2** and prints usage on **stderr**;
  `vmtest-harness/vmtest bogus` exits **2**.
- **Depends:** —

### P2-T2 — Configuration: `vmtest.defaults`, TSV reader, three-tier precedence

- **Files:** create `vmtest-harness/vmtest.defaults`; modify
  `vmtest-harness/vmtest`.
- **Contract:** DOC-2 §8.1 (three tiers), §8.2 (**the complete example file is
  given verbatim — copy it**), §8.3 (precedence and origin reporting), §3.2 (TSV
  format rules: `key<TAB>value`, `#` comments, blank lines ignored, exactly one
  line per key, **unknown keys are an error** so a typo cannot silently become
  "unpinned").
- **Do:** copy DOC-2 §8.2's file verbatim. Implement one `awk`-based reader used
  by all three TSV files (§3.1's "one parser, three files"). Implement the
  **mechanical** override mapping — uppercase the key, prefix `VMTEST_`; there is
  no table to maintain and no key that is overridable-in-principle but forgotten in
  practice. CLI flags exist **only** for `--cpu`, `--memory`, `--runid`, `--keep`,
  `--dry-run` (§8.2); adding a flag per tunable would give the driver a surface
  larger than its behaviour.
  - See **§F-5**: DOC-2 assigns no module to the TSV reader. The decision rule is
    there.
- **Acceptance:**
  ```sh
  bash -c '. vmtest-harness/vmtest --source-only 2>/dev/null; conf_get cpu'   # -> 8
  ```
  or equivalent direct invocation returns `8` for `cpu`, `16384` for `memory_mib`,
  `2700` for `install_timeout`; a defaults file with an injected unknown key makes
  the driver exit **10**.
- **Depends:** P2-T1

### P2-T3 — `--runid` generation, validation, and the atomic run registry

- **Files:** modify `vmtest-harness/vmtest`.
- **Contract:** DOC-2 §4.1 (optional, auto-generated when omitted), §4.2 (format
  `YYYYMMDDThhmmssZ-<pid>`; validation regex `^[A-Za-z0-9][A-Za-z0-9-]{0,31}$`;
  violation is **exit 2** before any VM work), §4.3 (registry, run-directory
  contents, concurrency warning).
- **Do:** acquire the run by **`mkdir "<registry root>/<runid>"`**. `mkdir` either
  creates or fails and two concurrent callers cannot both succeed — **a
  test-then-create sequence (`[ -d ... ] || mkdir ...`) is a race and must not be
  used.** Registry root is
  `${VMTEST_STATE_DIR:-$HOME/.local/state/vmtest-harness}/runs/`. Write `pid`,
  `vm`, `pattern`, `started` immediately on acquisition. **Warn — do not fail —
  when another run directory holds a live PID** (§4.3: the harness cannot know the
  operator's host, and refusing a legitimate second run on a large machine would be
  worse than a warning ignored on a small one).
- **Acceptance:** `vmtest run local --runid 'a b' --dry-run` exits **2**;
  `vmtest run local --runid $(printf 'x%.0s' $(seq 40)) --dry-run` exits **2**;
  running two `--runid dup` invocations where the first holds the lock makes the
  second exit **10** naming the conflicting run; an auto-generated id matches
  `^[0-9]{8}T[0-9]{6}Z-[0-9]+$`.
- **Depends:** P2-T2

### P2-T4 — `lib/vm.sh` — the OS boundary

- **Files:** create `vmtest-harness/lib/vm.sh`.
- **Contract:** DOC-2 §12.2 (`lib/vm.sh` surface — **eleven** signatures, given in
  full), §12.1 (calling conventions), §10.1/§10.2 (poll and watchdog parameters),
  §10.4 (**no `timeout(1)` on macOS**); DOC-1 §3.2 (the designed extension seam for
  Linux — §12.2), §8.1, §8.2.
- **Do:** implement `vm_clone`, `vm_size`, `vm_boot`, `vm_wait_ready`, `vm_state`,
  `vm_exec`, `vm_exec_raw`, `vm_exec_stdin`, `vm_wait_for_stopped`,
  `vm_assert_stopped`, `vm_delete`, exactly per §12.2's return/emit column.
  - **`vm_exec` deliberately does not die on non-zero** — it returns the guest's
    status verbatim so a caller can distinguish "the command failed" from "the
    harness failed", which is precisely what N1 needs, since N1's *expected* result
    is a non-zero exit. Callers requiring success wrap with `|| die 50 "..."`.
  - Build the watchdog from shell primitives: background the command, record the
    PID, poll `kill -0 <pid>` at the site's interval until the deadline, then kill
    and reap. **Do not reach for `timeout`/`gtimeout`** — that adds a Homebrew
    dependency to a harness whose host requirements are otherwise `tart`, `git`,
    `jq`, `cargo`, and would fail on a clean machine in a way that looks like a
    harness bug.
  - `vm_wait_ready` polls at a **fixed** 2 s interval, **not** exponential backoff:
    the distribution is tight and known (~18–35 s), so backoff's only effect is to
    overshoot a ready guest, in exchange for saving `tart exec` calls whose cost was
    measured as negligible (K1d).
  - **Timeout behaviour is uniform (§10.3): no retry, ever.** A retry that succeeds
    converts a reproducible failure into an intermittent one, and DOC-1 §8.2 shows
    a case where retrying is structurally incapable of helping. Classify by phase,
    report the budget *and* the `vmtest.defaults` key that changes it, and let the
    cleanup trap still run.
- **Acceptance:** two mechanical checks —
  ```sh
  grep -rln 'tart' vmtest-harness --include='*.sh' --include='vmtest'
  ```
  lists **only** `vmtest-harness/lib/vm.sh` (this is the DOC-1 §3.2 invariant and
  it must stay true for the life of the harness); and `bash -n
  vmtest-harness/lib/vm.sh` is silent. `lib/` files define **functions and nothing
  else** — no top-level statements, no `set`, no side effects at source time
  (§12.1); a stray `set +e` in a library would silently disarm the driver.
- **Depends:** P2-T1

### P2-T5 — Preflight

- **Files:** modify `vmtest-harness/vmtest` (or `vmtest-harness/lib/vm.sh` for the
  VM-state checks only).
- **Contract:** DOC-1 §4.1 (the check table and the **stopped-state refusal**),
  §8.3; DOC-2 §2 (**exit 10** for every preflight refusal), §3.3 (digest
  comparison), §8.4 (host-capacity table), §JSON parsing dependency (the `jq`
  functional smoke test).
- **Do:** in order — `tart` on `PATH`; `jq` present **and functional**; base-image
  digest matches `base-image.pin` (or is enforced by construction per P1-T3);
  **every** existing VM the harness would touch is `stopped`; no runid collision;
  host capacity per §8.4's four rows (total physical memory **hard-fails**,
  available memory and core counts **warn**).
  - **Refuse; do not repair.** DOC-1 §4.1 is exact: *do not attempt to stop it, do
    not attempt to resume it, do not retry.* Both §8 failure modes are
    unrecoverable-by-retry, and an automated "fix it up and carry on" path is
    exactly how a broken image shipped once already.
  - Core count uses `hw.physicalcpu`, **not** `hw.ncpu`: on Apple silicon `hw.ncpu`
    counts efficiency cores, which do not contribute to a build the way the
    measured 8-vCPU guest's cores did, so counting the wrong cores produces a
    reassuring warning-free run on a machine that will be slow.
  - The **24 GiB** `host_min_memory_gib` default is a labelled judgment call in
    DOC-2 §8.4 (16 GiB guest + 8 GiB host), deliberately conservative and tunable
    *because* it is a guess. Do not "fix" it.
- **Acceptance:** temporarily corrupt the pin's `digest` value → `vmtest run local
  --dry-run` exits **10** and prints **both** the pinned digest and what was
  actually found; rename `jq` out of `PATH` → exits **10** with the host-dependency
  message; with the pin restored, preflight passes.
- **Depends:** P2-T2, P2-T3, P2-T4, **P1-T3**

### P2-T6 — `vmtest clean`

- **Files:** modify `vmtest-harness/vmtest`.
- **Contract:** DOC-2 §5.1 (the four-condition definition of *orphaned* — **all
  four**), §5.2 (how in-progress runs are distinguished; the PID-reuse edge),
  §5.3 (`--keep` and the `keep` marker), §5.4 (the four cases and `--dry-run`).
- **Do:** implement the classifier. **`clean` never issues `tart stop`, never
  issues `tart suspend`, and never deletes a VM that is not already `stopped`** —
  it inherits DOC-1 §8.1/§8.3 wholesale. Implement `--dry-run` (full
  classification, prints the verdict for every candidate, deletes nothing) and
  `--include-kept`.
  - The **PID-reuse edge** is accepted deliberately and stated plainly: a recycled
    PID makes `clean` skip a genuine orphan, leaving a VM for a human. The
    opposite error — deleting a VM out from under a live run — **cannot occur by
    this mechanism**. Accepting a conservative false negative to make the dangerous
    false positive impossible is the trade; do not try to eliminate it with
    start-time comparisons.
- **Acceptance:** construct four fixtures and run `vmtest clean --dry-run` —
  (i) stopped `vmtest-*` with no registry entry → `ORPHANED (would delete)`;
  (ii) same, with a `keep` marker → `KEPT (would not delete)`;
  (iii) a registry directory with no matching VM → `PRUNE (bookkeeping)`;
  (iv) a `vmtest-*` VM in state `running` with no registry entry → the command
  **refuses**, prints the VM and its state, and exits **10**. Nothing is deleted in
  any of the four.
- **Depends:** P2-T4, P2-T5

### P2-T7 — Wire the checkpoint: `vmtest run <pattern> --dry-run`

- **Files:** modify `vmtest-harness/vmtest`.
- **Contract:** DOC-2 §8.2 (lists `--dry-run` among the five CLI flags), §8.3
  (effective-configuration banner with origins). **See §F-1 — DOC-2 defines
  `clean --dry-run` but never defines `run --dry-run`.** The decision rule in §F-1
  is binding; do not extend it.
- **Do:** `run --dry-run` performs preflight, prints the effective configuration
  with origin markers plus the bash version (§Shell discipline: so a bug report
  says which bash produced it), acquires and immediately releases the run
  registry entry, and **stops before `tart clone`**. It creates no VM.
- **Acceptance:** the phase checkpoint's three conditions, verbatim. Note
  specifically that *"a run whose log does not state its own sizing cannot be
  compared against DOC-1 §9's cost baseline, and comparing against that baseline is
  most of what the numbers are for"* (§8.3) — the banner is load-bearing, not
  decoration.
- **Depends:** P2-T5, P2-T6

### P2-T8 — Update the MANIFEST

- **Files:** modify `docs/research/tart-vm-testing-harness/03-plan/MANIFEST.md`.
- **Contract:** MANIFEST.md §Schema.
- **Do:** state, observed result (paste all three checkpoint commands and their
  output), files delivered, deviations.
- **Acceptance:** MANIFEST Phase 2 `Observed result` contains pasted terminal
  output for all three checkpoint conditions, including the `tart list` that shows
  no VM was created.
- **Depends:** P2-T7

---

## PHASE 3 — Guest bring-up: N1, provisioning, toolchain hand-off, source delivery

**Goal:** a `vmtest run local` that boots a guest, proves it has no toolchain,
provisions it, streams the source in, and tears down — with **no installs and no
oracle yet**.

**Why this shape.** The scenario file grows across phases. At the end of Phase 3
`scenarios/install-local.sh` contains step 1 of DOC-2 §12.5's skeleton and nothing
else. This is deliberate: it gives Phase 3 a runnable checkpoint without inventing
a driver flag to stop early, and it keeps the scenario honest — a scenario is *a
sequence of install steps plus the expectations that follow from them* (DOC-1
§3.6), and at this point there are no install steps, so there are no expectations.

**Checkpoint — PASS CONDITION.**

> `vmtest run local` **exits 0**, and its log shows, in order: `N1 PASS` with a
> non-zero exit recorded for each of `cargo`, `rustc`, `rustup`; a provisioning
> block ending with `rustc_version 1.91.1`; a streamed byte count > 80,000,000;
> and a teardown after which `tart list` contains **no** `vmtest-*` entry.
> `$VMTEST_RUNDIR` is removed, and `ls "${VMTEST_STATE_DIR:-$HOME/.local/state/vmtest-harness}/runs/"`
> is empty.

### P3-T1 — N1 precondition probe

- **Files:** create `vmtest-harness/lib/verify.sh` (see §F-4 for why the probes
  live here); modify `vmtest-harness/vmtest`.
- **Contract:** DOC-2 §6.2 **N1** (exact command, expected exit, expected output
  shape, predicate, **exit 30** on failure), §6.3 (**pinned** lifecycle position),
  §6.1 (why the probe had to be split at all); DOC-1 §4.2.
- **Do:** implement `negative_probe_n1`, invoked through `vm_exec_raw` — the
  **raw** variant, because at this point `VMTEST_GUEST_ENV` is still in its
  **base** lifetime (§7.3: base path only, no cargo, no mise, no cargo variables)
  and that is exactly what makes N1 meaningful.
  - Position it at `boot → vm_wait_ready → [N1] → provision` and nowhere else.
    This is the only window in which the guest genuinely lacks cargo, and it is
    the assertion a golden image structurally destroys — one of the two stated
    reasons the harness does not bake one (DOC-1 §4.3).
- **Acceptance:** on a fresh guest, `N1 PASS` with three recorded non-zero exits;
  then, as a deliberate negative control, run `mise use -g rust@1.91` **before**
  N1 in a throwaway invocation and confirm the driver exits **30** without
  proceeding to provisioning.
- **Depends:** P2-T8

### P3-T2 — Provisioning

- **Files:** create `vmtest-harness/lib/provision.sh`.
- **Contract:** DOC-2 §11.1 (**verified** preinstall state), §11.2 (per-tool
  strategy and the three-assertion mise detection command), §11.3 (**fail, do not
  repair** — exit 40), §11.5 (the amendment to DOC-1 §3.3); §12.2
  (`provision_guest`, `provision_detect_mise`, `provision_load_toolchain`).
- **Do:** implement the three functions with §12.2's exact signatures. Detection
  asserts all three of: `mise` resolves **under `/opt/homebrew/`**; **no second
  mise at `$HOME/.local/bin/mise`** — the exact artefact `mise.run` would create,
  so asserting its absence turns "somebody ran the forbidden command" from a
  mystery into a named failure; and `mise --version` returns 0. Install only
  `rust@1.91` and `uv@latest`.
  - **If detection fails, exit 40. Do not fall back to installing mise.** A
    `tahoe-base` without a Homebrew mise at `/opt/homebrew/bin/mise` **is not the
    base image this harness is pinned to** — it is a drift signal, and §3's whole
    purpose is to catch drift. This is not hypothetical: DOC-1 §5.3 records a
    golden image that shipped with `~/.zshenv` missing, which made `cargo` return
    **127** under both `/bin/sh` and `/bin/zsh` and presented as "cargo is not
    installed". A missing dotfile and a duplicated toolchain manager are the same
    category of failure.
- **Acceptance:** `vmtest run local` logs a provisioning block whose total wall
  clock is within 3× of the measured 30.079 s, with `gh` detected as already
  present (measured 616 ms — a no-op); a fixture where `$HOME/.local/bin/mise` is
  created before provisioning makes the run exit **40** with the second-mise
  message.
- **Depends:** P3-T1

### P3-T3 — Toolchain hand-off: `toolchain.tsv` and `VMTEST_GUEST_ENV`

- **Files:** modify `vmtest-harness/lib/provision.sh`, `vmtest-harness/lib/vm.sh`.
- **Contract:** DOC-2 §7.1 (what provisioning writes, where, and its **measured**
  seven values), §7.2 (why a guest file *and* a host copy), §7.3 (composition
  happens in **exactly one place**: `vm_exec`), §7.4 (the worked invocation and its
  four deliberate details); DOC-1 §5.2, §5.3, §3.3, §8.6.
- **Do:** provisioning writes `/Users/admin/.vmtest/toolchain.tsv`; the driver
  reads it back over `tart exec` into `$VMTEST_RUNDIR/toolchain.tsv`; the guest
  copy is **kept**, because it is what makes a `--keep` VM inspectable by a human
  reproducing a failing command by hand. Compose `VMTEST_GUEST_ENV` — `PATH`,
  `CARGO_TARGET_DIR`, `SKIP_UI_BUILD=1`, each followed by `export` — inside
  `vm_exec` and nowhere else. Scenarios never build a prefix and never see one.
  - **Ordering is load-bearing, not cosmetic:** `~/.cargo/bin` **must precede** the
    mise shims directory. mise's rust backend delegates to rustup, so putting the
    real rustup shims first is what allows rustup's *directory-based*
    `rust-toolchain.toml` resolution to work — which is precisely the mechanism
    DOC-1 §8.4 depends on. Reverse the order and §8.4's assertion silently stops
    measuring what it claims to measure.
  - **`VMTEST_GUEST_ENV` has two lifetimes** (§7.3): base before provisioning,
    full after. It is the only global that changes after preflight (§12.3).
- **Acceptance:** `$VMTEST_RUNDIR/toolchain.tsv` contains all seven keys of §7.1
  with `rustc_version 1.91.1`; `guest_path` begins with
  `/Users/admin/.cargo/bin:/Users/admin/.local/share/mise/shims:`; a `vm_exec` of
  `printf '%s' "$PATH"` returns that exact string.
- **Depends:** P3-T2

### P3-T4 — Promote the spike into `lib/source.sh`; delete the spike

- **Files:** create `vmtest-harness/lib/source.sh`; **delete**
  `vmtest-harness/spike/`.
- **Contract:** DOC-2 §12.2 `source_deliver_local` (signature, and "**emits the
  streamed byte count**, which DOC-1 §6.1 explicitly asks be logged"), §12.1
  (positional string arguments; the value channel is stdout and carries **at most
  one value**; diagnostics **always** to stderr because §1's oracle parses stdout);
  DOC-1 §6.1.
- **Do:** port P1-T6's pipeline into `source_deliver_local <vm_name> <host_repo>
  <guest_dir>` through `vm_exec_stdin`. Emit **only** the byte count on stdout;
  everything else goes to stderr. Then delete the spike directory — its job was to
  fail fast, and it has either done that or been superseded.
  - **Naming tension, recorded (§12.2):** DOC-1 §3.4 calls `source.sh` "source
    delivery" while DOC-1 §12.1 wants reusable **install-step** functions, so
    `install_from_path` / `install_from_registry` (P5-T1, P7-T1) also live here.
    Read `source.sh` as *"source acquisition and installation"*. A later split into
    `lib/install.sh` is permitted and would change no scenario, because scenarios
    call the functions, not the file.
- **Acceptance:** `vmtest run local` logs the byte count; `ls vmtest-harness/spike`
  fails; `git log --stat` shows the spike deleted in the same commit that adds
  `lib/source.sh`.
- **Depends:** P3-T3, P1-T6

### P3-T5 — `scenarios/install-local.sh` (delivery only) and scenario dispatch

- **Files:** create `vmtest-harness/scenarios/install-local.sh`; modify
  `vmtest-harness/vmtest`.
- **Contract:** DOC-2 §12.5 (the worked skeleton — implement **step 1 only** at
  this phase), §12.1, §12.4 (scenarios do **not** call `die` with a code of their
  own — they call lib functions, which die with their own phase code, so a scenario
  stays a description of steps and expectations and never encodes the exit-code
  table); DOC-1 §3.6. **See §F-6** — the driver's pattern→file→function dispatch is
  unspecified; the decision rule is there.
- **Do:** the scenario contains `scenario_install_local()` with step 1 of §12.5 and
  a `log` of the byte count. Note what the skeleton must **not** contain: no
  `tart`, no `PATH`, no timeout, no exit code, no `if` around a lib call.
- **Acceptance:** `grep -E 'tart|PATH=|exit ' vmtest-harness/scenarios/install-local.sh`
  produces **no output**; `vmtest run local` reaches teardown and exits 0.
- **Depends:** P3-T4

### P3-T6 — `~/.zshenv`: written, never depended on

- **Files:** modify `vmtest-harness/lib/provision.sh`.
- **Contract:** DOC-2 §11.4 (the reconciliation, stated as a blockquote rule);
  DOC-1 §5.3.
- **Do:** provisioning **may** write `~/.zshenv` as a convenience for a human
  inspecting a `--keep` VM. **No harness logic may read it, source it, or depend on
  it having been written.** The measured step exists (`STEP_ZSHENV_MS=617`), so
  writing it costs nothing. The reconciliation must be explicit in a comment **or
  someone will delete one rule and trust the other**.
- **Acceptance:** the file is written in the guest, and `grep -rn 'zshenv'
  vmtest-harness --include='*.sh' --include=vmtest` shows it referenced **only** in
  the writing step — never in a read, source, or conditional. The deliberate
  deletion drill that proves this is P8-T1.
- **Depends:** P3-T2

### P3-T7 — Run the checkpoint and update the MANIFEST

- **Files:** modify `docs/research/tart-vm-testing-harness/03-plan/MANIFEST.md`.
- **Contract:** MANIFEST.md §Schema.
- **Do:** run `vmtest run local` to completion; paste the observed log; record
  files delivered and deviations. Also record the second boot-to-ready measurement
  (subsequent boots measured ~18 s) for comparison against P1.
- **Acceptance:** MANIFEST Phase 3 `Observed result` contains the four log
  landmarks named in the checkpoint plus the empty-registry `ls`.
- **Depends:** P3-T5, P3-T6

---

## PHASE 4 — `expected-binaries.tsv` and `--check-table`

**Goal:** the authoritative expectation table, and the self-diff that keeps it
honest. Host-only, no VM.

**Why before the oracle.** The oracle consumes this table. DOC-1 §7.4 is blunt
about the stakes: the Single-Install gate *"is only ever as good as §7.2's table.
It cannot detect the loss of a binary it has never heard of — an omitted row is
not a weaker assertion, it is **no** assertion, and it fails silently and
permanently."* That is not hypothetical either: the `trusty-memory-mcp-bridge`
omission (DOC-2 §9.3) would have produced exactly that blindness. Build the table
and its differ before anything asserts against it.

**Checkpoint — PASS CONDITION.**

> `vmtest --check-table` **exits 0** against the workspace as it stands, printing
> no ADDED/REMOVED/CHANGED findings. Then, with one row deliberately deleted from
> `expected-binaries.tsv`, it **exits 60** and prints exactly one `REMOVED` finding
> naming that `(package, binary)` pair. The row is restored afterwards and the
> command exits 0 again.

### P4-T1 — Seed `expected-binaries.tsv`

- **Files:** create `vmtest-harness/expected-binaries.tsv`.
- **Contract:** DOC-2 §9.1 (**nine** columns, tab-separated, one header row, `#`
  comments, `LF` endings), §9.2 (`[package] name` is the key; `package` + `binary`
  is the composite primary key), §9.3 (**the seed content is given verbatim —
  copy it**), §9.4 (`req_features` and the implicit target); DOC-1 §7.2, §7.5, D3.
- **Do:** copy §9.3's block verbatim, including the out-of-scope rows. Do not
  re-derive it by hand.
  - **`in_scope` exists rather than two files** because `--check-table` must diff
    against **every** `[[bin]]` in the workspace or it cannot detect a newly added
    binary: a binary absent from a scope-only file is indistinguishable from one
    that was never in scope.
  - **Twelve in-scope rows, seven packages.** Both `trusty-mpm` rows carry
    `expect_a = present` (§A.1). `tga`'s `package` is `tga` while its `crate_dir`
    is `trusty-git-analytics` — the discontinuity DOC-1 D3 warns about.
  - `req_features` is carried because four in-scope binaries are gated behind
    `required-features` that are *currently* in their crate's `default` set. If a
    future change drops one, `cargo install` **succeeds and silently produces no
    binary** — a green install with a missing daemon, exactly DOC-1 §7.4's failure
    mode.
- **Acceptance:**
  ```sh
  awk -F'\t' 'NR>1 && $1 !~ /^#/ && NF!=9 {print NR": "NF}' vmtest-harness/expected-binaries.tsv
  ```
  prints nothing (every row has nine fields); `awk -F'\t' '$6=="yes"' | wc -l`
  returns **12**; `grep -c 'trusty-memory' ` shows the **three** `trusty-memory`
  binary rows including `trusty-memory-mcp-bridge`.
- **Depends:** P2-T8

### P4-T2 — `--check-table` self-diff

- **Files:** modify `vmtest-harness/vmtest`.
- **Contract:** DOC-2 §9.6 (source of truth **confirmed**; the six-step algorithm;
  exit **60**; **no auto-fix**), §9.4 (implicit targets); DOC-1 §7.2.
- **Do:** read actual targets via **`cargo metadata --no-deps --format-version 1`**
  and `jq`, not by parsing `Cargo.toml` files. Three real defects avoided:
  `cargo metadata` reports **implicit** targets (`crates/trusty-agents-local` has a
  `src/main.rs` and no `[[bin]]` section, so manifest-parsing misses it entirely
  and would report a spurious deletion); it resolves workspace-inherited fields;
  and it enumerates the non-`crates/*` path member
  `crates/trusty-agents/ui/src-tauri` that a `crates/*/Cargo.toml` glob would skip.
  Implement ADDED / REMOVED / CHANGED, and RENAMED as a **suggestion only, never
  applied automatically**.
  - **It does not auto-fix.** A table that rewrites itself to match reality asserts
    nothing — the human edit *is* the review step, and removing it would turn the
    authoritative expectation source into a mirror.
  - Compare **columns 1–5 only**. `in_scope` and the three `expect_*` columns are
    human judgments about scope, not facts about the workspace, and nothing can
    derive them.
- **Acceptance:** the phase checkpoint, verbatim. Additionally, changing a
  `bin_path` value in the TSV produces exactly one `CHANGED` finding and exit 60.
- **Depends:** P4-T1

### P4-T3 — Reconcile the seed against today's workspace

- **Files:** possibly modify `vmtest-harness/expected-binaries.tsv`; modify
  MANIFEST.
- **Contract:** DOC-2 §9.3, §9.6.
- **Do:** DOC-2's seed was enumerated on 2026-07-31 (26 explicit `[[bin]]` targets
  across 20 manifests, plus one implicit). If `--check-table` reports findings on
  the unmodified workspace, the workspace has moved since. **Record every finding
  verbatim in the MANIFEST**, then apply the human edit — adding a genuinely new
  binary with `in_scope=no` unless it belongs to one of D3's seven packages, in
  which case it is `in_scope=yes` with `present` in all three `expect_*` columns.
  - **Do not silently widen D3's scope.** DOC-2 §9.3 note 2 records that
    `trusty-review` is a publishable crate with a daemon and a `/health` endpoint
    that is **not** in D3's seven, carried `in_scope=no` faithfully to D3, and that
    *"whether D3's scope should include it is a design question this document does
    not decide, but it should be decided knowingly rather than by omission."* Same
    rule for anything new: knowingly, in a PR, not as a side effect of this task.
- **Acceptance:** `vmtest --check-table` exits 0; the MANIFEST records either
  "no drift since DOC-2 §9.3" or the exact findings and the edit made.
- **Depends:** P4-T2

### P4-T4 — Scope helpers, including the deduplication the oracle needs

- **Files:** modify `vmtest-harness/vmtest` (or `lib/verify.sh`, per §F-5).
- **Contract:** DOC-2 §12.5 (calls `tsv_scope_crate_dirs`, "column 2 where
  in_scope=yes"), §9.1, §9.3. **See §F-3** — the twelve in-scope rows contain only
  **seven** distinct `crate_dir` values, and DOC-2 never says to deduplicate.
- **Do:** implement `tsv_scope_crate_dirs` (unique `crate_dir`, in first-appearance
  order), `tsv_scope_packages` (unique `package`), and `tsv_expect <package>
  <binary> <pattern>`. Apply §F-3's decision rule.
- **Acceptance:** `tsv_scope_crate_dirs` emits **7** lines, beginning
  `trusty-search` and containing `trusty-git-analytics` (**not** `tga` — that is
  the package name, and `--path` takes the directory); `tsv_scope_packages` emits
  **7** lines including `tga` and `trusty-mpm`; `tsv_expect trusty-mpm tm a`
  returns `present`.
- **Depends:** P4-T1

### P4-T5 — Update the MANIFEST

- **Files:** modify `docs/research/tart-vm-testing-harness/03-plan/MANIFEST.md`.
- **Contract:** MANIFEST.md §Schema.
- **Do:** state, observed result (paste the three `--check-table` invocations of
  the checkpoint), files delivered, deviations — including any reconciliation from
  P4-T3.
- **Acceptance:** Phase 4 `Observed result` shows exit 0, then exit 60 with the
  `REMOVED` finding, then exit 0 again.
- **Depends:** P4-T3, P4-T4

<!-- APPEND-POINT -->
