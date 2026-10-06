#!/usr/bin/env bash
# Rebuild the patch series in patches/ from a git range in this repo.
#
# The series is not hand-written: it is mechanically derived from the diff
# between an upstream base and this fork's HEAD, split one file per patch and
# ordered least-fragile first. That derivation is what makes the series
# auditable -- if a patch disagrees with the tree, the disagreement is visible
# in a single `git diff`, and the patch header says what it was supposed to do.
#
# Usage:
#   patches/regenerate.sh                 regenerate against the recorded base
#   patches/regenerate.sh <base-ref>      regenerate against a different base
#
# Refusing to overwrite headers: the per-patch prose (what the change does, how
# fragile it is, what it deliberately does not fix) is written by a human and
# lives in patches/headers/. Only the diff hunks below each header are
# regenerated.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/.." && pwd)
HEADERS="$SCRIPT_DIR/headers"
BASE_PIN=$(cat "$SCRIPT_DIR/BASE" 2>/dev/null || echo "")

base=${1:-${BASE_PIN:-}}

if [ -z "$base" ]; then
    echo "error: no base ref given and patches/BASE is missing" >&2
    echo "usage: $0 <base-ref>    e.g. $0 1f65e9ee" >&2
    exit 2
fi

git -C "$REPO" rev-parse --verify "$base^{commit}" >/dev/null 2>&1 || {
    echo "error: base ref '$base' is not a commit in $REPO" >&2
    exit 2
}

if [ ! -d "$HEADERS" ]; then
    echo "error: $HEADERS does not exist; refusing to regenerate without prose" >&2
    exit 2
fi

cd "$REPO"

# patch file stem -> path it patches. Order matters: sorted, so 0001..0006
# applies least-fragile first.
declare -A TARGETS=(
    [0001-geph5-app-cargo-libc-android]=binaries/geph5-app/Cargo.toml
    [0002-geph5-misc-rpc-manager-control-android-sock]=libraries/geph5-misc-rpc/src/manager_control.rs
    [0003-geph5-app-cli-register-subcommand]=binaries/geph5-app/src/cli.rs
    [0004-geph5-app-client-register-command]=binaries/geph5-app/src/client.rs
    [0005-geph5-app-vpn-android-cfg]=binaries/geph5-app/src/vpn.rs
    [0006-geph5-app-platform-android]=binaries/geph5-app/src/platform.rs
)

dirty=0
for stem in "${!TARGETS[@]}"; do
    path=${TARGETS[$stem]}
    header="$HEADERS/$stem.header"
    out="$SCRIPT_DIR/$stem.patch"

    if [ ! -f "$header" ]; then
        echo "missing header: $header" >&2
        exit 2
    fi

    if [ ! -f "$out" ]; then
        echo "note: creating new patch $stem.patch"
    fi

    {
        cat "$header"
        echo
        echo "---"
        git diff --stat "$base"..HEAD -- "$path" | tail -1
        echo
        git diff "$base"..HEAD -- "$path"
    } > "$out.new"

    if [ -f "$out" ] && cmp -s "$out" "$out.new"; then
        rm -f "$out.new"
        echo "unchanged  $stem.patch"
    else
        mv "$out.new" "$out"
        echo "updated    $stem.patch   ($path)"
        dirty=1
    fi
done

rm -f "$SCRIPT_DIR"/*.new

echo "$base" > "$SCRIPT_DIR/BASE"
echo
echo "base pinned to: $base ($(git rev-parse --short "$base"))"

if [ "$dirty" -eq 1 ]; then
    echo
    echo "series changed. review with:"
    echo "  git diff -- patches/"
    echo "then re-verify with:"
    echo "  ./apply-patches.sh --check /path/to/pristine/geph5"
fi