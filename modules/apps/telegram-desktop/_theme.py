# Copyright (c) 2026 Bad3r
"""Build a Telegram Desktop .tdesktop-theme from the desktop palette.

Usage:
    python3 _theme.py COLORS_PALETTE NIGHT_THEME COLORS_JSON OUT

COLORS_PALETTE is Telegram/lib_ui/ui/colors.palette and NIGHT_THEME is
Telegram/Resources/night.tdesktop-theme from the same Telegram source.
COLORS_JSON holds base00..base0F plus the VS Code tokens named in TOKENS.
"""

import colorsys
import itertools
import json
import re
import struct
import sys
import zipfile
import zlib
from pathlib import Path

type Color = tuple[int, int, int, int]

TOKENS = ("accent", "link", "selection", "popup", "hover", "badge")
BASES = tuple(f"base0{digit}" for digit in "0123456789ABCDEF")
ARGC = 5
OPAQUE = 255
RGBA_DIGITS = 8

ENTRY = re.compile(r"([A-Za-z0-9_]+)\s*:\s*([^;]+);")
HEX = re.compile(r"#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?")
# Telegram's readNameAndValue: a name, ':', '#' plus name characters, ';'.
TELEGRAM_ENTRY = re.compile(r"\s*([A-Za-z0-9_]+)\s*:\s*(#[A-Za-z0-9_]+)\s*;")

# Telegram key -> palette name, '#rrggbb[aa]', or another Telegram key.
# A '/aa' suffix sets the alpha. Keys absent here take Telegram's night value,
# retoned onto the palette by retone().
MAP = {
    # basic
    "windowBg": "base01",
    "windowFg": "base05",
    "windowBgOver": "hover",
    "windowBgRipple": "#3a3b3c",
    "windowFgOver": "base06",
    "windowSubTextFg": "base04",
    "windowSubTextFgOver": "#9d9d9d",
    "windowBoldFg": "base06",
    "windowBoldFgOver": "base07",
    "windowBgActive": "accent",
    "windowFgActive": "#ffffff",
    "windowActiveTextFg": "link",
    "windowShadowFg": "#000000",
    "windowShadowFgFallback": "base00",
    "shadowFg": "#0000004d",
    # buttons
    "activeButtonBg": "accent",
    "activeButtonBgOver": "#42a0c9",
    "activeButtonBgRipple": "#4fabd3",
    "activeButtonFg": "#ffffff",
    "activeButtonFgOver": "#ffffff",
    "activeButtonSecondaryFg": "#cde6f1",
    "activeLineFg": "accent",
    "activeLineFgError": "base08",
    "lightButtonBg": "windowBg",
    "lightButtonBgOver": "hover",
    "lightButtonBgRipple": "#3a3b3c",
    "lightButtonFg": "link",
    "attentionButtonFg": "base08",
    "attentionButtonFgOver": "base0F",
    "attentionButtonBgOver": "base08/1f",
    "attentionButtonBgRipple": "base08/33",
    # menus and tooltips: VS Code quickInput surface
    "menuBg": "popup",
    "menuBgOver": "hover",
    "menuBgRipple": "#3a3b3c",
    "menuIconFg": "base04",
    "menuIconFgOver": "base06",
    "menuSubmenuArrowFg": "base04",
    "menuFgDisabled": "base03",
    "menuSeparatorFg": "base02",
    "tooltipBg": "popup",
    "tooltipFg": "base05",
    "tooltipBorderFg": "base02",
    "importantTooltipBg": "popup",
    "importantTooltipFg": "base05",
    "importantTooltipFgLink": "link",
    "toastBg": "popup/f2",
    "toastFg": "base06",
    # scrollbars: VS Code scrollbarSlider over the editor
    "scrollBarBg": "base04/59",
    "scrollBarBgOver": "base04/8c",
    "scrollBg": "#ffffff0d",
    "scrollBgOver": "#ffffff17",
    "historyScrollBarBg": "base04/59",
    "historyScrollBarBgOver": "base04/8c",
    "historyScrollBg": "#ffffff0d",
    "historyScrollBgOver": "#ffffff17",
    "smallCloseIconFg": "base03",
    "smallCloseIconFgOver": "base05",
    # inputs
    "placeholderFg": "base04",
    "placeholderFgActive": "base03",
    "inputBorderFg": "base02",
    "filterInputBorderFg": "accent",
    "filterInputActiveBg": "base00",
    "filterInputInactiveBg": "base00",
    "checkboxFg": "base03",
    "sliderBgInactive": "#3a3b3c",
    "sliderBgActive": "accent",
    "botKbBg": "base02",
    "botKbDownBg": "hover",
    # window title (custom title bar only)
    "titleBg": "base01",
    "titleBgActive": "base01",
    "titleButtonFg": "base04",
    "titleButtonBgOver": "hover",
    "titleButtonFgOver": "base06",
    "titleButtonBgActive": "base01",
    "titleButtonBgActiveOver": "hover",
    "titleButtonCloseBgOver": "#c42b1c",
    "titleButtonCloseBgActive": "base01",
    "titleButtonCloseBgActiveOver": "#c42b1c",
    "titleFg": "base04",
    "titleFgActive": "base05",
    "trayCounterBg": "badge",
    "trayCounterBgMute": "base03",
    # boxes share windowBg: box rows draw windowBg-keyed widgets
    "boxBg": "windowBg",
    "boxTextFg": "windowFg",
    "boxTextFgGood": "base0B",
    "boxTextFgError": "base08",
    "boxTitleFg": "base06",
    "boxSearchBg": "windowBg",
    "boxTitleAdditionalFg": "base04",
    "boxDividerBg": "base00",
    "cancelIconFg": "base04",
    "cancelIconFgOver": "base06",
    "membersAboutLimitFg": "base04",
    "contactsBg": "windowBg",
    "contactsBgOver": "hover",
    "contactsStatusFg": "base04",
    "contactsStatusFgOver": "base04",
    "contactsStatusFgOnline": "link",
    "callArrowFg": "base0B",
    "callArrowMissedFg": "base08",
    # intro (login) screens
    "introBg": "windowBg",
    "introTitleFg": "base07",
    "introDescriptionFg": "base04",
    "introCoverTopBg": "#1a3540",
    "introCoverBottomBg": "#245c73",
    "introCoverIconsFg": "selection",
    "introCoverPlaneTrace": "badge",
    "introCoverPlaneInner": "base06",
    "introCoverPlaneOuter": "base04",
    "introCoverPlaneTop": "#ffffff",
    # chat list: VS Code side bar
    "dialogsBg": "windowBg",
    "dialogsNameFg": "base06",
    "dialogsDateFg": "base04",
    "dialogsTextFg": "base04",
    "dialogsTextFgService": "link",
    "dialogsDraftFg": "base08",
    "dialogsVerifiedIconBg": "link",
    "dialogsVerifiedIconFg": "windowBg",
    "dialogsSendingIconFg": "base03",
    "dialogsSentIconFg": "link",
    "dialogsUnreadBg": "badge",
    "dialogsUnreadBgMuted": "base03",
    "dialogsUnreadFg": "#ffffff",
    "dialogsOnlineBadgeFg": "base0B",
    "dialogsBgOver": "hover",
    "dialogsDateFgOver": "base04",
    "dialogsTextFgOver": "#9d9d9d",
    "dialogsTextFgServiceOver": "link",
    "dialogsVerifiedIconBgOver": "link",
    "dialogsSentIconFgOver": "link",
    "dialogsUnreadBgOver": "badge",
    "dialogsUnreadBgMutedOver": "base03",
    "dialogsBgActive": "selection",
    "dialogsNameFgActive": "#ffffff",
    "dialogsDateFgActive": "#ffffffcc",
    "dialogsTextFgActive": "#ffffffeb",
    "dialogsDraftFgActive": "#ffd2ce",
    "dialogsSendingIconFgActive": "#ffffff99",
    "dialogsUnreadBgActive": "#ffffff",
    "dialogsUnreadBgMutedActive": "#9cc6d8",
    "dialogsUnreadFgActive": "selection",
    "dialogsOnlineBadgeFgActive": "#ffffff",
    "dialogsRippleBg": "#3a3b3c",
    "dialogsRippleBgActive": "#3189b0",
    "searchedBarBg": "popup",
    "searchedBarFg": "base04",
    "topBarBg": "windowBg",
    # folders strip: VS Code activity bar
    "sideBarBg": "base00",
    "sideBarBgActive": "hover",
    "sideBarBgRipple": "base02",
    "sideBarTextFg": "base04",
    "sideBarTextFgActive": "base07",
    "sideBarIconFg": "base04",
    "sideBarIconFgActive": "base07",
    "sideBarBadgeBg": "badge",
    "sideBarBadgeBgMuted": "base03",
    # emoji panel
    "emojiPanBg": "windowBg",
    "emojiPanCategories": "windowBg",
    "emojiPanHeaderFg": "base04",
    "emojiPanHeaderBg": "base01/f2",
    "emojiIconFg": "base04",
    "emojiSubIconFgActive": "base06",
    # messages: incoming on the quickInput surface, outgoing on a dark accent
    # tint, both over the base00 editor background
    "historyTextInFg": "base06",
    "historyTextInFgSelected": "base07",
    "historyTextOutFg": "base06",
    "historyTextOutFgSelected": "base07",
    "historyLinkInFg": "link",
    "historyLinkInFgSelected": "base0D",
    "historyLinkOutFg": "base0D",
    "historyLinkOutFgSelected": "#a5d6ff",
    "historyOutIconFg": "base0D",
    "historyOutIconFgSelected": "#a5d6ff",
    "historySendingOutIconFg": "#7fa8b9",
    "historySendingInIconFg": "base03",
    "historyCallArrowInFg": "base0B",
    "historyCallArrowOutFg": "base0B",
    "historyUnreadBarBg": "base01",
    "historyUnreadBarBorder": "base02",
    "historyUnreadBarFg": "base05",
    "msgInBg": "popup",
    "msgInBgSelected": "#23404d",
    "msgOutBg": "#1a3540",
    "msgOutBgSelected": "#245c73",
    "msgSelectOverlay": "selection/4c",
    "msgStickerOverlay": "selection/7f",
    "msgInServiceFg": "link",
    "msgInServiceFgSelected": "base0D",
    "msgOutServiceFg": "base0D",
    "msgOutServiceFgSelected": "#a5d6ff",
    "msgInDateFg": "base04",
    "msgInDateFgSelected": "base05",
    "msgOutDateFg": "#7fa8b9",
    "msgOutDateFgSelected": "#a9c9d6",
    "msgServiceFg": "base06",
    "msgServiceBg": "popup/d9",
    "msgServiceBgSelected": "selection",
    "msgInReplyBarColor": "accent",
    "msgInReplyBarSelColor": "base0D",
    "msgOutReplyBarColor": "base0D",
    "msgOutReplyBarSelColor": "#a5d6ff",
    "msgInMonoFg": "base09",
    "msgOutMonoFg": "base09",
    "msgInMonoFgSelected": "#ffc28a",
    "msgOutMonoFgSelected": "#ffc28a",
    "msgDateImgBgSelected": "selection/87",
    "msgFileThumbLinkInFg": "link",
    "msgFileThumbLinkOutFg": "base0D",
    "msgFileInBg": "accent",
    "msgFileInBgOver": "#42a0c9",
    "msgFileInBgSelected": "link",
    "msgFileOutBg": "accent",
    "msgFileOutBgSelected": "link",
    "msgFile1Bg": "#1f6feb",
    "msgFile1BgDark": "#1158c7",
    "msgFile1BgOver": "#388bfd",
    "msgFile2Bg": "#238636",
    "msgFile2BgDark": "#196c2e",
    "msgFile2BgOver": "#2ea043",
    "msgFile2BgSelected": "#2ea043",
    "msgFile3Bg": "#da3633",
    "msgFile3BgDark": "#b62324",
    "msgFile3BgOver": "#f85149",
    "msgFile3BgSelected": "#f85149",
    "msgFile4Bg": "#9e6a03",
    "msgFile4BgDark": "#845306",
    "msgFile4BgOver": "#bb8009",
    "msgFile4BgSelected": "#bb8009",
    "msgWaveformInActive": "accent",
    "msgWaveformInActiveSelected": "base0D",
    "msgWaveformInInactive": "#4a4b4c",
    "msgWaveformInInactiveSelected": "#3d6575",
    "msgWaveformOutActive": "base0D",
    "msgWaveformOutActiveSelected": "#a5d6ff",
    "msgWaveformOutInactive": "#2f5666",
    "msgWaveformOutInactiveSelected": "#4a7b8e",
    "historyToDownBg": "popup",
    "historyToDownBgOver": "hover",
    "historyToDownBgRipple": "#3a3b3c",
    "historyToDownFg": "base05",
    "historyComposeAreaBg": "windowBg",
    "historyComposeIconFg": "base04",
    "historyComposeIconFgOver": "base06",
    "historySendIconFg": "accent",
    "historySendIconFgOver": "link",
    "historyPinnedBg": "windowBg",
    "historyComposeButtonBgOver": "hover",
    "historyComposeButtonBgRipple": "#3a3b3c",
    "overviewPhotoSelectOverlay": "selection/33",
    "profileStatusFgOver": "base04",
    "profileAdminStartFg": "link",
    "notificationSampleCloseFg": "base04",
    "notificationSampleTextFg": "base05",
    "notificationSampleNameFg": "base06",
    "mainMenuBg": "windowBg",
    "mainMenuCoverBg": "base00",
    "mainMenuCloudBg": "selection",
    "mediaPlayerDisabledFg": "base03",
    "mediaviewTextLinkFg": "link",
    # peer colors: GitHub syntax hues for names, Primer emphasis fills for
    # userpics so white initials stay readable
    "historyPeer1NameFg": "base08",
    "historyPeer1UserpicBg": "#da3633",
    "historyPeer1UserpicBg2": "#b62324",
    "historyPeer2NameFg": "base0B",
    "historyPeer2UserpicBg": "#238636",
    "historyPeer2UserpicBg2": "#196c2e",
    "historyPeer3NameFg": "base0A",
    "historyPeer3UserpicBg": "#9e6a03",
    "historyPeer3UserpicBg2": "#845306",
    "historyPeer4NameFg": "base0D",
    "historyPeer4UserpicBg": "#1f6feb",
    "historyPeer4UserpicBg2": "#1158c7",
    "historyPeer5NameFg": "base0E",
    "historyPeer5UserpicBg": "#8957e5",
    "historyPeer5UserpicBg2": "#6e40c9",
    "historyPeer6NameFg": "base0F",
    "historyPeer6UserpicBg": "#bf4b8a",
    "historyPeer6UserpicBg2": "#99286e",
    "historyPeer7NameFg": "base0C",
    "historyPeer7UserpicBg": "#1b7c83",
    "historyPeer7UserpicBg2": "#136061",
    "historyPeer8NameFg": "base09",
    "historyPeer8UserpicBg": "#bd561d",
    "historyPeer8UserpicBg2": "#9b4215",
    "settingsIconBg1": "#da3633",
    "settingsIconBg2": "#238636",
    "settingsIconBg3": "#9e6a03",
    "settingsIconBg4": "#1f6feb",
    "settingsIconBg5": "#1158c7",
    "settingsIconBg6": "#8957e5",
    "settingsIconBg8": "#bd561d",
    "settingsIconBgArchive": "base03",
    # calls
    "callAnswerBg": "#238636",
    "callAnswerRipple": "#2ea043",
    "callAnswerBgOuter": "#2ea04326",
    "callHangupBg": "#da3633",
    "callHangupRipple": "#f85149",
    "callBarBg": "#245c73",
    "callBarMuteRipple": "selection",
    "callBarBgMuted": "base02",
    "groupCallActiveFg": "link",
}

# Night blue-grey lightness -> palette lightness, anchored on night's
# sideBarBg, windowBg and windowBgOver.
NEUTRAL_L = ((0.0, 0.0), (0.093, 0.075), (0.13, 0.10), (0.19, 0.19), (1.0, 1.0))
# Night's blue family, by HLS hue in degrees.
BLUE_HUES = (185, 240)
# HLS chroma below which a color is grey, and below which a blue is a blue-grey.
GREY_CHROMA = 0.02
BLUE_GREY_CHROMA = 0.2
MAX_ACCENT_SATURATION = 0.6

# Text and fills whose WCAG contrast the build log reports.
CONTRAST_PAIRS = (
    ("windowFg", "windowBg"),
    ("windowSubTextFg", "windowBg"),
    ("windowActiveTextFg", "windowBg"),
    ("activeButtonFg", "activeButtonBg"),
    ("dialogsNameFg", "dialogsBg"),
    ("dialogsNameFgActive", "dialogsBgActive"),
    ("dialogsTextFgActive", "dialogsBgActive"),
    ("dialogsUnreadFg", "dialogsUnreadBg"),
    ("windowFg", "menuBg"),
    ("historyTextInFg", "msgInBg"),
    ("historyTextOutFg", "msgOutBg"),
    ("historyLinkInFg", "msgInBg"),
    ("historyLinkOutFg", "msgOutBg"),
    ("msgInDateFg", "msgInBg"),
    ("msgOutDateFg", "msgOutBg"),
    ("historyTextOutFgSelected", "msgOutBgSelected"),
    ("historyPeerUserpicFg", "historyPeer3UserpicBg"),
)


class ThemeError(Exception):
    """Input the generator cannot turn into a valid theme."""


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    return re.sub(r"//[^\n]*", " ", text)


def entries(text: str) -> list[tuple[str, str]]:
    return [(key, value.strip()) for key, value in ENTRY.findall(strip_comments(text))]


def rgba(value: str) -> Color:
    digits = value.lower().lstrip("#")
    alpha = int(digits[6:8], 16) if len(digits) == RGBA_DIGITS else OPAQUE
    return int(digits[0:2], 16), int(digits[2:4], 16), int(digits[4:6], 16), alpha


def fmt(color: Color) -> str:
    r, g, b, a = color
    return f"#{r:02x}{g:02x}{b:02x}" + ("" if a == OPAQUE else f"{a:02x}")


def interpolate(x: float, points: tuple[tuple[float, float], ...]) -> float:
    for (x0, y0), (x1, y1) in itertools.pairwise(points):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return points[-1][1]


def retone(color: Color, accent_hue: float) -> Color:
    """Move night's blue-greys to neutral greys and its blues to the accent hue."""
    r, g, b, a = color
    hue, light, saturation = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    chroma = saturation * (1 - abs(2 * light - 1))
    if chroma < GREY_CHROMA or not BLUE_HUES[0] <= hue * 360 <= BLUE_HUES[1]:
        return color
    if chroma < BLUE_GREY_CHROMA:
        grey = round(interpolate(light, NEUTRAL_L) * 255)
        return grey, grey, grey, a
    nr, ng, nb = colorsys.hls_to_rgb(accent_hue, light, min(saturation, MAX_ACCENT_SATURATION))
    return round(nr * 255), round(ng * 255), round(nb * 255), a


def luminance(color: Color) -> float:
    def channel(value: int) -> float:
        v = value / 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4  # noqa: PLR2004

    r, g, b, _ = color
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(fg: Color, bg: Color) -> float:
    alpha = fg[3] / 255
    r, g, b = (round(fg[i] * alpha + bg[i] * (1 - alpha)) for i in range(3))
    hi, lo = sorted((luminance((r, g, b, OPAQUE)), luminance(bg)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def png_1x1(color: Color) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    pixels = zlib.compress(bytes([0, *color[:3]]))
    return (
        b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", pixels) + chunk(b"IEND", b"")
    )


class Resolver:
    """Resolve every Telegram key to a literal color, following references."""

    def __init__(self, palette: str, night: str, named: dict[str, Color]) -> None:
        self.defaults = dict(entries(palette))
        self.night = dict(entries(night))
        self.named = named
        accent = named["accent"]
        self.accent_hue = colorsys.rgb_to_hls(*(c / 255 for c in accent[:3]))[0]
        self.colors: dict[str, Color] = {}
        self.sources: dict[str, str] = {}
        self.stack: list[str] = []

    def value(self, spec: str, origin: str) -> Color:
        name, _, alpha = spec.partition("/")
        if HEX.fullmatch(name):
            color = rgba(name)
        elif name in self.named:
            color = self.named[name]
        elif name in self.defaults:
            color = self.resolve(name)
        else:
            msg = f"{origin}: unknown color {spec!r}"
            raise ThemeError(msg)
        return (*color[:3], int(alpha, 16)) if alpha else color

    def lookup(self, key: str) -> tuple[Color, str]:
        if key in MAP:
            return self.value(MAP[key], key), MAP[key]
        if key in self.night:
            spec = self.night[key]
            if HEX.fullmatch(spec):
                return retone(rgba(spec), self.accent_hue), "night"
            return self.resolve(spec), spec
        literal, _, fallback = (part.strip() for part in self.defaults[key].partition("|"))
        reference = fallback or (None if HEX.fullmatch(literal) else literal)
        if reference:
            return self.resolve(reference), reference
        return rgba(literal), "default"

    def resolve(self, key: str) -> Color:
        if key in self.colors:
            return self.colors[key]
        if key in self.stack:
            msg = f"reference cycle: {' -> '.join([*self.stack, key])}"
            raise ThemeError(msg)
        self.stack.append(key)
        self.colors[key], self.sources[key] = self.lookup(key)
        self.stack.pop()
        return self.colors[key]


def build(palette: str, night: str, named: dict[str, Color]) -> tuple[str, Resolver]:
    resolver = Resolver(palette, night, named)
    unknown = sorted(key for key in MAP if key not in resolver.defaults)
    if unknown:
        msg = f"MAP keys unknown to Telegram: {unknown}"
        raise ThemeError(msg)
    order = list(resolver.defaults)
    lines = [
        "// VS Code Dark 2026 over GitHub Dark accents, generated from the Stylix palette.",
        f"// {len(order)} keys, each a literal so new Telegram defaults cannot shift them.",
        "",
    ]
    lines += [f"{key}: {fmt(resolver.resolve(key))}; // {resolver.sources[key]}" for key in order]
    return "\n".join(lines) + "\n", resolver


def check(text: str, order: list[str]) -> None:
    """Re-read the output under Telegram's ReadPaletteValues rules."""
    body = strip_comments(text)
    pos = 0
    seen: list[str] = []
    while body[pos:].strip():
        match = TELEGRAM_ENTRY.match(body, pos)
        if not match:
            msg = f"unparsable at offset {pos}: {body[pos : pos + 40]!r}"
            raise ThemeError(msg)
        if not HEX.fullmatch(match.group(2)):
            msg = f"{match.group(1)}: not #rrggbb[aa]: {match.group(2)}"
            raise ThemeError(msg)
        seen.append(match.group(1))
        pos = match.end()
    if seen != order:
        msg = "output keys differ from colors.palette"
        raise ThemeError(msg)


def main() -> None:
    if len(sys.argv) != ARGC:
        raise SystemExit(__doc__)
    palette_path, night_path, colors_path, out = (Path(arg) for arg in sys.argv[1:])
    with zipfile.ZipFile(night_path) as archive:
        night = archive.read("colors.tdesktop-theme").decode()
    palette = palette_path.read_text(encoding="utf-8")
    colors: dict[str, str] = json.loads(colors_path.read_text(encoding="utf-8"))
    missing = [name for name in (*BASES, *TOKENS) if name not in colors]
    if missing:
        msg = f"{colors_path}: missing {missing}"
        raise ThemeError(msg)

    text, resolver = build(palette, night, {k: rgba(v) for k, v in colors.items()})
    check(text, list(resolver.defaults))
    for fg, bg in CONTRAST_PAIRS:
        ratio = contrast(resolver.colors[fg], resolver.colors[bg])
        print(f"{ratio:5.2f}  {fg} on {bg}", file=sys.stderr)

    # Fixed timestamps keep the archive reproducible.
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in (
            ("colors.tdesktop-theme", text.encode()),
            ("background.png", png_1x1(rgba(colors["base00"]))),
        ):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, data)


if __name__ == "__main__":
    main()
