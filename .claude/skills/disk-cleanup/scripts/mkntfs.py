#!/usr/bin/env python3
"""Build a tiny synthetic NTFS volume image to exercise fastscan's MFT parser.

Not a real filesystem: only the structures the parser reads are populated
(boot sector, $MFT record 0 with its data runs, and a handful of FILE records
covering resident/non-resident $DATA, namespace preference, deleted records,
named streams, subtree filtering and the extension-record path).
"""

import struct
import sys

SECTOR = 512
SPC = 8
CLUSTER = SECTOR * SPC  # 4096
REC = 1024
MFT_LCN = 16
MFT_CLUSTERS = 16
MFT_OFFSET = MFT_LCN * CLUSTER  # 65536
N_RECORDS = (MFT_CLUSTERS * CLUSTER) // REC  # 64

ROOT = 5

FN_POSIX, FN_WIN32, FN_DOS, FN_BOTH = 0, 1, 2, 3


def boot_sector() -> bytes:
    b = bytearray(SECTOR)
    b[0:3] = b"\xeb\x52\x90"
    b[3:11] = b"NTFS    "
    struct.pack_into("<H", b, 0x0B, SECTOR)
    b[0x0D] = SPC
    struct.pack_into("<Q", b, 0x28, 1 << 20)  # total sectors
    struct.pack_into("<Q", b, 0x30, MFT_LCN)
    struct.pack_into("<Q", b, 0x38, 2)  # $MFTMirr LCN
    struct.pack_into("<b", b, 0x40, -10)  # 2**10 = 1024-byte records
    struct.pack_into("<b", b, 0x44, 1)
    b[510:512] = b"\x55\xaa"
    return bytes(b)


def resident_attr(atype: int, content: bytes, name: str = "", instance: int = 0) -> bytes:
    nb = name.encode("utf-16-le")
    name_off = 0x18
    content_off = name_off + len(nb)
    content_off += (-content_off) % 8
    total = content_off + len(content)
    total += (-total) % 8
    a = bytearray(total)
    struct.pack_into("<I", a, 0x00, atype)
    struct.pack_into("<I", a, 0x04, total)
    a[0x08] = 0
    a[0x09] = len(name)
    struct.pack_into("<H", a, 0x0A, name_off if nb else 0)
    struct.pack_into("<H", a, 0x0C, 0)
    struct.pack_into("<H", a, 0x0E, instance)
    struct.pack_into("<I", a, 0x10, len(content))
    struct.pack_into("<H", a, 0x14, content_off)
    a[name_off : name_off + len(nb)] = nb
    a[content_off : content_off + len(content)] = content
    return bytes(a)


def nonresident_attr(
    atype: int,
    real_size: int,
    runs: bytes,
    name: str = "",
    start_vcn: int = 0,
    instance: int = 0,
) -> bytes:
    nb = name.encode("utf-16-le")
    name_off = 0x40
    run_off = name_off + len(nb)
    run_off += (-run_off) % 8
    total = run_off + len(runs)
    total += (-total) % 8
    a = bytearray(total)
    struct.pack_into("<I", a, 0x00, atype)
    struct.pack_into("<I", a, 0x04, total)
    a[0x08] = 1
    a[0x09] = len(name)
    struct.pack_into("<H", a, 0x0A, name_off if nb else 0)
    struct.pack_into("<H", a, 0x0C, 0)
    struct.pack_into("<H", a, 0x0E, instance)
    struct.pack_into("<Q", a, 0x10, start_vcn)
    last_vcn = max(0, (real_size + CLUSTER - 1) // CLUSTER - 1)
    struct.pack_into("<Q", a, 0x18, last_vcn)
    struct.pack_into("<H", a, 0x20, run_off)
    struct.pack_into("<H", a, 0x22, 0)
    alloc = ((real_size + CLUSTER - 1) // CLUSTER) * CLUSTER
    struct.pack_into("<Q", a, 0x28, alloc)
    struct.pack_into("<Q", a, 0x30, real_size)
    struct.pack_into("<Q", a, 0x38, real_size)
    a[name_off : name_off + len(nb)] = nb
    a[run_off : run_off + len(runs)] = runs
    return bytes(a)


def file_name_attr(parent: int, name: str, namespace: int, seq: int = 1) -> bytes:
    c = bytearray(0x42 + len(name) * 2)
    struct.pack_into("<Q", c, 0x00, (parent & 0x0000FFFFFFFFFFFF) | (seq << 48))
    struct.pack_into("<Q", c, 0x28, 0)
    struct.pack_into("<Q", c, 0x30, 0)
    struct.pack_into("<I", c, 0x38, 0)
    c[0x40] = len(name)
    c[0x41] = namespace
    c[0x42 :] = name.encode("utf-16-le")
    return resident_attr(0x30, bytes(c))


def make_run(lcn: int, count: int) -> bytes:
    """One data run with 1-byte length and 1-byte signed LCN delta."""
    return bytes([0x11, count & 0xFF, lcn & 0xFF]) + b"\x00"


def build_record(number: int, flags: int, attrs: list[bytes], base_ref: int = 0) -> bytes:
    """Assemble a FILE record and apply update-sequence protection."""
    usa_off = 0x30
    usa_count = REC // SECTOR + 1  # 3
    attr_off = usa_off + usa_count * 2
    attr_off += (-attr_off) % 8

    r = bytearray(REC)
    r[0:4] = b"FILE"
    struct.pack_into("<H", r, 0x04, usa_off)
    struct.pack_into("<H", r, 0x06, usa_count)
    struct.pack_into("<H", r, 0x10, 1)  # sequence
    struct.pack_into("<H", r, 0x12, 1)  # hard links
    struct.pack_into("<H", r, 0x14, attr_off)
    struct.pack_into("<H", r, 0x16, flags)
    struct.pack_into("<I", r, 0x1C, REC)
    struct.pack_into("<Q", r, 0x20, base_ref)
    struct.pack_into("<H", r, 0x28, len(attrs) + 1)
    struct.pack_into("<I", r, 0x2C, number)

    pos = attr_off
    for a in attrs:
        r[pos : pos + len(a)] = a
        pos += len(a)
    struct.pack_into("<I", r, pos, 0xFFFFFFFF)
    pos += 4
    struct.pack_into("<I", r, 0x18, pos)  # used size

    # Encode the fixups: stash each sector's last two bytes in the update
    # sequence array and stamp the USN in their place.
    usn = 0x0001
    struct.pack_into("<H", r, usa_off, usn)
    for i in range(1, usa_count):
        tail = i * SECTOR - 2
        struct.pack_into("<H", r, usa_off + i * 2, struct.unpack_from("<H", r, tail)[0])
        struct.pack_into("<H", r, tail, usn)
    return bytes(r)


def main(out_path: str) -> None:
    records: dict[int, bytes] = {}

    IN_USE, IS_DIR = 0x1, 0x2

    # Record 0: $MFT, whose non-resident $DATA runlist locates the table itself.
    records[0] = build_record(
        0,
        IN_USE,
        [
            file_name_attr(ROOT, "$MFT", FN_WIN32),
            nonresident_attr(
                0x80, MFT_CLUSTERS * CLUSTER, make_run(MFT_LCN, MFT_CLUSTERS)
            ),
        ],
    )

    # Record 5: volume root.
    records[ROOT] = build_record(
        ROOT, IN_USE | IS_DIR, [file_name_attr(ROOT, ".", FN_WIN32)]
    )

    records[32] = build_record(
        32, IN_USE | IS_DIR, [file_name_attr(ROOT, "Users", FN_WIN32)]
    )
    records[33] = build_record(
        33, IN_USE | IS_DIR, [file_name_attr(32, "oystein", FN_WIN32)]
    )

    # Non-resident $DATA: size must come from the real_size field.
    records[34] = build_record(
        34,
        IN_USE,
        [
            file_name_attr(33, "big.bin", FN_WIN32),
            nonresident_attr(0x80, 5_000_000, make_run(100, 1221)),
        ],
    )
    # Resident $DATA: size is the content length.
    records[35] = build_record(
        35,
        IN_USE,
        [file_name_attr(33, "small.txt", FN_WIN32), resident_attr(0x80, b"x" * 123)],
    )
    # Two names, DOS first: the WIN32 name must win regardless of order.
    records[36] = build_record(
        36,
        IN_USE,
        [
            file_name_attr(33, "LONGFI~1.TXT", FN_DOS),
            file_name_attr(33, "longfilename.txt", FN_WIN32),
            resident_attr(0x80, b"y" * 77),
        ],
    )
    records[37] = build_record(
        37, IN_USE | IS_DIR, [file_name_attr(33, "docs", FN_WIN32)]
    )
    records[38] = build_record(
        38,
        IN_USE,
        [file_name_attr(37, "note.md", FN_WIN32), resident_attr(0x80, b"z" * 456)],
    )
    # Deleted: the in-use bit is clear, so this must not appear at all.
    records[39] = build_record(
        39,
        0,
        [
            file_name_attr(33, "ghost.bin", FN_WIN32),
            nonresident_attr(0x80, 999_999_999, make_run(50, 244141)),
        ],
    )
    # Named stream must be ignored; only the unnamed $DATA counts.
    records[40] = build_record(
        40,
        IN_USE,
        [
            file_name_attr(33, "ads.bin", FN_WIN32),
            resident_attr(0x80, b"a" * 200),
            nonresident_attr(0x80, 999_999, make_run(200, 245), name="stream"),
        ],
    )
    # $ATTRIBUTE_LIST with no $DATA in the base record.
    records[41] = build_record(
        41,
        IN_USE,
        [
            file_name_attr(33, "frag.bin", FN_WIN32),
            resident_attr(0x20, b"\x00" * 32),
        ],
    )
    # Extension record carrying frag.bin's $DATA at VCN 0.
    records[42] = build_record(
        42,
        IN_USE,
        [nonresident_attr(0x80, 7_000_000, make_run(300, 1710))],
        base_ref=41 | (1 << 48),
    )
    # Outside the C:\Users\oystein subtree: must be filtered out.
    records[43] = build_record(
        43,
        IN_USE,
        [file_name_attr(32, "outside.txt", FN_WIN32), resident_attr(0x80, b"o" * 424)],
    )
    # DOS-only name: no better namespace exists, so the 8.3 name is used.
    records[44] = build_record(
        44,
        IN_USE,
        [file_name_attr(33, "SHORT~1.TXT", FN_DOS), resident_attr(0x80, b"s" * 11)],
    )

    image = bytearray(MFT_OFFSET + MFT_CLUSTERS * CLUSTER)
    image[0:SECTOR] = boot_sector()
    for i in range(N_RECORDS):
        off = MFT_OFFSET + i * REC
        if i in records:
            image[off : off + REC] = records[i]
        # Unused slots stay zeroed; the parser skips anything without "FILE".

    with open(out_path, "wb") as fh:
        fh.write(image)
    print(f"wrote {out_path} ({len(image)} bytes, {N_RECORDS} MFT records)")


if __name__ == "__main__":
    main(sys.argv[1])
