# vmtest-harness/lib/verify.sh — the assertion oracle (DOC-1 §3.5, DOC-2 §12.2).
#
# AT PLAN PHASE 3 THIS FILE CONTAINS THE N1 PRECONDITION PROBE AND NOTHING ELSE.
# `negative_probe_n2` (P5-T3) and the six `verify_*` signatures of DOC-2 §12.2
# (P4/P5) land later.
#
# WHY THE PROBES LIVE HERE — plan §F-4, resolved by NARROWEST READING. DOC-2
# §12.5 calls `negative_probe_n2` and §6.2 specifies both probes in full, but
# §12.2's four module surfaces list `vm.sh`, `provision.sh`, `source.sh` and
# `verify.sh` and NEITHER PROBE APPEARS IN ANY OF THEM; DOC-1 §3's component
# tree has no fifth module. The probes are assertions with pass predicates
# (§6.2 states both as `PASS iff …`), which is exactly what `verify.sh` is for.
# They die with 30, not 60, because §2 classifies them as their own phase —
# that is a property of the EXIT CODE, not of the file.
#
# This file never calls the virtualisation CLI directly (DOC-1 §12.2); it goes
# through `lib/vm.sh`. `die`, `log`, `conf_get` are driver infrastructure
# (plan §F-5) and are shell-global by the time this file is sourced.
#
# CONVENTIONS (DOC-2 §12.1): positional string arguments; the return channel is
# the exit status; diagnostics ALWAYS to stderr; functions call `die`, not
# `exit`; THIS FILE DEFINES FUNCTIONS AND NOTHING ELSE.

# --- N1 — precondition probe (DOC-2 §6.2, §6.3; DOC-1 §4.2) ----------------
#
# negative_probe_n1 <vm_name>
#
# Asserts that the guest genuinely lacks a Rust toolchain at the one instant it
# can be asserted. Predicate, verbatim from §6.2:
#
#     N1 PASS iff exit != 0 AND stdout is empty, for each of cargo, rustc, rustup
#
# NON-ZERO is asserted, not 127. §6.2 is explicit about why: 127 was measured
# for *invoking* `cargo`, not for `command -v cargo`, and `command -v` returns 1
# on not-found. Pinning a code measured for a different command would be false
# precision. The code that WAS observed is logged either way.
#
# On failure: die 30, and do not proceed to provisioning. A guest that already
# has cargo is not the guest this harness claims to test, and the likeliest
# cause is base-image drift (DOC-2 §3) — a FINDING, not a nuisance.
#
# LIFECYCLE POSITION IS PINNED (§6.3): boot -> vm_wait_ready -> [N1] -> provision.
# This is the only window in which the guest genuinely lacks cargo, and it is
# the assertion a golden image structurally destroys — one of the two stated
# reasons the harness does not bake one (DOC-1 §4.3).
negative_probe_n1() {
    local vm="$1"

    # POSITION GUARD. The plan (P3-T1) requires N1 be invoked through the RAW
    # exec variant *because* `VMTEST_GUEST_ENV` is still in its BASE lifetime
    # (§7.3: base path only, no cargo, no mise, no cargo variables) — "and that
    # is exactly what makes N1 meaningful". That reasoning is only sound if the
    # base lifetime actually still holds, so it is CHECKED rather than assumed.
    # Called after provisioning, N1 would probe a toolchain the harness itself
    # installed and fail for a reason that has nothing to do with the base
    # image; this turns a mis-ordering into a named failure at the probe.
    case "${VMTEST_GUEST_ENV:-}" in
        *'.cargo/bin'* | *'mise/shims'*)
            die 30 'N1 was invoked with VMTEST_GUEST_ENV already in its FULL lifetime (§7.3), i.e. AFTER provisioning. DOC-2 §6.3 pins N1 at boot -> vm_wait_ready -> [N1] -> provision and nowhere else.' ;;
    esac

    # §6.2's command is self-prefixed with the measured base PATH, and §12.2
    # assigns N1 to `vm_exec_raw` — the no-prefix variant. Both are satisfied by
    # passing the base prelude IN THE COMMAND STRING: the probe carries its own
    # PATH exactly as §6.2 shows it, and it takes that prelude from
    # $VMTEST_GUEST_ENV, whose base lifetime the guard above has just asserted.
    # Duplicating §7.1's base-path literal here would give the harness a second
    # copy to keep in step with the driver's.
    local tool out rc fail=0 codes=''
    for tool in cargo rustc rustup; do
        rc=0
        out=$(vm_exec_raw "$vm" "${VMTEST_GUEST_ENV:-} command -v $tool" 2>/dev/null) || rc=$?
        codes="${codes} ${tool}=${rc}"
        if [ "$rc" -eq 0 ]; then
            log "N1: '$tool' is PRESENT (exit 0) — precondition VIOLATED"
            fail=1
        elif [ -n "$out" ]; then
            log "N1: '$tool' produced stdout '$out' — precondition VIOLATED"
            fail=1
        fi
    done

    codes=${codes# }
    if [ "$fail" -ne 0 ]; then
        die 30 "N1 FAIL — the guest already has a Rust toolchain where DOC-2 §6.2 requires none. The likeliest cause is base-image drift (DOC-2 §3); this is a FINDING, not a nuisance. Recorded exits: ${codes}"
    fi
    log "N1 PASS (${codes})"
}
