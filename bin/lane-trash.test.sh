#!/usr/bin/env bash
# Tests for lane-trash and lane-trash-purge. Runs only in a temp folder under
# /var/tmp/claude, with a stub grove and fake pressure and presence files.
# Usage: bin/lane-trash.test.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
LT="$here/lane-trash"
PURGE="$here/lane-trash-purge"

mkdir -p /var/tmp/claude
T=$(mktemp -d -p /var/tmp/claude lane-trash-test.XXXXXX)
subvol=""
cleanup() {
  chmod -R u+rwx "$T" 2>/dev/null
  if [ -n "$subvol" ]; then
    rm -rf "${subvol:?}"/* 2>/dev/null
    btrfs subvolume delete "$subvol" >/dev/null 2>&1 || rmdir "$subvol" 2>/dev/null
  fi
  rm -rf -- "$T"
}
trap cleanup EXIT

pass=0 fail=0
ok()   { echo "ok   $*"; pass=$((pass + 1)); }
bad()  { echo "FAIL $*"; fail=$((fail + 1)); }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

# ---- fixture: a work_dir with a main repo and one worktree lane -----------
W="$T/work"
mkdir -p "$W/.scratch" "$T/state"
git init -q "$W/master"
git -C "$W/master" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

new_lane() {
  git -C "$W/master" worktree add -q -b "br-$1" "$W/.scratch/$1"
  mkdir -p "$W/.scratch/$1/sub/deep"
  echo x >"$W/.scratch/$1/sub/deep/f"
}

# Stub grove: `path` maps a tag to .scratch/<tag> if it exists in
# $T/registry; `done` records its args and, unless STUB_DONE_RC is set,
# drops the git metadata like the real one.
cat >"$T/grove" <<EOF
#!/usr/bin/env bash
[ "\$1" = --repo ] && shift 2
case "\$1" in
  path) grep -qxF "\$2" "$T/registry" || { echo "grove: unknown tag '\$2'" >&2; exit 1; }
        echo "$W/.scratch/\$2" ;;
  done) echo "\$*" >>"$T/done.calls"
        [ -z "\${STUB_DONE_RC:-}" ] || exit "\$STUB_DONE_RC"
        tag="\${@: -1}"
        git -C "$W/master" worktree remove --force "$W/.scratch/\$tag" || exit 1
        grep -vxF "\$tag" "$T/registry" >"$T/registry.new"; mv "$T/registry.new" "$T/registry" ;;
esac
EOF
chmod +x "$T/grove"
: >"$T/registry"

export LANE_TRASH_WORK_DIR="$W" LANE_TRASH_STATE_DIR="$T/state" LANE_TRASH_GROVE="$T/grove"
export LANE_TRASH_DIR="$W/.trash" LANE_TRASH_GROVE_LOCK="$T/grove-machine.lock"

# ---- lane-trash: tag and path checks ---------------------------------------
for badtag in '..' '../x' 'a/b' '.scratch' '-rf' 'a..b'; do
  out=$("$LT" -- "$badtag" 2>&1); rc=$?
  check "bad tag '$badtag' refused" [ "$rc" -ne 0 ]
done
out=$("$LT" nolane 2>&1); rc=$?
check "unknown lane refused" [ "$rc" -ne 0 ]

# A registered tag whose folder is a symlink to somewhere else.
mkdir -p "$T/outside"; echo keep >"$T/outside/canary"
ln -s "$T/outside" "$W/.scratch/linked"; echo linked >>"$T/registry"
out=$("$LT" linked 2>&1); rc=$?
check "symlinked lane refused" [ "$rc" -ne 0 ]
check "symlink target untouched" [ -f "$T/outside/canary" ]
rm "$W/.scratch/linked"

# ---- lane-trash: happy path -------------------------------------------------
new_lane lt1; echo lt1 >>"$T/registry"
out=$("$LT" lt1 2>&1); rc=$?
check "trash lt1 succeeds" [ "$rc" -eq 0 ]
check "lt1 folder gone from .scratch" [ ! -e "$W/.scratch/lt1" ]
check "lt1 is in the trash" bash -c "compgen -G '$W/.trash/lt1-*' >/dev/null"
check "grove done called with --force" grep -qx "done --force lt1" "$T/done.calls"
check "git forgot lt1" bash -c "! git -C '$W/master' worktree list | grep -q '/lt1 '"
check "trash keeps lt1 files" bash -c "compgen -G '$W/.trash/lt1-*/sub/deep/f' >/dev/null"

# ---- lane-trash: grove done fails before dropping metadata -> moved back ---
new_lane lt2; echo lt2 >>"$T/registry"
out=$(STUB_DONE_RC=1 "$LT" lt2 2>&1); rc=$?
check "failed done returns non-zero" [ "$rc" -ne 0 ]
check "failed done moves lane back" [ -f "$W/.scratch/lt2/sub/deep/f" ]
check "nothing of lt2 left in trash" bash -c "! compgen -G '$W/.trash/*lt2-*'"
check "no staged folder left after lt1" bash -c "! compgen -G '$W/.trash/.incoming-*'"

# ---- lane-trash: cross-filesystem refusal ----------------------------------
# A btrfs subvolume has its own device number, like another filesystem, and
# rename(2) into it fails with EXDEV. Fall back to /dev/shm (tmpfs).
if btrfs subvolume create "$T/othersv" >/dev/null 2>&1; then
  subvol="$T/othersv"; other="$subvol/trash"
else
  other=$(mktemp -d -p /dev/shm lane-trash-test.XXXXXX)/trash
fi
mkdir -p "$other"
out=$(LANE_TRASH_DIR="$other" "$LT" lt2 2>&1); rc=$?
check "cross-filesystem move refused" [ "$rc" -ne 0 ]
check "refusal names filesystems" grep -q "different filesystems" <<<"$out"
check "lane untouched after refusal" [ -f "$W/.scratch/lt2/sub/deep/f" ]
case "$other" in /dev/shm/*) rm -rf -- "$(dirname "$other")" ;; esac

# ---- lane-trash: global lock -------------------------------------------------
LANE_TRASH_HOLD_SECS=4 "$LT" --dry-run lt2 >/dev/null 2>&1 &
holder=$!
sleep 1
out=$(LANE_TRASH_LOCK_WAIT=1 "$LT" --dry-run lt2 2>&1); rc=$?
check "second call fails while lock is held" [ "$rc" -ne 0 ]
check "lock message" grep -q "holds" <<<"$out"
wait "$holder"
out=$(LANE_TRASH_LOCK_WAIT=1 "$LT" --dry-run lt2 2>&1); rc=$?
check "call succeeds after lock is free" [ "$rc" -eq 0 ]

# ---- lane-trash: waits for grove's machine lock -----------------------------
flock "$T/grove-machine.lock" sleep 3 &
gl=$!
sleep 0.5
out=$(LANE_TRASH_LOCK_WAIT=1 "$LT" lt2 2>&1); rc=$?
check "lane-trash refuses while grove lock is held" [ "$rc" -ne 0 ]
check "lane untouched while grove lock held" [ -f "$W/.scratch/lt2/sub/deep/f" ]
wait "$gl"

# ---- purge: fixture ----------------------------------------------------------
P="$T/purge"
mkdir -p "$P/trash" "$P/outside/dir"
echo keep >"$P/outside/canary"; echo keep >"$P/outside/dir/canary2"
echo '{"state": "away"}' >"$P/presence"
echo "some avg10=0.00 avg60=0.00 avg300=0.00 total=0" >"$P/psi"
export LANE_TRASH_DIR="$P/trash" LANE_TRASH_PSI_FILE="$P/psi" LANE_TRASH_PRESENCE_FILE="$P/presence"
export LANE_TRASH_GROVE_LOCK="$P/grove.lock" LANE_TRASH_SLEEP=0 LANE_TRASH_SLEEP_AWAY=0
export LANE_TRASH_PAUSE_POLL=0.2 LANE_TRASH_BATCH=50

make_tree() {
  local d="$P/trash/$1"
  mkdir -p "$d/a/b/c" "$d/ro/inner"
  for i in $(seq 1 120); do echo "$i" >"$d/a/f$i"; done
  for i in $(seq 1 30); do echo "$i" >"$d/a/b/c/g$i"; done
  echo x >"$d/ro/inner/h"; chmod 0555 "$d/ro/inner" "$d/ro"
  ln -s "$P/outside" "$d/link-to-dir"
  ln -s "$P/outside/canary" "$d/link-to-file"
  ln -s ../../outside "$d/a/dotdot-link"
  ln "$P/outside/canary" "$d/hardlink" 2>/dev/null || true
}

# ---- purge: pauses on IO pressure -------------------------------------------
make_tree p1
echo loose >"$P/trash/loose-file"
echo "some avg10=5.00 avg60=1.00 avg300=1.00 total=0" >"$P/psi"
LANE_TRASH_MAX_PAUSE=1 "$PURGE" --once >/dev/null 2>&1; rc=$?
check "purge exits 3 while paused on IO pressure" [ "$rc" -eq 3 ]
check "nothing deleted under pressure" [ -f "$P/trash/p1/a/f1" ]
check "loose file kept under pressure" [ -f "$P/trash/loose-file" ]
check "pause logged" grep -q "pause: io pressure some avg10=5.00" "$T/state/purge.log"
echo "some avg10=0.00 avg60=0.00 avg300=0.00 total=0" >"$P/psi"

# ---- purge: pauses while presence is here ------------------------------------
echo '{"state": "here"}' >"$P/presence"
LANE_TRASH_MAX_PAUSE=1 "$PURGE" --once >/dev/null 2>&1; rc=$?
check "purge pauses while presence is here" [ "$rc" -eq 3 ]
echo '{"state": "away"}' >"$P/presence"

# ---- purge: waits for grove's machine lock -----------------------------------
: >"$P/grove.lock"
flock "$P/grove.lock" sleep 3 &
gl=$!
sleep 0.5
LANE_TRASH_MAX_PAUSE=1 "$PURGE" --once >/dev/null 2>&1; rc=$?
check "purge waits while grove lock is held" [ "$rc" -eq 3 ]
wait "$gl"

# ---- purge: removes the tree, never anything outside -------------------------
make_tree p2
mkdir -p "$P/trash/.incoming-p9"; echo x >"$P/trash/.incoming-p9/f"
ln -s "$P/outside" "$P/trash/top-link"   # a symlink directly in the trash
"$PURGE" --once >/dev/null 2>&1; rc=$?
check "purge --once exits 0" [ "$rc" -eq 0 ]
check "trash holds only the staged folder" [ "$(ls -A "$P/trash")" = .incoming-p9 ]
check "staged folder untouched" [ -f "$P/trash/.incoming-p9/f" ]
rm -r "$P/trash/.incoming-p9"
check "outside canary kept" [ "$(cat "$P/outside/canary" 2>/dev/null)" = keep ]
check "outside nested canary kept" [ -f "$P/outside/dir/canary2" ]
check "outside folder kept" [ -d "$P/outside/dir" ]
check "purge log has one line per folder" [ "$(grep -c '^.* purged p[12] files=' "$T/state/purge.log")" -eq 2 ]
check "purge log counts files" grep -q "purged p1 files=15[0-9] dirs=6 " "$T/state/purge.log"

# ---- purge: refuses a trash folder that is a symlink -------------------------
mkdir -p "$P/real"; echo keep >"$P/real/x"
ln -s "$P/real" "$P/trash-link"
out=$(LANE_TRASH_DIR="$P/trash-link" "$PURGE" --once 2>&1); rc=$?
check "symlinked trash folder refused" [ "$rc" -ne 0 ]
check "symlinked trash target kept" [ -f "$P/real/x" ]

# ---- purge: a subvolume inside the trash is left alone -----------------------
if btrfs subvolume create "$P/trash/p3" >/dev/null 2>&1; then
  mkdir "$P/trash/p3/x"; echo y >"$P/trash/p3/x/z"
  out=$("$PURGE" --once 2>&1); rc=$?
  # The subvolume root itself is not followed into because its device differs.
  check "subvolume in trash reported stuck" grep -q "stuck p3" <<<"$out"
  check "subvolume contents kept" [ -f "$P/trash/p3/x/z" ]
  rm -rf "$P/trash/p3/x"; btrfs subvolume delete "$P/trash/p3" >/dev/null 2>&1 || rmdir "$P/trash/p3"
else
  echo "skip subvolume test (cannot create a btrfs subvolume here)"
fi

echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
