"""Turn the DarkOne fooyin layout into the Plasma-following layout. Run once, with fooyin closed.

Usage: python3 fyl_style.py <in.fyl> <out.fyl>

Colours are left to the application palette (UseCustomColours off, no fixed colours), so the
waveform, spectrum and info panel follow the Plasma colour scheme live. Keeps every widget ID.
Splitter states keep their flags; only the sizes change.
"""

import base64
import json
import struct
import sys
import uuid

src, dst = sys.argv[1], sys.argv[2]
layout = json.loads(open(src).read())


def splitter_state(old_b64, sizes):
    # QSplitter::saveState(): magic, version, QList<int> sizes, then flags that stay as they are.
    raw = base64.b64decode(old_b64)
    magic, version, count = struct.unpack(">iiI", raw[:12])
    tail = raw[12 + 4 * count :]
    head = struct.pack(">iiI", magic, version, len(sizes))
    return base64.b64encode(
        head + struct.pack(f">{len(sizes)}i", *sizes) + tail
    ).decode()


def strip_colours(widget):
    for key in [k for k in widget if k.endswith("Colour") or k.endswith("Colours")]:
        del widget[key]
    widget["UseCustomColours"] = False


def walk(node, fn):
    if isinstance(node, dict):
        for key, value in node.items():
            fn(key, value)
            walk(value, fn)
    elif isinstance(node, list):
        for item in node:
            walk(item, fn)


root = layout["Widgets"][0]["SplitterVertical"]
wave, spectrum, tabs, main, transport, _status = (
    next(iter(w.values())) for w in root["Widgets"]
)

# WaveBar, Spectrum, TabStack, main area, transport, status bar.
root["State"] = splitter_state(root["State"], [130, 84, 230, 640, 44, 24])
root["Spacing"] = 4

strip_colours(wave)
wave["CursorWidth"] = 2

strip_colours(spectrum)
spectrum.update(
    {
        "BarSections": 12,
        "SectionSpacing": 1,
        "BarSpacing": 2,
        "ShowHorizontalGrid": False,
        "ShowRightLabels": False,
        "PeaksEnabled": False,
    }
)


def per_widget(key, value):
    if key == "LibraryFilter":
        value["RowHeight"] = 26
        value["AlternatingRows"] = True
    elif key == "LibraryTree":
        value["RowHeight"] = 26
    elif key == "Playlist":
        value["Preset"] = 12
    elif key == "ArtworkPanel":
        value["FadeCoverChanges"] = True
        value["FadeDurationMs"] = 180
    elif key == "Lyrics":
        value["UseCustomColours"] = False
        value["ShowScrollbar"] = False
        value["NoLyricsScript"] = "<alpha=120>No lyrics</alpha>"
        for font_key in ("BaseFont", "LineFont"):
            value.pop(font_key, None)  # use the Plasma font
    elif key in ("SplitterVertical", "SplitterHorizontal"):
        value["Spacing"] = 4


walk(tabs, per_widget)
walk(main, per_widget)

# Main area: sidebar | playlist.
main["State"] = splitter_state(main["State"], [640, 1272])

# Sidebar: cover, a label/value info block, then lyrics.
sidebar = main["Widgets"][0]["SplitterVertical"]
fields = [
    ("Artist", "$if2($meta(album artist),%albumartist%)"),
    ("Album", "$if2(%album%,-)"),
    ("Title", "<b>%title%</b>"),
    ("Date", "$if2(%date%,-)"),
    ("Genre", "$if2(%genre%,-)"),
    ("Format", "%codec%  ·  %samplerate% Hz[  ·  %bitdepth% bit]  ·  %channels%"),
]
# Labels in a monospace font, padded to the same width, so the values line up without a table.
info_script = "$crlf()".join(
    f"<font=monospace><alpha=130>{label:<8}</alpha></font>{value}"
    for label, value in fields
)
if not any("ScriptDisplay" in w for w in sidebar["Widgets"]):
    sidebar["Widgets"].insert(1, {"ScriptDisplay": {"ID": uuid.uuid4().hex}})
for widget in sidebar["Widgets"]:
    if "ScriptDisplay" in widget:
        widget["ScriptDisplay"].update(
            {
                "Script": info_script,
                "Font": "",
                "BackgroundColour": "",
                "ForegroundColour": "",
                "LinkColour": "",
                "HorizontalAlignment": 1,
                "VerticalAlignment": 128,
                "ShowScrollbar": False,
                "ShowStoppedTrack": True,
            }
        )
sidebar["State"] = splitter_state(sidebar["State"], [320, 150, 170])

transport["State"] = splitter_state(transport["State"], [110, 180, 1450, 150])

open(dst, "w").write(json.dumps(layout, indent=4))
print("wrote", dst)
