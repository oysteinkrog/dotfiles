#!/usr/bin/env python3
"""fastscan.py - WizTree/WinDirStat-style disk usage scanner for WSL1 + Windows.

Why this exists
---------------
On WSL1, every filesystem call against a DrvFs mount (/c, /mnt/c) is translated
into Win32 calls one at a time. `du -sh` on a large tree therefore takes minutes
to hours: the per-file `stat()` cost dominates. Native Windows enumeration of the
same tree is 10-100x faster.

So this script always does its real work in *Windows* Python. When it is started
by a Linux/WSL interpreter it converts its own path and its path arguments to
Windows form and re-executes itself through `python.exe`. Output paths are then
converted back to the form the caller used, so `/c/...` in means `/c/...` out.

Two engines
-----------
scandir (default)
    Multithreaded recursive `os.scandir`. On Windows a `DirEntry` is populated
    from the FindFirstFile/FindNextFile result, so `entry.stat(follow_symlinks=
    False)` needs no extra syscall - size and attributes are already in hand.
    This is the WinDirStat approach. Needs no privileges.

mft (opt-in, --engine mft)
    Reads the raw NTFS Master File Table off the volume and parses every FILE
    record. This is the WizTree approach: one large sequential read replaces
    millions of directory operations. Requires Administrator (raw volume access),
    so it must be run from an elevated shell.

Caveats for the mft engine are documented in --help and in the code comments
near the parser.
"""

from __future__ import annotations

import argparse
import fnmatch
import heapq
import os
import queue
import re
import shutil
import struct
import subprocess
import sys
import threading
import time

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

FILE_ATTRIBUTE_REPARSE_POINT = 0x400

# Internal flags used only for the WSL -> Windows re-exec handshake.
_REEXEC_FLAG = "--_reexec"
_OUTSTYLE_FLAG = "--_out-style"
_JSONLABEL_FLAG = "--_json-label"
_TTY_FLAG = "--_tty"

DEFAULT_TARGET_WIN = r"C:\Users\oystein"

HEARTBEAT_SECONDS = 2.0


# --------------------------------------------------------------------------- #
# stdout / stderr safety
#
# The Windows console defaults to cp1252 under many code pages. File names on
# disk routinely contain characters that cannot be encoded there, and an
# UnicodeEncodeError mid-report would throw away a scan that took minutes.
# --------------------------------------------------------------------------- #


def _make_streams_safe() -> None:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[union-attr]
        except (AttributeError, ValueError, OSError):
            pass


# --------------------------------------------------------------------------- #
# Path conversion
# --------------------------------------------------------------------------- #

# Matches /mnt/c/... (standard WSL) - captures the drive letter.
_RE_WSL_MNT = re.compile(r"^/mnt/([A-Za-z])(?=/|$)")
# Matches /c/... (this machine's automount root=/ layout).
_RE_WSL_ROOT = re.compile(r"^/([A-Za-z])(?=/|$)")
# Matches C:\... or C:/...
_RE_WIN = re.compile(r"^([A-Za-z]):[\\/]")


def looks_windows(path: str) -> bool:
    return bool(_RE_WIN.match(path)) or path.startswith("\\\\")


def detect_out_style(path: str) -> str:
    """Return 'mnt', 'root' or 'win' describing how the caller writes paths."""
    if _RE_WSL_MNT.match(path):
        return "mnt"
    if looks_windows(path):
        return "win"
    if _RE_WSL_ROOT.match(path):
        return "root"
    return "win"


def wsl_to_win(path: str) -> str:
    """Convert a WSL DrvFs path to Windows form. Raises ValueError otherwise."""
    if looks_windows(path):
        return path.replace("/", "\\")
    m = _RE_WSL_MNT.match(path)
    if m:
        rest = path[len(m.group(0)) :]
    else:
        m = _RE_WSL_ROOT.match(path)
        if not m:
            raise ValueError(
                f"{path!r} is not on a Windows drive mount. fastscan can only "
                f"scan paths under /c, /mnt/c, ... (WSL's own rootfs is not "
                f"reachable from Windows Python)."
            )
        rest = path[len(m.group(0)) :]
    drive = m.group(1).upper()
    rest = rest.replace("/", "\\").lstrip("\\")
    return f"{drive}:\\{rest}" if rest else f"{drive}:\\"


def win_to_wsl(path: str, style: str) -> str:
    """Convert a Windows path back to the WSL form named by `style`."""
    if style == "win":
        return path
    m = _RE_WIN.match(path)
    if not m:
        return path
    drive = m.group(1).lower()
    rest = path[m.end() :].replace("\\", "/")
    prefix = f"/mnt/{drive}" if style == "mnt" else f"/{drive}"
    return f"{prefix}/{rest}" if rest else prefix


# --------------------------------------------------------------------------- #
# Re-exec into Windows Python
# --------------------------------------------------------------------------- #


def interop_cwd() -> str:
    """A directory on a Windows drive, safe to use as cwd for a Win32 child.

    WSL1 interop gotcha: launching a Windows executable while the current
    directory is inside WSL's own rootfs (/tmp, /home, ...) leaves the child
    with no valid working directory. In practice the launch stalls until it is
    killed rather than failing fast, which looks exactly like a missing
    interpreter. Every Win32 child below is therefore given an explicit cwd on
    a DrvFs mount.
    """
    here = os.path.dirname(os.path.realpath(os.path.abspath(__file__)))
    try:
        wsl_to_win(here)
    except ValueError:
        for fallback in ("/c", "/mnt/c"):
            if os.path.isdir(fallback):
                return fallback
        return here
    return here


WINDOWS_PYTHON_CANDIDATES = (["python.exe"], ["py.exe", "-3"])


def staging_dir() -> str:
    """A directory writable from WSL that Windows can also see, for --json relay.

    Deliberately derived without launching anything: a single Windows process
    launch through WSL1 interop costs 1.5-4 seconds, which is more than most
    scans, so the fast path must be exactly one launch in total.
    """
    candidates = [os.environ.get("FASTSCAN_STAGE_DIR"), os.path.expanduser("~")]
    for prefix in ("/c", "/mnt/c"):
        candidates.append(f"{prefix}/Users/Public")
    candidates.append(os.path.dirname(os.path.realpath(os.path.abspath(__file__))))
    for cand in candidates:
        if not cand or not os.path.isdir(cand):
            continue
        try:
            wsl_to_win(cand)
        except ValueError:
            continue
        if os.access(cand, os.W_OK):
            return cand
    return ""


def reexec_on_windows(argv: list[str]) -> int:
    """Translate argv to Windows form and run this script under python.exe."""
    # ~/.claude is a symlink into ~/.dotfiles/.claude. Resolve it here, on the
    # WSL side, so Windows Python is handed a path it can open without needing
    # to traverse a WSL-created reparse point.
    script = os.path.realpath(os.path.abspath(__file__))
    try:
        script_win = wsl_to_win(script)
    except ValueError:
        sys.stderr.write(
            f"fastscan: this script lives at {script}, which is not on a "
            f"Windows drive, so Windows Python cannot run it.\n"
        )
        return 3

    # A --json destination on WSL's own rootfs (/tmp, /home, ...) is invisible
    # to Windows. Rather than refusing, the child writes into the Windows temp
    # dir and this process moves the result to where the caller asked for it.
    relay: tuple[str, str] | None = None

    def json_dest(target: str) -> str:
        nonlocal relay
        try:
            return wsl_to_win(target)
        except ValueError:
            pass
        stage = staging_dir()
        if not stage:
            return target
        staged_wsl = os.path.join(stage, f".fastscan-{os.getpid()}.json")
        relay = (staged_wsl, target)
        return wsl_to_win(staged_wsl)

    # Rewrite path-bearing arguments. Everything else passes through verbatim.
    out: list[str] = []
    style = "win"
    i = 0
    saw_positional = False
    label: str | None = None
    while i < len(argv):
        a = argv[i]
        if a == "--json" and i + 1 < len(argv):
            label = argv[i + 1]
            out += [a, json_dest(label)]
            i += 2
            continue
        if a.startswith("--json="):
            label = a.split("=", 1)[1]
            out.append("--json=" + json_dest(label))
            i += 1
            continue
        if a == "--image" and i + 1 < len(argv):
            out += [a, _translate_arg(argv[i + 1])]
            i += 2
            continue
        if a.startswith("--image="):
            out.append("--image=" + _translate_arg(a.split("=", 1)[1]))
            i += 1
            continue
        if (
            not a.startswith("-")
            and not saw_positional
            and not _is_option_value(argv, i)
        ):
            saw_positional = True
            style = detect_out_style(a)
            out.append(_translate_arg(a))
            i += 1
            continue
        out.append(a)
        i += 1

    if not saw_positional:
        # No PATH given: the default target is a Windows path, but the caller
        # invoked us from WSL, so report results in WSL form.
        style = "root" if os.path.isdir("/c") else "mnt"

    tail = [script_win, _REEXEC_FLAG, _OUTSTYLE_FLAG, style]
    if sys.stderr.isatty():
        # A Windows process launched through WSL interop never sees a tty on
        # its inherited handles, not even under a pty, so isatty() in the child
        # is always False. Only this side can tell whether a human is watching.
        tail.append(_TTY_FLAG)
    if label is not None:
        # So the child reports the destination the caller typed rather than the
        # staging path it may actually be writing to.
        tail += [_JSONLABEL_FLAG, label]
    tail += out

    # Try each interpreter in turn, but only fall through when the *launch*
    # itself failed. A child that started and then exited nonzero has already
    # reported its own problem; retrying would run the scan twice.
    rc = None
    cwd = interop_cwd()
    for py in WINDOWS_PYTHON_CANDIDATES:
        try:
            rc = subprocess.call(py + tail, cwd=cwd)
            break
        except KeyboardInterrupt:
            return 130
        except OSError:
            continue
    if rc is None:
        sys.stderr.write(
            "fastscan: cannot launch a Windows Python (`python.exe` or "
            "`py.exe -3`) from WSL. Native Windows enumeration is the whole "
            "point of this tool; a WSL-side scan would be too slow to be "
            "useful. Install Python for Windows, or run the scan from a "
            "Windows shell directly.\n"
        )
        return 3

    if relay is not None:
        staged_wsl, final = relay
        if rc != 0:
            # The child failed; do not leave a stale staging file behind.
            try:
                os.unlink(staged_wsl)
            except OSError:
                pass
            return rc
        try:
            shutil.move(staged_wsl, final)
        except OSError as exc:
            sys.stderr.write(
                f"fastscan: the scan finished but its JSON could not be moved "
                f"from {staged_wsl} to {final}: {exc}\n"
            )
            return 5
    return rc


# Options that take a separate value; used so we do not mistake that value for
# the positional PATH argument during re-exec rewriting.
_VALUE_OPTIONS = {
    "--engine",
    "--image",
    "--top",
    "--threads",
    "--json",
    "--min-size",
    "--depth",
    "--exclude",
}


def _is_option_value(argv: list[str], i: int) -> bool:
    return i > 0 and argv[i - 1] in _VALUE_OPTIONS


def _translate_arg(a: str) -> str:
    try:
        return wsl_to_win(a)
    except ValueError:
        return a


# --------------------------------------------------------------------------- #
# Formatting helpers
# --------------------------------------------------------------------------- #

_UNITS = (("TiB", 1 << 40), ("GiB", 1 << 30), ("MiB", 1 << 20), ("KiB", 1 << 10))


def human(n: int) -> str:
    for name, scale in _UNITS:
        if n >= scale:
            return f"{n / scale:.2f} {name}"
    return f"{n} B"


_SIZE_RE = re.compile(r"^\s*([0-9]*\.?[0-9]+)\s*([KMGTP]?)(?:i?B?)?\s*$", re.I)
_SIZE_MULT = {
    "": 1,
    "K": 1 << 10,
    "M": 1 << 20,
    "G": 1 << 30,
    "T": 1 << 40,
    "P": 1 << 50,
}


def parse_size(spec: str) -> int:
    m = _SIZE_RE.match(spec)
    if not m:
        raise argparse.ArgumentTypeError(
            f"cannot parse size {spec!r}; use forms like 100M, 1.5G, 4096"
        )
    return int(float(m.group(1)) * _SIZE_MULT[m.group(2).upper()])


# --------------------------------------------------------------------------- #
# Shared scan result container
# --------------------------------------------------------------------------- #


class ScanResult:
    """Per-directory own sizes plus the top-files heap, before roll-up."""

    def __init__(self) -> None:
        # path -> [own_size_bytes, direct_file_count]
        self.dirs: dict[str, list[int]] = {}
        self.files: list[tuple[int, str, float]] = []  # (size, path, mtime)
        self.n_files = 0
        self.n_dirs = 0
        self.n_errors = 0
        self.n_reparse = 0
        self.total_bytes = 0
        self.notes: list[str] = []


def rollup(
    dirs: dict[str, list[int]], root: str
) -> tuple[dict[str, int], dict[str, int]]:
    """Turn per-directory own sizes into cumulative subtree sizes.

    A child path is always strictly longer than its parent path, so processing
    in order of decreasing path length visits every directory after all of its
    descendants. No explicit child lists or recursion needed.
    """
    cum = {p: v[0] for p, v in dirs.items()}
    cumn = {p: v[1] for p, v in dirs.items()}
    # `key=len` would be enough, but it makes type checkers widen the element
    # type from str to Sized; the lambda keeps the key type intact.
    for p in sorted(dirs, key=lambda path: len(path), reverse=True):
        if p == root:
            continue
        parent = os.path.dirname(p)
        if parent in cum:
            cum[parent] += cum[p]
            cumn[parent] += cumn[p]
    return cum, cumn


# --------------------------------------------------------------------------- #
# Engine: scandir
# --------------------------------------------------------------------------- #


class _ThreadStats:
    __slots__ = ("files", "dirs", "errors", "reparse", "bytes", "heap")

    def __init__(self) -> None:
        self.files = 0
        self.dirs = 0
        self.errors = 0
        self.reparse = 0
        self.bytes = 0
        # Min-heap of (size, path, mtime), bounded; smallest entry at [0].
        self.heap: list[tuple[int, str, float]] = []


def scan_scandir(
    root: str,
    threads: int,
    excludes: list[str],
    min_size: int,
    file_cap: int,
    quiet: bool,
) -> ScanResult:
    res = ScanResult()
    work: queue.Queue = queue.Queue()
    work.put(root)

    # Each worker keeps private counters and a private top-files heap, so the
    # hot path takes no locks at all. They are merged once, at the end.
    all_stats: list[_ThreadStats] = []
    stats_lock = threading.Lock()
    tls = threading.local()

    # dirs[] is written without a lock: each directory is processed by exactly
    # one worker, so keys never collide, and dict.__setitem__ is atomic under
    # the GIL for built-in types.
    dirs = res.dirs
    dirs[root] = [0, 0]

    excl_lower = [e.lower() for e in excludes]

    def excluded(path: str, name: str) -> bool:
        if not excl_lower:
            return False
        pl = path.lower()
        nl = name.lower()
        for pat in excl_lower:
            if fnmatch.fnmatchcase(nl, pat) or fnmatch.fnmatchcase(pl, pat):
                return True
        return False

    def stats() -> _ThreadStats:
        st = getattr(tls, "st", None)
        if st is None:
            st = _ThreadStats()
            tls.st = st
            with stats_lock:
                all_stats.append(st)
        return st

    def process(directory: str) -> None:
        st = stats()
        own = 0
        nfile = 0
        try:
            it = os.scandir(directory)
        except (PermissionError, OSError):
            st.errors += 1
            return
        with it:
            while True:
                # Advancing the iterator can itself raise on a directory that
                # disappears or denies access mid-enumeration, so the loop is
                # driven manually rather than with `for entry in it`.
                try:
                    entry = next(it)
                except StopIteration:
                    break
                except (PermissionError, OSError):
                    st.errors += 1
                    break
                try:
                    # Free on Windows: the DirEntry already carries the
                    # FindFirstFile data, so no syscall happens here.
                    est = entry.stat(follow_symlinks=False)
                except (PermissionError, OSError):
                    st.errors += 1
                    continue

                attrs = getattr(est, "st_file_attributes", 0)
                if attrs & FILE_ATTRIBUTE_REPARSE_POINT:
                    # Junctions, symlinks and cloud placeholders. AppData is
                    # full of junctions that form cycles, and following them
                    # would double-count or hang the scan.
                    st.reparse += 1
                    continue

                path = entry.path
                name = entry.name
                if excluded(path, name):
                    continue

                mode = est.st_mode
                if mode & 0o170000 == 0o040000:  # S_IFDIR
                    st.dirs += 1
                    dirs[path] = [0, 0]
                    work.put(path)
                else:
                    size = est.st_size
                    st.files += 1
                    st.bytes += size
                    own += size
                    nfile += 1
                    if size >= min_size:
                        h = st.heap
                        if len(h) < file_cap:
                            heapq.heappush(h, (size, path, est.st_mtime))
                        elif size > h[0][0]:
                            heapq.heapreplace(h, (size, path, est.st_mtime))
        slot = dirs.get(directory)
        if slot is None:
            dirs[directory] = [own, nfile]
        else:
            slot[0] = own
            slot[1] = nfile

    def worker() -> None:
        while True:
            item = work.get()
            if item is None:
                work.task_done()
                return
            try:
                process(item)
            except Exception:  # noqa: BLE001 - a worker must never die silently
                stats().errors += 1
            finally:
                work.task_done()

    stop_beat = threading.Event()

    def heartbeat() -> None:
        # Long scans need to look alive. Written to stderr so that piping
        # stdout to a file or another program stays clean.
        while not stop_beat.wait(HEARTBEAT_SECONDS):
            with stats_lock:
                snapshot = list(all_stats)
            d = sum(s.dirs for s in snapshot)
            f = sum(s.files for s in snapshot)
            b = sum(s.bytes for s in snapshot)
            sys.stderr.write(
                f"\r  scanning... {d:>9,} dirs  {f:>10,} files  "
                f"{b / (1 << 30):>8.2f} GiB  q={work.qsize():<7}"
            )
            sys.stderr.flush()

    pool = [threading.Thread(target=worker, daemon=True) for _ in range(threads)]
    for t in pool:
        t.start()
    beat = None
    if not quiet:
        beat = threading.Thread(target=heartbeat, daemon=True)
        beat.start()

    work.join()
    stop_beat.set()
    if beat is not None:
        beat.join(timeout=1.0)
        sys.stderr.write("\r" + " " * 78 + "\r")
        sys.stderr.flush()
    for _ in pool:
        work.put(None)

    merged: list[tuple[int, str, float]] = []
    for s in all_stats:
        res.n_files += s.files
        res.n_dirs += s.dirs
        res.n_errors += s.errors
        res.n_reparse += s.reparse
        res.total_bytes += s.bytes
        merged.extend(s.heap)
    res.files = heapq.nlargest(file_cap, merged)
    return res


# --------------------------------------------------------------------------- #
# Engine: mft
#
# NTFS layout reference, all offsets in bytes.
#
# Boot sector (LBA 0):
#   0x0B u16  bytes per sector
#   0x0D u8   sectors per cluster (if >= 0x80: cluster size = 2**(256 - value))
#   0x30 u64  LCN of $MFT
#   0x40 s8   clusters per MFT record (if negative: size = 2**(-value))
#
# FILE record header:
#   0x00 4s   "FILE"
#   0x04 u16  offset of update sequence array
#   0x06 u16  count of u16 entries in the update sequence array
#   0x14 u16  offset of first attribute
#   0x16 u16  flags: 0x1 in use, 0x2 directory
#   0x20 u64  base record reference (0 for a base record)
#   0x2C u32  this record's MFT number (NTFS 3.1+)
#
# Attribute header (common):
#   0x00 u32  type (0xFFFFFFFF terminates)
#   0x04 u32  length
#   0x08 u8   non-resident flag
#   0x09 u8   name length in UTF-16 chars
#   0x0A u16  name offset
# Resident form:
#   0x10 u32  content length
#   0x14 u16  content offset
# Non-resident form:
#   0x10 u64  starting VCN
#   0x20 u16  offset to the data runs
#   0x28 u64  allocated size
#   0x30 u64  real size
#
# $FILE_NAME (0x30) content:
#   0x00 u64  parent reference (low 48 bits = MFT index)
#   0x40 u8   name length in chars
#   0x41 u8   namespace: 0 POSIX, 1 WIN32, 2 DOS, 3 WIN32+DOS
#   0x42      name, UTF-16LE
# --------------------------------------------------------------------------- #

ATTR_ATTRIBUTE_LIST = 0x20
ATTR_FILE_NAME = 0x30
ATTR_DATA = 0x80
ATTR_END = 0xFFFFFFFF

ROOT_FRN = 5

# Higher wins. A DOS 8.3 short name is only used if nothing better exists.
_NS_PRIORITY = {1: 4, 3: 4, 0: 3, 2: 1}

MFT_READ_CHUNK = 64 << 20  # 64 MiB sequential reads


class MFTError(RuntimeError):
    pass


def _parse_data_runs(buf: memoryview, offset: int) -> list[tuple[int, int]]:
    """Decode an NTFS data run list into [(lcn, cluster_count), ...].

    Each run starts with a header byte: the low nibble is the byte width of the
    run length field, the high nibble the byte width of the LCN delta field.
    The delta is *signed* and relative to the previous run's LCN, which is why
    a run can move backwards on disk. A zero-width delta field marks a sparse
    run: it consumes VCNs but occupies no clusters, so it is skipped.
    """
    runs: list[tuple[int, int]] = []
    pos = offset
    lcn = 0
    end = len(buf)
    while pos < end:
        header = buf[pos]
        if header == 0:
            break
        len_bytes = header & 0x0F
        off_bytes = (header >> 4) & 0x0F
        pos += 1
        if len_bytes == 0 or pos + len_bytes + off_bytes > end:
            break
        length = int.from_bytes(buf[pos : pos + len_bytes], "little", signed=False)
        pos += len_bytes
        if off_bytes:
            delta = int.from_bytes(buf[pos : pos + off_bytes], "little", signed=True)
            pos += off_bytes
            lcn += delta
            runs.append((lcn, length))
        # else: sparse run - no clusters allocated, nothing to read.
    return runs


def _apply_fixups(rec: bytearray, sector_size: int) -> bool:
    """Undo the update-sequence protection on a FILE record.

    NTFS overwrites the last two bytes of every sector in a record with an
    update sequence number so that a torn write can be detected. The real
    bytes live in the update sequence array. Every sector's tail must equal
    the USN; if one does not, the record is torn or not a record at all.
    """
    usa_off, usa_count = struct.unpack_from("<HH", rec, 0x04)
    if usa_count == 0 or usa_off + usa_count * 2 > len(rec):
        return False
    usn = rec[usa_off : usa_off + 2]
    for i in range(1, usa_count):
        tail = i * sector_size - 2
        if tail + 2 > len(rec):
            return False
        if rec[tail : tail + 2] != usn:
            return False
        src = usa_off + i * 2
        rec[tail : tail + 2] = rec[src : src + 2]
    return True


class MFTScanner:
    def __init__(self, drive: str, quiet: bool, image: str | None = None) -> None:
        self.drive = drive.upper()
        self.quiet = quiet
        # `image` points at a captured volume image instead of the live device.
        # It needs no privileges, which is what makes the parser testable.
        self.image = image
        self.volume = image if image else f"\\\\.\\{self.drive}:"
        self.fh = None
        self.sector_size = 512
        self.cluster_size = 4096
        self.record_size = 1024
        self.mft_lcn = 0

    def open(self) -> None:
        try:
            # buffering=0 keeps Python from issuing unaligned reads; raw volume
            # handles require offsets and lengths that are sector multiples.
            self.fh = open(self.volume, "rb", buffering=0)
        except PermissionError as exc:
            me = os.path.abspath(__file__)
            raise MFTError(
                f"Access denied opening {self.volume}. Reading the raw MFT "
                f"requires Administrator privileges.\n"
                f"  Fix: run this scan from an elevated shell, e.g. in an "
                f"admin PowerShell:\n"
                f'      python.exe "{me}" {self.drive}:\\ --engine mft\n'
                f"  Or use the unprivileged engine, which needs no elevation "
                f"and is the default:\n"
                f'      python3 "{me}" <path>'
            ) from exc
        except OSError as exc:
            raise MFTError(f"Cannot open {self.volume}: {exc}") from exc

    def close(self) -> None:
        if self.fh is not None:
            self.fh.close()
            self.fh = None

    def _read_at(self, offset: int, length: int) -> bytes:
        assert self.fh is not None
        self.fh.seek(offset)
        chunks = []
        remaining = length
        while remaining > 0:
            b = self.fh.read(remaining)
            if not b:
                break
            chunks.append(b)
            remaining -= len(b)
        return b"".join(chunks)

    def read_boot(self) -> None:
        boot = self._read_at(0, 512)
        if len(boot) < 512:
            raise MFTError(f"Short read of the boot sector on {self.volume}.")
        if boot[3:11] != b"NTFS    ":
            raise MFTError(
                f"{self.drive}: is not NTFS (OEM id {boot[3:11]!r}). The mft "
                f"engine only understands NTFS; use --engine scandir."
            )
        self.sector_size = struct.unpack_from("<H", boot, 0x0B)[0]
        spc = boot[0x0D]
        if spc >= 0x80:
            # Stored as a negative power of two for very large clusters.
            self.cluster_size = 1 << (256 - spc)
        else:
            self.cluster_size = self.sector_size * spc
        self.mft_lcn = struct.unpack_from("<Q", boot, 0x30)[0]
        cpr = struct.unpack_from("<b", boot, 0x40)[0]
        self.record_size = (1 << -cpr) if cpr < 0 else cpr * self.cluster_size
        if self.sector_size <= 0 or self.cluster_size <= 0 or self.record_size <= 0:
            raise MFTError("Boot sector geometry is not sane; refusing to guess.")

    def read_mft_runs(self) -> tuple[list[tuple[int, int]], int]:
        """Locate $MFT's own extents by parsing FILE record 0."""
        base = self.mft_lcn * self.cluster_size
        raw = bytearray(self._read_at(base, self.record_size))
        if len(raw) < self.record_size or raw[0:4] != b"FILE":
            raise MFTError(
                "The $MFT record does not start with a FILE signature; the "
                "volume may be BitLocker-locked or the geometry misread."
            )
        if not _apply_fixups(raw, self.sector_size):
            raise MFTError("Update-sequence fixups failed on the $MFT record.")
        view = memoryview(raw)
        runs: list[tuple[int, int]] = []
        real_size = 0
        for atype, attr_off, attr_len, non_res, name_len in self._iter_attrs(view):
            if atype != ATTR_DATA or name_len != 0 or not non_res:
                continue
            start_vcn = struct.unpack_from("<Q", raw, attr_off + 0x10)[0]
            run_off = struct.unpack_from("<H", raw, attr_off + 0x20)[0]
            if start_vcn == 0:
                real_size = struct.unpack_from("<Q", raw, attr_off + 0x30)[0]
            runs += _parse_data_runs(view[attr_off : attr_off + attr_len], run_off)
        if not runs:
            raise MFTError("Could not decode any $MFT data runs.")
        return runs, real_size

    @staticmethod
    def _iter_attrs(view: memoryview):
        """Yield (type, offset, length, non_resident, name_len) per attribute."""
        raw = view
        total = len(raw)
        try:
            pos = struct.unpack_from("<H", raw, 0x14)[0]
        except struct.error:
            return
        while 0 < pos and pos + 8 <= total:
            atype = struct.unpack_from("<I", raw, pos)[0]
            if atype == ATTR_END:
                return
            alen = struct.unpack_from("<I", raw, pos + 4)[0]
            if alen < 16 or pos + alen > total:
                return
            non_res = raw[pos + 8]
            name_len = raw[pos + 9]
            yield atype, pos, alen, non_res, name_len
            pos += alen

    def iter_records(self, runs: list[tuple[int, int]], real_size: int):
        """Stream (index, raw_record) over the whole MFT in big sequential reads."""
        rec_size = self.record_size
        cs = self.cluster_size
        index = 0
        limit = real_size // rec_size if real_size else None
        for lcn, count in runs:
            span = count * cs
            base = lcn * cs
            done = 0
            while done < span:
                want = min(MFT_READ_CHUNK, span - done)
                # Keep reads a whole number of records so a record is never
                # split across two chunks.
                want -= want % rec_size
                if want <= 0:
                    break
                blob = self._read_at(base + done, want)
                if not blob:
                    break
                for off in range(0, len(blob) - rec_size + 1, rec_size):
                    if limit is not None and index >= limit:
                        return
                    yield index, blob[off : off + rec_size]
                    index += 1
                done += len(blob)
                if len(blob) < want:
                    break

    def scan(
        self,
    ) -> tuple[dict[int, tuple[int, str, bool]], dict[int, int], list[str]]:
        """Parse every FILE record.

        Returns (entries, sizes, notes) where
          entries[frn] = (parent_frn, name, is_dir)
          sizes[frn]   = logical size of the unnamed $DATA stream
        """
        self.read_boot()
        runs, real_size = self.read_mft_runs()
        entries: dict[int, tuple[int, str, bool]] = {}
        sizes: dict[int, int] = {}
        best_ns: dict[int, int] = {}
        notes: list[str] = []
        n_attr_list = 0
        n_bad = 0
        n_records = 0
        last_beat = time.monotonic()

        for index, blob in self.iter_records(runs, real_size):
            n_records += 1
            if not self.quiet and n_records % 65536 == 0:
                now = time.monotonic()
                if now - last_beat >= HEARTBEAT_SECONDS:
                    last_beat = now
                    sys.stderr.write(
                        f"\r  parsing MFT... {n_records:>10,} records  "
                        f"{len(entries):>10,} entries"
                    )
                    sys.stderr.flush()
            if blob[0:4] != b"FILE":
                continue
            rec = bytearray(blob)
            if not _apply_fixups(rec, self.sector_size):
                n_bad += 1
                continue
            flags = struct.unpack_from("<H", rec, 0x16)[0]
            if not flags & 0x1:  # deleted record
                continue
            is_dir = bool(flags & 0x2)

            # An extension record carries attributes on behalf of a base
            # record. Its $DATA size still belongs to the base file, so
            # attribute it there rather than dropping it.
            base_ref = struct.unpack_from("<Q", rec, 0x20)[0]
            owner = (base_ref & 0x0000FFFFFFFFFFFF) if base_ref else index

            view = memoryview(rec)
            for atype, attr_off, attr_len, non_res, name_len in self._iter_attrs(view):
                if atype == ATTR_ATTRIBUTE_LIST:
                    n_attr_list += 1
                    continue
                if atype == ATTR_FILE_NAME and not non_res:
                    cl = struct.unpack_from("<I", rec, attr_off + 0x10)[0]
                    co = struct.unpack_from("<H", rec, attr_off + 0x14)[0]
                    c = attr_off + co
                    if cl < 0x42 or c + cl > len(rec):
                        continue
                    parent = struct.unpack_from("<Q", rec, c)[0] & 0x0000FFFFFFFFFFFF
                    nchars = rec[c + 0x40]
                    ns = rec[c + 0x41]
                    nstart = c + 0x42
                    nend = nstart + nchars * 2
                    if nend > len(rec):
                        continue
                    prio = _NS_PRIORITY.get(ns, 0)
                    if prio <= best_ns.get(owner, -1):
                        continue
                    name = bytes(rec[nstart:nend]).decode("utf-16-le", "replace")
                    best_ns[owner] = prio
                    entries[owner] = (parent, name, is_dir)
                elif atype == ATTR_DATA and name_len == 0:
                    # Only the unnamed stream counts toward "file size";
                    # alternate data streams are excluded, matching WizTree.
                    if non_res:
                        start_vcn = struct.unpack_from("<Q", rec, attr_off + 0x10)[0]
                        if start_vcn != 0:
                            # Later extent of a fragmented file: the size
                            # fields are only valid on the first extent.
                            continue
                        sz = struct.unpack_from("<Q", rec, attr_off + 0x30)[0]
                    else:
                        sz = struct.unpack_from("<I", rec, attr_off + 0x10)[0]
                    if sz > sizes.get(owner, -1):
                        sizes[owner] = sz

        if not self.quiet:
            sys.stderr.write("\r" + " " * 78 + "\r")
            sys.stderr.flush()
        notes.append(f"MFT records read: {n_records:,}")
        if n_bad:
            notes.append(f"records with failed fixups (skipped): {n_bad:,}")
        if n_attr_list:
            notes.append(
                f"{n_attr_list:,} records carry an $ATTRIBUTE_LIST. Sizes for "
                f"heavily fragmented files whose $DATA lives entirely in an "
                f"extension record with a non-zero starting VCN may be "
                f"underreported."
            )
        return entries, sizes, notes


def scan_mft(
    root: str,
    excludes: list[str],
    min_size: int,
    file_cap: int,
    quiet: bool,
    keep_metafiles: bool,
    image: str | None = None,
) -> ScanResult:
    m = _RE_WIN.match(root)
    if not m:
        raise MFTError(f"Cannot determine a drive letter from {root!r}.")
    drive = m.group(1)
    scanner = MFTScanner(drive, quiet, image)
    scanner.open()
    try:
        entries, sizes, notes = scanner.scan()
    finally:
        scanner.close()

    drive_root = f"{drive.upper()}:\\"
    path_cache: dict[int, str] = {ROOT_FRN: drive_root}

    def resolve(frn: int) -> str:
        """Walk parent references up to the volume root, memoizing as we go."""
        chain: list[int] = []
        cur = frn
        while cur not in path_cache:
            ent = entries.get(cur)
            if ent is None:
                return ""
            if cur in chain:  # corrupt parent cycle
                return ""
            chain.append(cur)
            cur = ent[0]
            if len(chain) > 512:
                return ""
        base = path_cache[cur]
        for frn2 in reversed(chain):
            name = entries[frn2][1]
            base = base + name if base.endswith("\\") else base + "\\" + name
            path_cache[frn2] = base
        return path_cache[frn]

    res = ScanResult()
    res.notes = notes
    # A bare drive letter must keep its trailing separator, or dirname() of a
    # top-level entry ("C:\\Users" -> "C:\\") never matches the root and the
    # roll-up leaves a stray zero-byte "C:" row behind.
    root_norm = root.rstrip("\\")
    if not root_norm or (len(root_norm) == 2 and root_norm[1] == ":"):
        root_norm = drive_root
    root_prefix = root_norm if root_norm.endswith("\\") else root_norm + "\\"
    root_lower = root_norm.lower()
    prefix_lower = root_prefix.lower()
    excl_lower = [e.lower() for e in excludes]

    def in_scope(path: str) -> bool:
        pl = path.lower()
        return pl == root_lower or pl.startswith(prefix_lower)

    def excluded(path: str) -> bool:
        if not excl_lower:
            return False
        pl = path.lower()
        nl = os.path.basename(pl)
        for pat in excl_lower:
            if fnmatch.fnmatchcase(nl, pat) or fnmatch.fnmatchcase(pl, pat):
                return True
        return False

    dirs = res.dirs
    dirs[root_norm] = [0, 0]
    heap: list[tuple[int, str, float]] = []
    n_unresolved = 0

    for frn, (_parent, name, is_dir) in entries.items():
        if not keep_metafiles and name.startswith("$") and frn < 32:
            continue
        path = resolve(frn)
        if not path:
            n_unresolved += 1
            continue
        if not in_scope(path) or excluded(path):
            continue
        if is_dir:
            res.n_dirs += 1
            if path not in dirs:
                dirs[path] = [0, 0]
        else:
            size = sizes.get(frn, 0)
            res.n_files += 1
            res.total_bytes += size
            parent_path = os.path.dirname(path)
            slot = dirs.get(parent_path)
            if slot is None:
                dirs[parent_path] = [size, 1]
            else:
                slot[0] += size
                slot[1] += 1
            if size >= min_size:
                if len(heap) < file_cap:
                    heapq.heappush(heap, (size, path, 0.0))
                elif size > heap[0][0]:
                    heapq.heapreplace(heap, (size, path, 0.0))
    res.files = heapq.nlargest(file_cap, heap)
    if n_unresolved:
        res.notes.append(
            f"{n_unresolved:,} records could not be resolved to a path (broken "
            f"or cyclic parent chain) and are excluded from the totals"
        )
    return res


# --------------------------------------------------------------------------- #
# Reporting
# --------------------------------------------------------------------------- #


def print_report(
    res: ScanResult,
    root: str,
    engine: str,
    elapsed: float,
    top: int,
    depth: int,
    style: str,
    threads: int,
) -> tuple[list[tuple[str, int, int]], list[tuple[int, str, float]]]:
    cum, cumn = rollup(res.dirs, root)
    out = sys.stdout.write

    def disp(p: str) -> str:
        return win_to_wsl(p, style)

    total = cum.get(root, res.total_bytes)
    out("=" * 78 + "\n")
    out(f"fastscan  target: {disp(root)}\n")
    out(
        f"          engine: {engine}"
        + (f" ({threads} threads)" if engine == "scandir" else "")
        + f"    elapsed: {elapsed:.2f}s\n"
    )
    out(f"          {res.n_files:,} files, {res.n_dirs:,} dirs, total {human(total)}\n")
    extras = []
    if res.n_errors:
        extras.append(f"{res.n_errors:,} unreadable entries skipped")
    if res.n_reparse:
        extras.append(f"{res.n_reparse:,} reparse points not followed")
    if extras:
        out("          " + "; ".join(extras) + "\n")
    for note in res.notes:
        out(f"          note: {note}\n")
    out("=" * 78 + "\n")

    ranked = sorted(
        ((p, cum[p], cumn.get(p, 0)) for p in cum), key=lambda t: t[1], reverse=True
    )
    out(f"\nTop {top} directories by cumulative size\n")
    out("-" * 78 + "\n")
    for p, size, nfiles in ranked[:top]:
        out(f"{human(size):>12}  {nfiles:>9,} files  {disp(p)}\n")

    out(f"\nTop {top} files by size\n")
    out("-" * 78 + "\n")
    if not res.files:
        out("  (none above the --min-size threshold)\n")
    for size, p, _mtime in res.files[:top]:
        out(f"{human(size):>12}  {disp(p)}\n")

    if depth > 0:
        out(f"\nCumulative tree to depth {depth}\n")
        out("-" * 78 + "\n")
        root_depth = root.rstrip("\\").count("\\")
        rows = []
        for p, size, _n in ranked:
            d = p.rstrip("\\").count("\\") - root_depth
            if 0 <= d <= depth:
                rows.append((p, size, d))
        rows.sort(key=lambda t: t[0].lower())
        for p, size, d in rows:
            label = os.path.basename(p.rstrip("\\")) or disp(p)
            out(f"{human(size):>12}  {'  ' * d}{label}\n")

    return ranked, res.files


def write_json(
    path: str,
    res: ScanResult,
    ranked: list[tuple[str, int, int]],
    root: str,
    engine: str,
    elapsed: float,
    cap: int,
    style: str,
    label: str | None = None,
) -> None:
    import json

    def disp(p: str) -> str:
        return win_to_wsl(p, style)

    doc = {
        "meta": {
            "target": disp(root),
            "target_windows": root,
            "engine": engine,
            "elapsed_seconds": round(elapsed, 3),
            "files": res.n_files,
            "dirs": res.n_dirs,
            "errors": res.n_errors,
            "reparse_points_skipped": res.n_reparse,
            "total_bytes": ranked[0][1]
            if ranked and ranked[0][0] == root
            else res.total_bytes,
            "notes": res.notes,
        },
        "dirs": [{"path": disp(p), "size": s, "files": n} for p, s, n in ranked[:cap]],
        "files": [
            {"path": disp(p), "size": s, "mtime": mt} for s, p, mt in res.files[:cap]
        ],
    }
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2)
    sys.stdout.write(f"\nJSON written to {label or path}\n")


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

EPILOG = """\
examples:
  fastscan.py                                 scan C:\\Users\\oystein (default)
  fastscan.py /c/work/desktop                 WSL path in, WSL paths out
  fastscan.py 'C:\\Windows' --top 40
  fastscan.py /c/users/oystein --depth 2 --min-size 200M
  fastscan.py /c --json /tmp/c.json --top 50
  fastscan.py C:\\ --engine mft                needs an elevated shell
  fastscan.py C:\\ --engine mft --image vol.img   parse a captured image, no admin

engines:
  scandir  multithreaded native os.scandir; no privileges needed; the default.
  mft      parses the raw NTFS Master File Table. Far faster on whole volumes,
           but requires Administrator. Known limits: sizes count only the
           unnamed $DATA stream (alternate data streams are ignored, as in
           WizTree), and a heavily fragmented file whose $DATA attribute lives
           entirely in an extension record at a non-zero starting VCN may be
           underreported. Directory hard links resolve to a single path.

notes:
  Reparse points (junctions, symlinks, OneDrive placeholders) are never
  followed, so cycles under AppData cannot trap or double-count the scan.
  Sizes are logical file sizes, not allocated-on-disk sizes.
"""


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="fastscan.py",
        description=(
            "Fast disk usage scanner. Enumeration always runs natively on "
            "Windows, because per-file stat() through WSL1's DrvFs is orders "
            "of magnitude slower."
        ),
        epilog=EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument(
        "path",
        nargs="?",
        help="directory to scan; WSL (/c/..., /mnt/c/...) or Windows (C:\\...) "
        f"form. Default: {DEFAULT_TARGET_WIN}",
    )
    p.add_argument("--engine", choices=("scandir", "mft"), default="scandir")
    p.add_argument(
        "--top",
        type=int,
        default=25,
        metavar="N",
        help="rows per table (default: 25)",
    )
    p.add_argument(
        "--threads",
        type=int,
        default=48,
        metavar="N",
        help="scandir worker threads (default: 48)",
    )
    p.add_argument("--json", metavar="FILE", help="also write machine-readable output")
    p.add_argument(
        "--min-size",
        type=parse_size,
        default=0,
        metavar="SPEC",
        help="only list files at least this large (e.g. 100M, 1.5G)",
    )
    p.add_argument(
        "--depth",
        type=int,
        default=0,
        metavar="N",
        help="also print a du-style cumulative tree to depth N",
    )
    p.add_argument(
        "--exclude",
        action="append",
        default=[],
        metavar="GLOB",
        help="skip entries whose name or full path matches (repeatable)",
    )
    p.add_argument(
        "--image",
        metavar="FILE",
        help="mft engine: read NTFS structures from a volume image file "
        "instead of the live device. Needs no elevation.",
    )
    p.add_argument(
        "--keep-metafiles",
        action="store_true",
        help="mft engine: include NTFS $-metafiles in the output",
    )
    p.add_argument("-q", "--quiet", action="store_true", help="no progress heartbeat")
    p.add_argument(_REEXEC_FLAG, action="store_true", help=argparse.SUPPRESS)
    p.add_argument(_OUTSTYLE_FLAG, default=None, help=argparse.SUPPRESS)
    p.add_argument(_JSONLABEL_FLAG, default=None, help=argparse.SUPPRESS)
    p.add_argument(_TTY_FLAG, action="store_true", help=argparse.SUPPRESS)
    return p


def main(argv: list[str]) -> int:
    _make_streams_safe()

    # Stage one: if a Linux interpreter is running us, hand the whole job to
    # Windows Python. Nothing below this point runs on the WSL side.
    if sys.platform != "win32":
        if _REEXEC_FLAG not in argv:
            return reexec_on_windows(argv)
        # Re-exec happened but landed on a non-Windows interpreter, so
        # `python.exe` on PATH is not really Windows Python. Stop rather than
        # bouncing between interpreters or running a hopelessly slow scan.
        sys.stderr.write(
            f"fastscan: re-executed into a non-Windows interpreter "
            f"(sys.platform={sys.platform!r}). Check what `python.exe` "
            f"resolves to on PATH.\n"
        )
        return 3

    args = build_parser().parse_args(argv)

    if args.path:
        style = args.__dict__.get("_out_style") or detect_out_style(args.path)
        try:
            root = wsl_to_win(args.path)
        except ValueError as exc:
            sys.stderr.write(f"fastscan: {exc}\n")
            return 2
    else:
        style = args.__dict__.get("_out_style") or "win"
        root = DEFAULT_TARGET_WIN

    root = os.path.abspath(root)
    if len(root) == 2 and root[1] == ":":
        root += "\\"
    if len(root) > 3:
        root = root.rstrip("\\")

    if args.image and args.engine != "mft":
        sys.stderr.write("fastscan: --image only applies to --engine mft\n")
        return 2
    if args.engine == "scandir" and not os.path.isdir(root):
        sys.stderr.write(f"fastscan: not a directory: {win_to_wsl(root, style)}\n")
        return 2
    if args.top < 1:
        sys.stderr.write("fastscan: --top must be at least 1\n")
        return 2
    threads = max(1, min(args.threads, 512))
    cap = args.top * 4
    # The heartbeat repaints one line with \r, which only makes sense on a
    # terminal. Redirected to a file or a pipe it would just prepend a run of
    # padding spaces to the report, so suppress it there. When re-executed from
    # WSL the parent reports the terminal state, since the child cannot see it.
    on_tty = args.__dict__.get("_tty") or sys.stderr.isatty()
    quiet = args.quiet or not on_tty

    started = time.monotonic()
    try:
        if args.engine == "mft":
            res = scan_mft(
                root,
                args.exclude,
                args.min_size,
                cap,
                quiet,
                args.keep_metafiles,
                args.image,
            )
        else:
            res = scan_scandir(root, threads, args.exclude, args.min_size, cap, quiet)
    except MFTError as exc:
        sys.stderr.write(f"fastscan: {exc}\n")
        return 4
    except KeyboardInterrupt:
        sys.stderr.write("\nfastscan: interrupted\n")
        return 130
    elapsed = time.monotonic() - started

    ranked, _files = print_report(
        res, root, args.engine, elapsed, args.top, args.depth, style, threads
    )
    if args.json:
        try:
            write_json(
                args.json,
                res,
                ranked,
                root,
                args.engine,
                elapsed,
                cap,
                style,
                args.__dict__.get("_json_label"),
            )
        except OSError as exc:
            sys.stderr.write(f"fastscan: cannot write {args.json}: {exc}\n")
            return 5
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
