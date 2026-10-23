// Writes fooyin settings blobs (theme, playlist presets and columns, library filter, colours) into a
// fooyin.conf, using fooyin's own formats.
//
// Usage: fyhelper <fooyin.conf> darkone
//        fyhelper <fooyin.conf> plasma <accent #rrggbb>
//        fyhelper <fooyin.conf> style <KDE colours file>
//
// darkone: the foobar2000 DarkOne look of the main instance (fixed greys, orange accent).
// plasma:  no saved theme, so fooyin follows the Plasma palette live. Only the accent inside text scripts is
//          fixed, so fooyin-theme-sync runs this again when the Plasma colour scheme changes.
// style:   the plasma layout, plus a saved theme (palette, waveform, spectrum) built from a KDE colours file,
//          such as a Plasma style's own colors file. Used when the Plasma style and the app colour scheme differ.
#include "spectrumcolours.h"
#include "wavebarcolours.h"

#include <gui/theme/fytheme.h>

#include <QApplication>
#include <QDataStream>
#include <QDir>
#include <QFile>
#include <QSettings>

#include <cstdio>

using namespace Fooyin;
using namespace Qt::StringLiterals;

// Copied from src/gui/theme/fytheme.cpp: libfooyin_gui does not export these.
namespace Fooyin {
QDataStream& operator<<(QDataStream& stream, const PaletteKey& key)
{
    return stream << key.group << key.role;
}
QDataStream& operator>>(QDataStream& stream, PaletteKey& key)
{
    return stream >> key.group >> key.role;
}
QDataStream& operator<<(QDataStream& stream, const FyTheme& scheme)
{
    return stream << 1 << scheme.id << scheme.index << scheme.name << scheme.isDefault << scheme.colours
                  << scheme.fonts;
}
QDataStream& operator>>(QDataStream& stream, FyTheme& scheme)
{
    int version{0};
    return stream >> version >> scheme.id >> scheme.index >> scheme.name >> scheme.isDefault >> scheme.colours
        >> scheme.fonts;
}
} // namespace Fooyin

// foobar2000 writes the album artist of many MP3s to a custom "ALBUM ARTIST" field, which fooyin keeps as an
// extra tag. Prefer it, then fall back to fooyin's album artist (which itself falls back to the track artist).
static const QString AlbumArtist = u"$if2($meta(album artist),%albumartist%)"_s;

// Copies of fooyin's private serialisers (src/gui/filters/filterfwd.h, src/gui/playlist/playlistpreset.cpp).
static void writeFilterColumn(QDataStream& s, int id, int index, const QString& name, const QString& field)
{
    s << qint32{-0x46434F4C} << qint32{2} << id << index << name << field << QString{};
}

struct Preset
{
    int id;
    int index;
    QString name;
    QString title, subtitle, sideText, info;
    int headerHeight;
    bool showCover, simple;
    QString grouping;
    QString subLeft, subRight;
    int subHeight;
    QString left, right;
    int trackHeight;
};

static void writePreset(QDataStream& s, const Preset& p)
{
    s << -1 << 4 << p.id << p.index << p.name;
    s << p.title << p.subtitle << p.sideText << p.info << p.headerHeight << p.showCover << p.simple;
    s << quint32{1} << p.subLeft << p.subRight << p.subHeight; // one subheader row (QList size, then the row)
    s << p.left << p.right << p.trackHeight;                     // track row
    s << false << false;                                          // inset subheaders, cover below subheaders
    s << p.grouping << QStringList{QString{}};                    // header grouping, subheader groupings
}

static QByteArray registryBlob(int count, const std::function<void(QDataStream&)>& writeItems)
{
    QByteArray bytes;
    QDataStream s(&bytes, QIODevice::WriteOnly);
    s.setVersion(QDataStream::Qt_6_0);
    s << count;
    writeItems(s);
    return qCompress(bytes, 9);
}

// Serialiser copied from src/gui/playlist/playlistcolumn.h.
static void writePlaylistColumn(QDataStream& s, int id, int index, const QString& name, const QString& field)
{
    s << qint32{-0x50434F4C} << qint32{2} << id << true << index << name << field << QString{} << QString{};
}

// Playlist preset modelled on the SimPlaylist "Artist - album / cover" grouping used with DarkOne.
static const Preset DarkOne{
    .id           = 10,
    .index        = 4,
    .name         = u"DarkOne"_s,
    .title        = u"<sized=2><color=#e8751a>"_s + AlbumArtist
             + u" - </color><color=#8c5a32>[%date%]</color> <color=#e8751a>$if2(%album%,Unknown Album)</color></sized>"_s,
    .subtitle     = {},
    .sideText     = {},
    .info         = {},
    .headerHeight = 34,
    .showCover    = false,
    .simple       = true,
    .grouping     = AlbumArtist + u"|%date%|%album%"_s,
    .subLeft      = u"$ifgreater($max(%disctotal%,%disc%),1,<color=#8c5a32>   Disc %disc%</color>)"_s,
    .subRight     = {},
    .subHeight    = 22,
    .left         = u"   $num(%track%,2)      %title%[<alpha=150>  ▪  %trackartist%]"_s,
    .right        = u"$ifgreater(%playcount%,0,<alpha=120>%playcount%x</alpha>     )%duration%     $upper(%codec%)  "_s,
    .trackHeight  = 20,
};

// Plasma preset: album group header with the cover, the album in bold, "artist · year" and "tracks · length" under
// it. Muted text uses <alpha>, so it follows the palette's text colour. The accent parameter is kept for the
// column scripts; the header itself uses no fixed colour.
static Preset plasmaPreset(const QString& /*accent*/)
{
    return {
        .id           = 12,
        .index        = 5,
        .name         = u"Plasma"_s,
        .title        = u"<b><sized=3>$if2(%album%,Unknown Album)</sized></b>"_s,
        .subtitle     = u"<sized=1><alpha=170>"_s + AlbumArtist + u"[  ·  %date%]</alpha></sized>"_s,
        .sideText     = {},
        .info         = u"<alpha=130>%trackcount% tracks  ·  %playtime%</alpha>"_s,
        .headerHeight = 84,
        .showCover    = true,
        .simple       = false,
        .grouping     = AlbumArtist + u"|%date%|%album%"_s,
        .subLeft      = u"$ifgreater($max(%disctotal%,%disc%),1,<alpha=140>Disc %disc%</alpha>)"_s,
        .subRight     = {},
        .subHeight    = 24,
        .left         = u"$num(%track%,2)   %title%[<alpha=140>  ·  %trackartist%</alpha>]"_s,
        .right        = u"<alpha=140>%duration%</alpha>"_s,
        .trackHeight  = 28,
    };
}

static void writeDarkOne(QSettings& settings)
{
    settings.setValue(u"PlaylistWidget/PlaylistColumns"_s, registryBlob(4, [](QDataStream& s) {
        writePlaylistColumn(s, 30, 23, u"#"_s, u"$num(%track%,2)"_s);
        writePlaylistColumn(s, 31, 24, u"Title / track artist"_s, u"%title%[<alpha=150>  ▪  %trackartist%]"_s);
        writePlaylistColumn(s, 32, 25, u"Format"_s, u"%codec%"_s);
        writePlaylistColumn(s, 33, 26, u"Plays"_s, u"$ifgreater(%playcount%,0,<alpha=120>%playcount%x</alpha>)"_s);
    }));

    settings.setValue(u"PlaylistWidget/Presets"_s, registryBlob(1, [](QDataStream& s) { writePreset(s, DarkOne); }));
    settings.setValue(u"PlaylistWidget/CurrentPreset"_s, DarkOne.id);

    // Theme: neutral dark greys with an orange accent, like DarkOne.
    FyTheme theme;
    theme.name     = u"DarkOne"_s;
    const auto set = [&theme](QPalette::ColorRole role, const QColor& colour) {
        theme.colours.insert(PaletteKey{.role = role}, colour);
    };
    set(QPalette::Window, {43, 43, 43});
    set(QPalette::WindowText, {215, 215, 215});
    set(QPalette::Base, {36, 36, 36});
    set(QPalette::AlternateBase, {44, 44, 44});
    set(QPalette::Text, {215, 215, 215});
    set(QPalette::Button, {52, 52, 52});
    set(QPalette::ButtonText, {215, 215, 215});
    set(QPalette::Highlight, {82, 82, 82});
    set(QPalette::HighlightedText, {255, 255, 255});
    set(QPalette::ToolTipBase, {52, 52, 52});
    set(QPalette::ToolTipText, {215, 215, 215});
    set(QPalette::PlaceholderText, {128, 128, 128});
    set(QPalette::Link, {232, 117, 26});
    set(QPalette::BrightText, {232, 117, 26});
    set(QPalette::Light, {70, 70, 70});
    set(QPalette::Midlight, {58, 58, 58});
    set(QPalette::Mid, {40, 40, 40});
    set(QPalette::Dark, {28, 28, 28});
    set(QPalette::Shadow, {15, 15, 15});
    settings.setValue(u"Theme/CustomTheme"_s, QVariant::fromValue(theme));

    // Waveform seekbar: orange wave, lighter where already played.
    using WT = WaveBar::Colours::Type;
    WaveBar::Colours wave;
    const QColor orange{232, 117, 26}, orangeLight{255, 175, 90}, orangeDark{160, 75, 12}, orangeRmsPlayed{225, 135, 50};
    wave.waveColours = {
        {WT::BgUnplayed, QColor{28, 28, 28}},  {WT::BgPlayed, QColor{28, 28, 28}},
        {WT::MaxUnplayed, orange},             {WT::MinUnplayed, orange},
        {WT::MaxPlayed, orangeLight},          {WT::MinPlayed, orangeLight},
        {WT::RmsMaxUnplayed, orangeDark},      {WT::RmsMinUnplayed, orangeDark},
        {WT::RmsMaxPlayed, orangeRmsPlayed},   {WT::RmsMinPlayed, orangeRmsPlayed},
        {WT::MaxBorder, Qt::transparent},      {WT::MinBorder, Qt::transparent},
        {WT::RmsMaxBorder, Qt::transparent},   {WT::RmsMinBorder, Qt::transparent},
        {WT::Cursor, QColor{255, 255, 255}},   {WT::SeekingCursor, QColor{255, 255, 255}},
        {WT::PlayedThreshold, QColor{200, 200, 200}},
    };
    settings.setValue(u"WaveBar/Colours"_s, QVariant::fromValue(wave));

    // Spectrum: beige bars on near-black, like the foobar2000 spectrum panel.
    using ST = Spectrum::Colours::Type;
    Spectrum::Colours spectrum;
    spectrum.setColour(ST::Background, {28, 28, 28});
    spectrum.setColour(ST::BarGradient, {236, 222, 200});
    spectrum.setColour(ST::Peaks, {200, 200, 200});
    spectrum.setColour(ST::Text, {150, 150, 150});
    spectrum.setColour(ST::HorizontalGrid, {60, 60, 60});
    spectrum.setColour(ST::VerticalGrid, {45, 45, 45});
    spectrum.setColour(ST::OctaveGrid, {60, 60, 60});
    settings.setValue(u"Spectrum/Colours"_s, QVariant::fromValue(spectrum));
}

static void writePlasma(QSettings& settings, const QString& accent)
{
    settings.setValue(u"PlaylistWidget/PlaylistColumns"_s, registryBlob(4, [&](QDataStream& s) {
        writePlaylistColumn(s, 30, 23, u"#"_s, u"<alpha=140>$num(%track%,2)</alpha>"_s);
        writePlaylistColumn(s, 31, 24, u"Title / track artist"_s,
                            u"$if(%isplaying%,<color="_s + accent
                                + u">%title%</color>,%title%)[<alpha=140>  ·  %trackartist%</alpha>]"_s);
        writePlaylistColumn(s, 32, 25, u"Format"_s, u"<alpha=140>$upper(%codec%)</alpha>"_s);
        writePlaylistColumn(s, 33, 26, u"Plays"_s, u"$ifgreater(%playcount%,0,<alpha=140>%playcount%x</alpha>)"_s);
    }));

    // Keep DarkOne as a second preset so it can still be picked in the playlist's context menu.
    const Preset plasma = plasmaPreset(accent);
    settings.setValue(u"PlaylistWidget/Presets"_s, registryBlob(2, [&](QDataStream& s) {
        writePreset(s, DarkOne);
        writePreset(s, plasma);
    }));
    settings.setValue(u"PlaylistWidget/CurrentPreset"_s, plasma.id);
    settings.setValue(u"PlaylistWidget/AlternatingColours"_s, true);
    settings.setValue(u"PlaylistWidget/Header"_s, false); // no column header row; the group headers carry it

    // fooyin's default playing row is the accent at alpha 110, which stands out too much. Same colour, fainter.
    QColor playingRow = QColor::fromString(accent).lighter(150);
    playingRow.setAlpha(45);
    settings.setValue(u"PlaylistWidget/PlayingRowColour"_s, playingRow);

    // Everything below falls back to the application palette, which Plasma updates live.
    for(const auto* key : {"Theme/CustomTheme", "Interface/Style", "PlaylistWidget/PlayingRowFont",
                           "WaveBar/Colours", "Spectrum/Colours"}) {
        settings.remove(QString::fromLatin1(key));
    }
}

// [Colors:<group>] <key> from a KDE colours file ("r,g,b").
static QColor kdeColour(QSettings& colours, const QString& group, const QString& key)
{
    const QStringList rgb = colours.value(u"Colors:"_s + group + u"/"_s + key).toStringList();
    if(rgb.size() < 3) {
        return {};
    }
    return {rgb.at(0).toInt(), rgb.at(1).toInt(), rgb.at(2).toInt()};
}

static void writeStyle(QSettings& settings, const QString& coloursFile)
{
    QSettings colours(coloursFile, QSettings::IniFormat);
    const auto get = [&colours](const char* group, const char* key) {
        return kdeColour(colours, QString::fromLatin1(group), QString::fromLatin1(key));
    };

    const QColor window = get("Window", "BackgroundNormal");
    const QColor base   = get("View", "BackgroundNormal");
    const QColor text   = get("View", "ForegroundNormal");
    const QColor accent = get("Selection", "BackgroundNormal");
    const QColor muted  = get("View", "ForegroundInactive");

    writePlasma(settings, accent.name());

    FyTheme theme;
    theme.name     = u"Plasma style"_s;
    const auto set = [&theme](QPalette::ColorRole role, const QColor& colour) {
        if(colour.isValid()) {
            theme.colours.insert(PaletteKey{.role = role}, colour);
        }
    };
    set(QPalette::Window, window);
    set(QPalette::WindowText, get("Window", "ForegroundNormal"));
    set(QPalette::Base, base);
    set(QPalette::AlternateBase, base.lighter(112));
    set(QPalette::Text, text);
    set(QPalette::Button, get("Button", "BackgroundNormal"));
    set(QPalette::ButtonText, get("Button", "ForegroundNormal"));
    // Selected rows: the full accent (Sweet's #8500f7) glares in the playlist, so blend 40% of it into the
    // list background. Text on it keeps the normal text colour, which reads better on the darker mix.
    const auto blend = [](const QColor& a, const QColor& b, double amountA) {
        return QColor::fromRgbF(static_cast<float>(a.redF() * amountA + b.redF() * (1 - amountA)),
                                static_cast<float>(a.greenF() * amountA + b.greenF() * (1 - amountA)),
                                static_cast<float>(a.blueF() * amountA + b.blueF() * (1 - amountA)));
    };
    set(QPalette::Highlight, accent.isValid() && base.isValid() ? blend(accent, base, 0.4) : accent);
    set(QPalette::HighlightedText, text);
    set(QPalette::ToolTipBase, get("Tooltip", "BackgroundNormal"));
    set(QPalette::ToolTipText, get("Tooltip", "ForegroundNormal"));
    set(QPalette::PlaceholderText, muted);
    set(QPalette::Link, get("View", "ForegroundLink"));
    set(QPalette::BrightText, accent);
    set(QPalette::Light, window.lighter(160));
    set(QPalette::Midlight, window.lighter(130));
    set(QPalette::Mid, window.darker(130));
    set(QPalette::Dark, window.darker(170));
    set(QPalette::Shadow, QColor{0, 0, 0});
    settings.setValue(u"Theme/CustomTheme"_s, QVariant::fromValue(theme));

    // Waveform seekbar: accent wave, lighter where already played.
    using WT = WaveBar::Colours::Type;
    WaveBar::Colours wave;
    const QColor played = accent.lighter(140), rms = accent.darker(150), rmsPlayed = accent.lighter(115);
    wave.waveColours = {
        {WT::BgUnplayed, window},           {WT::BgPlayed, window},
        {WT::MaxUnplayed, accent},          {WT::MinUnplayed, accent},
        {WT::MaxPlayed, played},            {WT::MinPlayed, played},
        {WT::RmsMaxUnplayed, rms},          {WT::RmsMinUnplayed, rms},
        {WT::RmsMaxPlayed, rmsPlayed},      {WT::RmsMinPlayed, rmsPlayed},
        {WT::MaxBorder, Qt::transparent},   {WT::MinBorder, Qt::transparent},
        {WT::RmsMaxBorder, Qt::transparent}, {WT::RmsMinBorder, Qt::transparent},
        {WT::Cursor, text},                 {WT::SeekingCursor, text},
        {WT::PlayedThreshold, muted},
    };
    settings.setValue(u"WaveBar/Colours"_s, QVariant::fromValue(wave));

    // Spectrum: accent bars on the window colour.
    using ST = Spectrum::Colours::Type;
    Spectrum::Colours spectrum;
    spectrum.setColour(ST::Background, window);
    spectrum.setColour(ST::BarGradient, accent.lighter(120));
    spectrum.setColour(ST::Peaks, text);
    spectrum.setColour(ST::Text, muted);
    spectrum.setColour(ST::HorizontalGrid, window.lighter(150));
    spectrum.setColour(ST::VerticalGrid, window.lighter(130));
    spectrum.setColour(ST::OctaveGrid, window.lighter(150));
    settings.setValue(u"Spectrum/Colours"_s, QVariant::fromValue(spectrum));
}

int main(int argc, char** argv)
{
    QApplication app(argc, argv);
    qRegisterMetaType<FyTheme>("FyTheme");
    qRegisterMetaType<WaveBar::Colours>("Fooyin::WaveBar::Colours");
    qRegisterMetaType<Spectrum::Colours>("Fooyin::Spectrum::Colours");

    const QStringList args = app.arguments();
    const bool plasma      = args.size() == 4 && args.at(2) == u"plasma"_s && QColor::fromString(args.at(3)).isValid();
    const bool style       = args.size() == 4 && args.at(2) == u"style"_s && QFile::exists(args.at(3));
    if(!plasma && !style && !(args.size() == 3 && args.at(2) == u"darkone"_s)) {
        std::fputs("usage: fyhelper <fooyin.conf> darkone | plasma <accent #rrggbb> | style <KDE colours file>\n",
                   stderr);
        return 2;
    }

    QSettings settings(args.at(1), QSettings::IniFormat);

    // Library order, as in foo_facets/SimPlaylist: album artist, date, album, disc, track.
    settings.setValue(u"Library/SortScript"_s,
                      AlbumArtist + u" - %date% - %album% - $num(%disc%,5) - $num(%track%,5) - %title%"_s);

    // Library filter column: top-level folder under the library root (Bought, Custom-DL, ...).
    settings.setValue(u"Filters/FilterColumns"_s, registryBlob(1, [](QDataStream& s) {
        writeFilterColumn(s, 5, 5, u"Folder"_s, u"$left(%relativepath%,$sub($strchr(%relativepath%,/),1))"_s);
    }));

    if(plasma) {
        writePlasma(settings, args.at(3));
    }
    else if(style) {
        writeStyle(settings, args.at(3));
    }
    else {
        writeDarkOne(settings);
    }

    settings.sync();
    return settings.status() == QSettings::NoError ? 0 : 1;
}
