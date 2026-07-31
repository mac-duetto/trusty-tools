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

<!-- APPEND-POINT -->
