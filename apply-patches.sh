#!/usr/bin/env bash
# Apply the geph5 Android patch series to a geph5 source tree.
#
# Instead of merging upstream into a fork, keep upstream pristine and re-apply
# the Android delta as a patch series. See patches/README.md for why.
#
# Usage:
#   ./apply-patches.sh [TARGET_DIR]      apply the series to TARGET_DIR (default: .)
#   ./apply-patches.sh --check [DIR]     verify only, change nothing
#   ./apply-patches.sh --3way  [DIR]     allow three-way merging of drifted context
#
# Deliberately uses `git apply`, never `patch -p1`. GNU patch applies with fuzz,
# which silently accepts shifted context and can leave a tree that compiles while
# gating on the wrong platform. git apply either lands exactly or fails loudly,
# and that property is what makes the series reviewable.
#
# Patches apply in filename order, sorted least-fragile first, so a reject on the
# large platform.rs patch does not cost you the one-line libc cfg.

set -euo pipefail

mode=apply
target=.

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --check) mode=check ;;
        --3way)  mode=3way ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)  target=$1 ;;
    esac
    shift
done

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
SERIE_DIR="$SCRIPT_DIR/patches"
ERR=$(mktemp)
trap 'rm -f "$ERR"' EXIT

if [ ! -d "$SERIE_DIR" ]; then
    echo "error: no patches/ next to $0 (looked in $SERIE_DIR)" >&2
    exit 2
fi

if [ ! -f "$target/binaries/geph5-app/Cargo.toml" ]; then
    echo "error: $target is not a geph5 source tree" >&2
    echo "       expected $target/binaries/geph5-app/Cargo.toml to exist" >&2
    exit 2
fi

if ! grep -q '^\[workspace\]' "$target/Cargo.toml" 2>/dev/null; then
    echo "error: $target/Cargo.toml has no [workspace] table; wrong tree?" >&2
    exit 2
fi

shopt -s nullglob
patches=("$SERIE_DIR"/*.patch)
shopt -u nullglob

if [ ${#patches[@]} -eq 0 ]; then
    echo "error: no .patch files in $SERIE_DIR" >&2
    exit 2
fi

echo "target: $(cd "$target" && pwd)"
echo "series: ${#patches[@]} patches"

# --3way rebuilds the "ours" side from the index, so a worktree that has drifted
# away from the index makes it abort with a misleading "does not match index".
# Warn rather than refuse: uncommitted drift is a legitimate state to be in when
# you are mid-sync, but it must not silently poison the merge.
if [ "$mode" = "3way" ]; then
    untracked_and_staged=$(git -C "$target" status --porcelain 2>/dev/null | grep -c '^[MADRCU]' || true)
    unstaged=$(git -C "$target" diff --name-only 2>/dev/null | grep -c . || true)
    if [ "$unstaged" -gt 0 ]; then
        echo "warning: $unstaged file(s) differ from the index."
        echo "         git apply --3way takes \"ours\" from the index, so results can be"
        echo "         confusing. Stage or commit your drift first for a clean merge."
    fi
fi

echo

applied=0
skipped=0
failed=0
failed_name=""

for p in "${patches[@]}"; do
    name=$(basename "$p")

    # `--check --3way` does not predict conflicts: git reports success because it
    # expects to be able to reconstruct and merge. So --check is only meaningful
    # without --3way, and 3way mode has to apply each patch and read the result.
    if [ "$mode" = "3way" ]; then
        if git -C "$target" apply --check --reverse "$p" 2>/dev/null; then
            echo "skip   $name (already applied)"
            skipped=$((skipped + 1))
            continue
        fi
        if git -C "$target" apply --3way "$p" 2>"$ERR"; then
            echo "apply  $name"
            applied=$((applied + 1))
            continue
        fi
        echo "CONFLICT $name"
        sed 's/^/         /' "$ERR"
        conflicted=$(git -C "$target" diff --name-only --diff-filter=U 2>/dev/null | sed 's/^/         /')
        [ -n "$conflicted" ] && printf 'unmerged: %s\n' "$conflicted"
        failed=1
        failed_name=$name
        break
    fi

    if git -C "$target" apply --check "$p" 2>"$ERR"; then
        if [ "$mode" = "check" ]; then
            echo "ok      $name"
        else
            git -C "$target" apply "$p"
            echo "apply   $name"
        fi
        applied=$((applied + 1))
    elif git -C "$target" apply --check --reverse "$p" 2>/dev/null; then
        # reverse-check makes re-running safe after a mid-series failure
        echo "skip    $name (already applied)"
        skipped=$((skipped + 1))
    else
        # Not fatal on its own, but it must be loud: an unapplied platform.rs
        # patch yields a binary that compiles and then gates on the wrong
        # target OS, which is the failure mode that costs real time.
        echo "REJECT  $name"
        sed 's/^/         /' "$ERR"
        echo "         retry with: $0 --3way $target"
        echo "         or re-derive the series: patches/regenerate.sh"
        echo
        failed=$((failed + 1))
        failed_name=$name
    fi
done

echo

total=${#patches[@]}
if [ "$mode" = "check" ]; then
    tally="$((applied + skipped))/$total applicable"
    [ "$skipped" -gt 0 ] && tally="$tally, $skipped already present"
else
    tally="$applied applied"
    [ "$skipped" -gt 0 ] && tally="$tally, $skipped already present"
fi

if [ "$failed" -eq 0 ]; then
    case "$mode" in
        check) echo "all $total patches verified against the tree: $tally; nothing was modified" ;;
        *)     echo "all $total patches accounted for: $tally"
               echo
               echo "next: confirm the Android target still compiles, e.g."
               echo "  cd $target && cargo check -p geph5-app -p geph5-client --target aarch64-linux-android" ;;
    esac
    exit 0
fi

if [ "$mode" = "3way" ]; then
    echo "stopped at $failed_name ($applied of ${#patches[@]} already applied)."
    echo "Patches after this one were not attempted."
    echo
    echo "The tree is left mid-merge on purpose. Resolve, then continue:"
    echo "  git -C $target add <resolved files>     # or git checkout --theirs to back out"
    echo "  $0 --3way $target                      # will re-report already-applied patches"
    echo
    echo "If the conflict is really an upstream reflow, re-derive instead of hand-merging:"
    echo "  patches/regenerate.sh <new-base>"
    exit 1
fi

echo "$failed of ${#patches[@]} patches rejected (last: $failed_name)"
echo
echo "Nothing was committed. The tree holds whatever applied cleanly."
echo "Do not build from it until the rejects are resolved: a missing platform.rs"
echo "patch produces a binary that gates on the wrong target OS."
exit 1