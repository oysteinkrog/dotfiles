"""Build the "np-a" fooyin layout from the DarkOne layout. Run once, with fooyin closed.

Usage: python3 fyl_style.py <DarkOne.fyl> <out.fyl> <accent> <muted> <window>   (colours as #rrggbb)

Layout:
  left    cover, now-playing text (title, artist, album in the accent colour, format), synced lyrics
  right   waveform seekbar, spectrum, library search box, playlist with cover group headers
  bottom  shuffle and repeat, playback buttons, "artist - title", volume

Colours come from the application palette, so they follow the Plasma colour scheme live. The accent
appears in the album line and the current lyric line, and the now-playing text uses a fixed muted colour
(the info panel ignores <alpha> without a colour). The lyrics get the window background so they blend into
the header. fooyin-theme-sync swaps all three when Plasma changes.
There are no facet filters: the search box searches the whole library into a "Search Results" playlist.
"""

import base64
import json
import struct
import sys
import uuid
import zlib

src, dst, accent, muted, window = sys.argv[1:6]
old = json.loads(open(src).read())

VERTICAL, HORIZONTAL = 2, 1
ALIGN_LEFT, ALIGN_RIGHT, ALIGN_HCENTER = 0x1, 0x2, 0x4
ALIGN_TOP, ALIGN_VCENTER = 0x20, 0x80


def splitter_state(orientation, sizes):
    # QSplitter::saveState(): magic, version, sizes, childrenCollapsible, handleWidth, opaqueResize,
    # orientation, childrenCollapsible.
    data = struct.pack(">iiI", 0xFF, 1, len(sizes)) + struct.pack(
        f">{len(sizes)}i", *sizes
    )
    return base64.b64encode(
        data + struct.pack(">?i?i?", False, -1, True, orientation, False)
    ).decode()


def splitter(orientation, children, sizes, locked=None):
    node = {
        "State": splitter_state(orientation, sizes),
        "Spacing": 4,
        "Widgets": children,
    }
    if locked:
        node["Locked"] = locked
    return {
        ("SplitterVertical" if orientation == VERTICAL else "SplitterHorizontal"): node
    }


def find(node, name):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == name:
                return value
            found = find(value, name)
            if found is not None:
                return found
    elif isinstance(node, list):
        for item in node:
            found = find(item, name)
            if found is not None:
                return found
    return None


def strip_colours(widget):
    for key in [k for k in widget if k.endswith("Colour") or k.endswith("Colours")]:
        del widget[key]
    widget["UseCustomColours"] = False


def header_state(columns, width=1300):
    # AutoHeaderView::saveHeaderState(): pixel widths, logical order, width shares, stretch, sort order,
    # sort section (-1: none), as a qCompress'ed stream.
    shares = [share for _, _, share in columns]
    shares = [s / sum(shares) for s in shares]
    data = struct.pack(">I", len(shares)) + b"".join(
        struct.pack(">i", max(20, round(s * width))) for s in shares
    )
    data += struct.pack(">I", len(shares)) + b"".join(
        struct.pack(">i", i) for i in range(len(shares))
    )
    data += struct.pack(">I", len(shares)) + b"".join(
        struct.pack(">d", s) for s in shares
    )
    data += struct.pack(">?ii", True, 0, -1)
    return base64.b64encode(
        struct.pack(">I", len(data)) + zlib.compress(data, 9)
    ).decode()


def script_display(script, h_align, v_align, font=""):
    return {
        "ScriptDisplay": {
            "ID": uuid.uuid4().hex,
            "Script": script,
            "Font": font,
            "BackgroundColour": "",
            "ForegroundColour": "",
            "LinkColour": "",
            "HorizontalAlignment": h_align,
            "VerticalAlignment": v_align,
            "ShowScrollbar": False,
            "ShowStoppedTrack": True,
        }
    }


# Widgets carried over from the DarkOne layout.
wave = find(old, "WaveBar")
spectrum = find(old, "Spectrum")
artwork = find(old, "ArtworkPanel")
lyrics = find(old, "Lyrics")
playlist = find(old, "Playlist")
playlist_controls = find(old, "PlaylistControls")
player_controls = find(old, "PlayerControls")
volume = find(old, "VolumeControls")

strip_colours(wave)
wave.update({"CursorWidth": 2, "ShowLabels": True})

strip_colours(spectrum)
spectrum.update(
    {
        "BandCount": 120,
        "BarSections": 1,
        "BarSpacing": 2,
        "PeaksEnabled": False,
        "ShowHorizontalGrid": False,
        "ShowVerticalGrid": False,
        "ShowRightLabels": False,
        "ShowBottomLabels": False,
    }
)


artwork.update(
    {
        "CoverAlignment": ALIGN_HCENTER | ALIGN_TOP,
        "KeepAspectRatio": True,
        "FadeCoverChanges": True,
        "FadeDurationMs": 180,
    }
)

for key in [k for k in lyrics if k.endswith("Colour")]:
    del lyrics[key]
for key in ("BaseFont", "LineFont", "WordFont", "WordLineFont"):
    lyrics.pop(key, None)  # use the Plasma font
lyrics.update(
    {
        "UseCustomColours": True,  # line colours other than the current one fall back to the palette
        "CurrentLineColour": accent,
        "BackgroundColour": window,
        "Alignment": ALIGN_LEFT,  # lyrics accept only plain left, right or centre
        "LeftMargin": 14,
        "RightMargin": 14,
        "TopMargin": 6,
        "BottomMargin": 14,
        "LineSpacing": 8,
        "ShowScrollbar": False,
        "EdgeFadeMode": 2,
        "EdgeFadeSize": 24,
        "NoLyricsScript": "<alpha=110>No lyrics</alpha>",
    }
)

# Column mode keeps the playing icon in its own column: playing icon, #, title / track artist, duration.
columns = [
    (8, ALIGN_HCENTER, 0.04),
    (30, ALIGN_RIGHT, 0.05),
    (31, None, 0.79),
    (7, ALIGN_RIGHT, 0.12),
]
playlist.update(
    {
        "Preset": 12,
        "SingleMode": False,
        "Columns": "|".join(
            f"{cid}:{align}" if align else str(cid) for cid, align, _ in columns
        ),
        "HeaderState": header_state(columns),
    }
)

now_playing = "$crlf()".join(
    [
        "<size=20><b>%title%</b></size>",
        f"<size=15><color={muted}>$if2(%artist%,Unknown Artist)</color></size>",
        f"<size=14><color={accent}>$if2(%album%,Unknown Album)[ (%date%)]</color></size>",
        f"<color={muted}>%codec%[ %bitdepth%-bit]  ·  %samplerate% Hz</color>",
    ]
)
transport_text = f"<color={muted}>$if2(%artist%,Unknown Artist)</color>  —  %title%"

# Sized for a half-screen window (about 960 px wide). The sidebar is a fixed 360 px, and the cover slot is
# as tall as the sidebar is wide, so the cover fills it edge to edge. Locked slots keep their size when
# the window grows; the lyrics and the playlist take the rest.
SIDEBAR = 360
sidebar = splitter(
    VERTICAL,
    [
        {"ArtworkPanel": artwork},
        script_display(now_playing, ALIGN_LEFT, ALIGN_TOP),
        {"Lyrics": lyrics},
    ],
    [SIDEBAR, 130, 560],
    locked=[True, True, False],
)
right = splitter(
    VERTICAL,
    [
        {"WaveBar": wave},
        {"Spectrum": spectrum},
        {
            "SearchBar": {
                "SearchMode": 0,  # library
                "AutoSearch": True,
                "ShowAll": False,
                "Placeholder": "Search in library...",
            }
        },
        {"Playlist": playlist},
    ],
    [90, 36, 34, 886],
    locked=[True, True, True, False],
)
main = splitter(HORIZONTAL, [sidebar, right], [SIDEBAR, 600], locked=[True, False])
transport = splitter(
    HORIZONTAL,
    [
        {"PlaylistControls": playlist_controls},
        {"PlayerControls": player_controls},
        script_display(transport_text, ALIGN_LEFT, ALIGN_VCENTER),
        {"VolumeControls": volume},
    ],
    [90, 150, 1500, 170],
    locked=[True, True, False, True],
)
root = splitter(VERTICAL, [main, transport], [1100, 52], locked=[False, True])

layout = {key: value for key, value in old.items() if key != "Widgets"}
layout["Widgets"] = [root]
open(dst, "w").write(json.dumps(layout, indent=4))
print("wrote", dst)
