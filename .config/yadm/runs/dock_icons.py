#!/usr/bin/env python3
"""Приводит иконки дока GNOME к одинаковой видимой высоте.

Дэш вписывает файл иконки в бокс целиком, а прозрачные поля внутри файла у
приложений разные: Edge занимает всю канву, Sioyek — 62 % её по высоте (арт ещё
и широкий, поэтому вписывается по ширине). Скрипт обрезает прозрачные поля,
масштабирует арт до FILL от канвы 512×512, центрирует и складывает результат в
набор иконок dash-aligned, который всё остальное наследует у текущей темы
(Inherits=). Иконкам, подключённым в .desktop абсолютным путём — таких в теме
нет — путь переписывается на сгенерированный файл.

Запускается из runs/z_gnome, вручную — без аргументов. Код возврата 1 означает,
что набор иконок не собран и переключать тему не надо. Файл не исполняемый
намеренно: run_runner.sh собирает ранеры через find -executable.
"""

from __future__ import annotations

import ast
import functools
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import TYPE_CHECKING

# PyGObject — C-расширение из системного пакета python3-gi: в venv он не виден.
# z_gnome этот случай ловит сам, ручной запуск получает внятное сообщение.
try:
    import gi  # pyright: ignore[reportMissingTypeStubs] — стабов в Debian нет

    gi.require_version("GdkPixbuf", "2.0")
    # gi.repository собирается в рантайме: require_version выше требует импорт не в
    # начале файла (E402), а стабы о его символах не знают.
    from gi.repository import GLib, GdkPixbuf  # noqa: E402  # pyright: ignore[reportAttributeAccessIssue, reportMissingTypeStubs]
except (ImportError, ValueError) as gi_error:
    print(
        f"[ERROR] Нужен PyGObject из системы: python3-gi + gir1.2-gdkpixbuf-2.0 ({gi_error})",
        file=sys.stderr,
    )
    sys.exit(1)

try:
    import numpy as np
except ImportError:  # без numpy работает, просто медленнее на больших png
    np = None

# Аннотации выше — строки (from __future__ import annotations), поэтому без Pillow
# модуль импортируется: ветка else нужна только ради runtime-имён.
if TYPE_CHECKING:
    from PIL import Image, ImageDraw, ImageFont
else:
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:  # без Pillow иконки выравниваются, но без меток хоткеев
        Image = ImageDraw = ImageFont = None

# Канва и доля арта в ней. 512 — с запасом на масштаб 2x (дэш рисует ~96 логических px).
CANVAS = 512
# Порог альфы: на 4/16/48/96 доля закрашенной области меняется на десятые доли,
# поэтому мягкие тени бокс не раздувают.
ALPHA_THRESHOLD = 16
THEME_NAME = "dash-aligned"
THEME_SIZE_DIR = "512x512"
ICON_EXTENSIONS = (".svg", ".png", ".xpm")
# Иконки, которые в ряду не читаются: у Sioyek арт — раскрытая книга 1.53:1,
# в квадратном боксе она всегда ниже соседей. Таким приложениям берётся иконка
# формата из темы (PDF так, как его рисует Breeze; в Adwaita application-pdf
# нет, а x-office-document — обычный лист без метки формата).
ICON_OVERRIDES = {
    "sioyek.desktop": "application-pdf",
}

# Метка хоткея в правом верхнем углу. Хоткеи живут в shortcuts.conf run-or-raise
# (Win+1 … Win+0, Win+-, Win+=) и привязываются к приложениям по wm_class/Exec,
# поэтому сопоставление идёт токенами, а не по порядку в favorite-apps.
SHORTCUTS_CONF = Path.home() / ".config/run-or-raise/shortcuts.conf"
BADGE_FONTS = (
    "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/cantarell/Cantarell-Bold.otf",
)
BADGE_SIZE = 0.26  # кегль относительно канвы
BADGE_MARGIN = 0.045  # отступ от верхнего правого угла
BADGE_STROKE = 0.016  # тёмная обводка: иначе белая цифра пропадает на светлой иконке
# Обёртки запуска и подстановки не говорят о приложении ничего.
LAUNCHER_COMMANDS = {"env", "sh", "bash", "setsid", "gtk-launch", "flatpak", "snap", "run"}
KEY_LABELS = {
    "minus": "-",
    "equal": "=",
    "plus": "+",
    "space": "␣",
    "Return": "⏎",
    "Escape": "Esc",
    "comma": ",",
    "period": ".",
    "slash": "/",
    "backslash": "\\",
    "grave": "`",
    "apostrophe": "'",
    "semicolon": ";",
    "bracketleft": "[",
    "bracketright": "]",
}


@functools.lru_cache(maxsize=1)
def fill_ratio() -> float:
    """Доля канвы под арт; DOCK_ICON_FILL позволяет уменьшить иконки разом."""
    raw = os.environ.get("DOCK_ICON_FILL") or "1.0"
    try:
        value = float(raw)
    except ValueError:
        warn(f"DOCK_ICON_FILL={raw!r} не число — беру 1.0")
        return 1.0
    if not 0.5 <= value <= 1.0:
        # Меньше половины канвы арт теряет смысл, больше — это уже 1.0.
        warn(f"DOCK_ICON_FILL={value} вне 0.5..1.0 — ограничиваю")
    return min(max(value, 0.5), 1.0)


def warn(message: str) -> None:
    print(f"[WARN] {message}", file=sys.stderr)


def data_home() -> Path:
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")


def data_dirs() -> list[Path]:
    """XDG_DATA_DIRS плюс экспорты flatpak: их иконки тоже видны дэшу."""
    raw = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    dirs = [Path(item) for item in raw.split(":") if item]
    dirs += [Path("/var/lib/flatpak/exports/share"), data_home() / "flatpak/exports/share"]
    return dirs


def icon_roots() -> list[Path]:
    roots = [Path.home() / ".icons", data_home() / "icons"]
    roots += [directory / "icons" for directory in data_dirs()]
    return roots


def application_dirs() -> list[Path]:
    dirs = [data_home() / "applications"] + [d / "applications" for d in data_dirs()]
    return dirs


def read_favorites() -> list[str]:
    """Список закреплённых .desktop id из gsettings."""
    result = subprocess.run(
        ["gsettings", "get", "org.gnome.shell", "favorite-apps"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        warn(f"gsettings: {result.stderr.strip()}")
        return []

    raw = result.stdout.strip()
    if not raw or raw in ("@as []", "[]"):
        return []
    try:
        return [str(item) for item in ast.literal_eval(raw)]
    except (ValueError, SyntaxError):
        warn(f"не разобрал favorite-apps: {raw}")
        return []


def desktop_file(desktop_id: str) -> Path | None:
    for directory in application_dirs():
        candidate = directory / desktop_id
        if candidate.is_file():
            return candidate
    return None


def entry_values(desktop: Path) -> dict[str, str]:
    """Пары ключ=значение из группы [Desktop Entry], по первому вхождению."""
    values: dict[str, str] = {}
    group = None
    for line in desktop.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            group = stripped
            continue
        if group != "[Desktop Entry]" or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        values.setdefault(key, value)
    return values


def icon_value(desktop: Path) -> str | None:
    return entry_values(desktop).get("Icon") or None


def command_tokens(command: str) -> list[str]:
    """Имена из команды запуска: флаги, переменные и подстановки (%U) — мимо."""
    tokens = []
    for word in command.split():
        if not word or word.startswith("-") or "=" in word:
            continue
        name = Path(word.split("%", 1)[0]).name.lower()
        if not name or name in LAUNCHER_COMMANDS:
            continue
        tokens.append(name)
    return tokens


def wm_class_token(raw: str) -> str:
    r"""wm_class из conf — это regex: /^com\.mitchellh\.ghostty$/ → имя класса."""
    value = raw.strip()
    if len(value) > 2 and value.startswith("/") and value.endswith("/"):
        value = value[1:-1]
    return value.replace("^", "").replace("$", "").replace("\\", "").strip().lower()


def shortcut_label(shortcut: str) -> str:
    """Клавиша из «<Super>minus:режим» → короткая метка для значка."""
    key = re.sub(r"<[^>]+>", "", shortcut.split(":", 1)[0]).strip()
    if not key:
        return ""
    return KEY_LABELS.get(key, key.upper() if key.isalpha() else key)


def read_shortcut_entries() -> list[tuple[str, set[str]]]:
    """Строки shortcuts.conf как (метка, токены приложения)."""
    path = SHORTCUTS_CONF
    if not path.is_file():
        return []

    entries: list[tuple[str, set[str]]] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        fields = [field.strip() for field in line.split(",")]
        if len(fields) < 2:
            continue
        label = shortcut_label(fields[0])
        tokens = set(command_tokens(fields[1]))
        tokens |= {wm_class_token(field) for field in fields[2:] if field}
        tokens.discard("")
        if label and tokens:
            entries.append((label, tokens))
    return entries


def desktop_tokens(desktop_id: str, desktop: Path) -> set[str]:
    """Чем приложение может опознаться в shortcuts.conf."""
    values = entry_values(desktop)
    tokens = {desktop_id.removesuffix(".desktop").lower()}
    wm_class = values.get("StartupWMClass")
    if wm_class:
        tokens.add(wm_class.lower())
    tokens |= set(command_tokens(values.get("Exec", "")))
    return {token for token in tokens if token}


def shortcut_labels(favorites: list[str]) -> dict[str, str]:
    """desktop id → метка хоткея (Win+1 → «1»).

    Общее имя (`ghostty`) есть и у обычного окна, и внутри `gtk-launch
    com.mitchellh.ghostty.wiki`, поэтому побеждает самое длинное совпадение.
    """
    entries = read_shortcut_entries()
    if not entries:
        return {}

    labels: dict[str, str] = {}
    for desktop_id in favorites:
        desktop = desktop_file(desktop_id)
        if desktop is None:
            continue
        tokens = desktop_tokens(desktop_id, desktop)
        best_label, best_length = "", 0
        for label, entry_tokens in entries:
            common = tokens & entry_tokens
            if not common:
                continue
            length = max(len(token) for token in common)
            if length > best_length:
                best_label, best_length = label, length
        if best_label:
            labels[desktop_id] = best_label
    return labels


@functools.lru_cache(maxsize=1)
def badges_enabled() -> bool:
    if (os.environ.get("DOCK_ICON_BADGE") or "1") == "0":
        return False
    if Image is None:
        warn("Pillow не установлен — рисую иконки без меток хоткеев")
        return False
    if not any(Path(candidate).is_file() for candidate in BADGE_FONTS):
        warn("нет жирного ttf для меток — рисую иконки без них")
        return False
    return True


@functools.lru_cache(maxsize=1)
def badge_font() -> ImageFont.FreeTypeFont:
    for candidate in BADGE_FONTS:
        if Path(candidate).is_file():
            return ImageFont.truetype(candidate, int(CANVAS * BADGE_SIZE))
    raise OSError("нет шрифта для метки хоткея")


def pixbuf_to_image(pixbuf: GdkPixbuf.Pixbuf) -> Image.Image:
    return Image.frombuffer(
        "RGBA",
        (pixbuf.get_width(), pixbuf.get_height()),
        bytes(pixbuf.get_pixels()),
        "raw",
        "RGBA",
        pixbuf.get_rowstride(),
        1,
    )


def image_to_pixbuf(image: Image.Image) -> GdkPixbuf.Pixbuf:
    return GdkPixbuf.Pixbuf.new_from_bytes(
        GLib.Bytes.new(image.tobytes()),
        GdkPixbuf.Colorspace.RGB,
        True,
        8,
        image.width,
        image.height,
        image.width * 4,
    )


def draw_badge(pixbuf: GdkPixbuf.Pixbuf, label: str) -> GdkPixbuf.Pixbuf:
    """Белая метка с тёмной обводкой в правом верхнем углу канвы."""
    image = pixbuf_to_image(pixbuf)
    draw = ImageDraw.Draw(image)
    font = badge_font()
    stroke = max(2, round(CANVAS * BADGE_STROKE))
    left, top, right, _bottom = draw.textbbox(
        (0, 0), label, font=font, stroke_width=stroke
    )
    margin = round(CANVAS * BADGE_MARGIN)
    draw.text(
        (CANVAS - margin - (right - left) - left, margin - top),
        label,
        font=font,
        fill=(255, 255, 255, 255),
        stroke_width=stroke,
        stroke_fill=(0, 0, 0, 255),
    )
    return image_to_pixbuf(image)


def entry_icon_position(desktop: Path) -> int | None:
    """Номер строки Icon= в группе [Desktop Entry].

    Icon= бывает и в группах действий ([Desktop Action ...]) — иконка самого
    приложения берётся только из основной группы.
    """
    group = None
    lines = desktop.read_text(encoding="utf-8", errors="replace").splitlines()
    for position, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            group = stripped
            continue
        if group == "[Desktop Entry]" and stripped.startswith("Icon="):
            return position
    return None


def index_icon_files(names: set[str]) -> dict[str, list[Path]]:
    """Ищет файлы иконок с нужными именами: один обход корней вместо glob на имя.

    Собственный набор пропускается: иначе после первого прогона источником
    становится уже сгенерированный файл и исходная иконка больше не читается.
    """
    index: dict[str, list[Path]] = {}
    generated = theme_dir()
    for root in icon_roots():
        if not root.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            current = Path(dirpath)
            if current == generated:
                dirnames[:] = []
                continue
            for filename in filenames:
                path = Path(filename)
                if path.suffix not in ICON_EXTENSIONS:
                    continue
                if path.stem in names:
                    index.setdefault(path.stem, []).append(current / filename)
    return index


def pick_icon(candidates: list[Path], theme: str) -> Path:
    """Тема побеждает hicolor, svg побеждает png, крупный — мелкий."""

    def score(path: Path) -> tuple[int, int, int, int]:
        parts = path.parts
        themed = int(theme in parts)
        ext = int(path.suffix == ".svg")
        scalable = int("scalable" in parts)
        size = 0
        for part in parts:
            width, _, height = part.partition("x")
            if width.isdigit() and height.isdigit() and width == height:
                size = max(size, int(width))
            elif part.isdigit():
                # Breeze раскладывает по 16/22/64 без второй половины.
                size = max(size, int(part))
        return (themed, ext, scalable, size)

    return max(candidates, key=score)


def load_pixbuf(path: Path) -> GdkPixbuf.Pixbuf:
    """Читает иконку; svg растеризуется сразу в 1024, чтобы не терять резкость."""
    if path.suffix == ".svg":
        pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
            str(path), CANVAS * 2, CANVAS * 2, True
        )
    else:
        pixbuf = GdkPixbuf.Pixbuf.new_from_file(str(path))
    if pixbuf.get_n_channels() != 4:
        pixbuf = pixbuf.add_alpha(False, 0, 0, 0)
    return pixbuf


def alpha_bbox(pixbuf: GdkPixbuf.Pixbuf) -> tuple[int, int, int, int] | None:
    """Границы непрозрачной области как (left, top, right, bottom) включительно."""
    width, height = pixbuf.get_width(), pixbuf.get_height()
    channels = pixbuf.get_n_channels()
    stride = pixbuf.get_rowstride()
    # bytes(): старые PyGObject отдавали здесь list[int], а np.frombuffer работает
    # только с объектом, поддерживающим buffer-протокол.
    data = bytes(pixbuf.get_pixels())

    if np is not None:
        alpha = np.frombuffer(data, dtype=np.uint8).reshape(height, stride)
        alpha = alpha[:, : width * channels].reshape(height, width, channels)[:, :, 3]
        rows, cols = np.nonzero(alpha > ALPHA_THRESHOLD)
        if rows.size == 0:
            return None
        return int(cols.min()), int(rows.min()), int(cols.max()), int(rows.max())

    # Резерв без numpy: сначала строки (срез байтов шагом channels — C-скорость),
    # потом столбцы только в найденных строках, с ранним выходом.
    left, right, top, bottom = width, -1, height, -1
    for y in range(height):
        start = y * stride
        row = data[start + 3 : start + width * channels : channels]
        if max(row) <= ALPHA_THRESHOLD:
            continue
        top = min(top, y)
        bottom = max(bottom, y)
        for x in range(width):
            if row[x] > ALPHA_THRESHOLD:
                left = min(left, x)
                break
        for x in range(width - 1, -1, -1):
            if row[x] > ALPHA_THRESHOLD:
                right = max(right, x)
                break
    if bottom < 0:
        return None
    return left, top, right, bottom


def render(pixbuf: GdkPixbuf.Pixbuf) -> tuple[GdkPixbuf.Pixbuf, float, float]:
    """Обрезает поля и вписывает арт в канву.

    Возвращает канву, долю высоты в исходном файле и долю высоты в результате:
    у арта шире, чем выше, высоту ограничивает ширина канвы.
    """
    box = alpha_bbox(pixbuf)
    if box is None:
        raise ValueError("иконка полностью прозрачная")
    left, top, right, bottom = box
    content = pixbuf.new_subpixbuf(left, top, right - left + 1, bottom - top + 1)

    scale = CANVAS * fill_ratio() / content.get_height()
    # Широкий арт (Sioyek) не вылезает за канву: тогда высота меньше остальных,
    # но это единственный вариант без обрезки картинки.
    if content.get_width() * scale > CANVAS:
        scale = CANVAS / content.get_width()

    scaled = content.scale_simple(
        max(1, round(content.get_width() * scale)),
        max(1, round(content.get_height() * scale)),
        GdkPixbuf.InterpType.BILINEAR,
    )

    canvas = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, CANVAS, CANVAS)
    canvas.fill(0x00000000)
    offset_x = (CANVAS - scaled.get_width()) // 2
    offset_y = (CANVAS - scaled.get_height()) // 2
    scaled.composite(
        canvas,
        offset_x,
        offset_y,
        scaled.get_width(),
        scaled.get_height(),
        offset_x,
        offset_y,
        1.0,
        1.0,
        GdkPixbuf.InterpType.BILINEAR,
        255,
    )

    return (
        canvas,
        content.get_height() / pixbuf.get_height(),
        scaled.get_height() / CANVAS,
    )


def save_png(pixbuf: GdkPixbuf.Pixbuf, destination: Path) -> bool:
    """Пишет png только если картинка изменилась — не трогаем mtime зря."""
    ok, buffer = pixbuf.save_to_bufferv("png", [], [])
    if not ok:
        raise OSError(f"не смог закодировать png для {destination}")
    payload = bytes(buffer)
    if destination.is_file() and destination.read_bytes() == payload:
        return False
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)
    return True


def current_theme() -> str:
    result = subprocess.run(
        ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"],
        capture_output=True,
        text=True,
    )
    theme = result.stdout.strip().strip("'")
    return theme or "Adwaita"


def theme_dir() -> Path:
    return data_home() / "icons" / THEME_NAME


def parent_theme() -> str:
    """Что наследует dash-aligned: текущая тема, а если она уже наша — прежнее значение."""
    theme = current_theme()
    if theme != THEME_NAME:
        return theme
    index = theme_dir() / "index.theme"
    if index.is_file():
        for line in index.read_text(encoding="utf-8").splitlines():
            if line.startswith("Inherits="):
                value = line.split("=", 1)[1].strip()
                if value and value != THEME_NAME:
                    return value
    return "Adwaita"


def sources_file() -> Path:
    return theme_dir() / "sources.json"


def load_sources() -> dict[str, str]:
    """Карта «сгенерированный файл → исходная иконка» для путей в Icon=."""
    path = sources_file()
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        warn(f"{path}: {error} — беру пустую карту источников")
        return {}
    if not isinstance(data, dict):
        return {}
    return {str(name): str(value) for name, value in data.items()}


def save_sources(sources: dict[str, str]) -> None:
    path = sources_file()
    payload = json.dumps(sources, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if path.is_file() and path.read_text(encoding="utf-8") == payload:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(payload, encoding="utf-8")


def original_source(sources: dict[str, str], destination: Path, current: Path) -> Path | None:
    """Исходник иконки, подключённой через абсолютный путь.

    После первого прогона Icon= указывает в сам набор, поэтому настоящий путь
    берётся из sources.json: иначе иконка каждый раз пересчитывалась бы из
    собственного результата и теряла бы качество при смене DOCK_ICON_FILL.
    """
    recorded = sources.get(destination.name)
    if recorded:
        path = Path(recorded)
        if path.is_file() and theme_dir() not in path.parents:
            return path
    if current.is_file() and theme_dir() not in current.parents:
        return current
    return None


def ensure_index_theme() -> None:
    index = theme_dir() / "index.theme"
    content = (
        "[Icon Theme]\n"
        "Name=Dock icons (aligned)\n"
        "Comment=Dock icons trimmed and scaled to the same visual height\n"
        f"Inherits={parent_theme()}\n"
        f"Directories={THEME_SIZE_DIR}/apps\n"
        "\n"
        f"[{THEME_SIZE_DIR}/apps]\n"
        f"Size={CANVAS}\n"
        "Type=Fixed\n"
        "Context=Applications\n"
    )
    if index.is_file() and index.read_text(encoding="utf-8") == content:
        return
    index.parent.mkdir(parents=True, exist_ok=True)
    index.write_text(content, encoding="utf-8")


def patch_desktop(desktop: Path, icon: Path) -> bool:
    """Переписывает Icon= на сгенерированный файл; системные .desktop не трогает.

    Проверяется resolved путь: симлинк из ~/.local/share/applications в
    /usr/share/applications иначе записал бы правку в системный файл.
    """
    applications = (data_home() / "applications").resolve()
    if desktop.is_symlink():
        warn(f"{desktop} — симлинк, править .desktop через него не буду")
        return False
    if applications not in desktop.resolve().parents:
        warn(f"{desktop} вне {applications} — иконку не подменить")
        return False

    position = entry_icon_position(desktop)
    if position is None:
        warn(f"{desktop}: нет Icon= в [Desktop Entry]")
        return False

    lines = desktop.read_text(encoding="utf-8", errors="surrogateescape").splitlines(True)
    new_line = f"Icon={icon}\n"
    if lines[position] == new_line:
        return False
    lines[position] = new_line
    desktop.write_text("".join(lines), encoding="utf-8", errors="surrogateescape")
    return True


def main() -> int:
    favorites = read_favorites()
    if not favorites:
        warn("org.gnome.shell favorite-apps пуст — выравнивать нечего")
        return 1

    target_dir = theme_dir() / THEME_SIZE_DIR / "apps"
    target_dir.mkdir(parents=True, exist_ok=True)

    # Имена иконок для поиска файлов собираем заранее: один обход корней на всех.
    entries: list[tuple[str, Path, str, str | None]] = []
    for desktop_id in favorites:
        desktop = desktop_file(desktop_id)
        if desktop is None:
            warn(f"{desktop_id}: .desktop не найден")
            continue
        value = icon_value(desktop) or ""
        override = ICON_OVERRIDES.get(desktop_id)
        if not value and not override:
            warn(f"{desktop_id}: нет строки Icon=")
            continue
        entries.append((desktop_id, desktop, value, override))

    names = {value for _id, _desktop, value, _override in entries if value and not value.startswith("/")}
    names |= {override for _id, _desktop, _value, override in entries if override}
    index = index_icon_files(names) if names else {}
    theme = parent_theme()
    labels = shortcut_labels(favorites) if badges_enabled() else {}

    produced: set[str] = set()
    sources = load_sources()
    fresh_sources: dict[str, str] = {}
    failures = 0
    for desktop_id, desktop, value, override in entries:
        if override:
            candidates = index.get(override)
            if not candidates:
                warn(f"{desktop_id}: иконка {override} не найдена в темах")
                failures += 1
                continue
            source = pick_icon(candidates, theme)
            destination = target_dir / f"dock-{desktop_id.removesuffix('.desktop')}.png"
            patch = True
        elif value.startswith("/"):
            destination = target_dir / f"dock-{desktop_id.removesuffix('.desktop')}.png"
            source = original_source(sources, destination, Path(value))
            if source is None:
                warn(f"{desktop_id}: нет исходного файла иконки (Icon={value})")
                failures += 1
                continue
            patch = True
        else:
            candidates = index.get(value)
            if not candidates:
                warn(f"{desktop_id}: иконка {value} не найдена в темах")
                failures += 1
                continue
            source = pick_icon(candidates, theme)
            destination = target_dir / f"{value}.png"
            patch = False

        try:
            pixbuf = load_pixbuf(source)
            width, height = pixbuf.get_width(), pixbuf.get_height()
            if max(width, height) < CANVAS // 2:
                warn(f"{desktop_id}: исходник {width}×{height} — до 512 px будет мыло")
            canvas, before, after = render(pixbuf)
            label = labels.get(desktop_id, "")
            # Наложение поверх чужой копии набора запрещено: иначе метка легла бы
            # на старую метку (бывает только если потерян sources.json).
            if label and theme_dir() not in source.parents:
                canvas = draw_badge(canvas, label)
            written = save_png(canvas, destination)
        except (GLib.GError, ValueError, OSError) as error:
            warn(f"{desktop_id}: {error}")
            failures += 1
            continue

        produced.add(destination.name)
        # Замена иконки не запоминается как исходник: она выбирается по имени
        # каждый прогон, а в карте лежат только пути из чужих .desktop.
        if patch and not override and theme_dir() not in source.parents:
            fresh_sources[destination.name] = str(source)
        note = []
        if label:
            note.append(f"метка «{label}»")
        if written:
            note.append("обновлено")
        if after < fill_ratio() - 0.01:
            note.append("высота ограничена шириной арта")
        if patch and patch_desktop(desktop, destination):
            note.append("Icon= переписан")
        suffix = f"  ({source.name}{', ' + ', '.join(note) if note else ''})"
        print(f"{desktop_id}: {before * 100:.0f}% -> {after * 100:.0f}%{suffix}")

    # Мусор от прежних прогонов: иконки имён, которые больше не закреплены. Файлы
    # dock-*.png не трогаем — на них ссылаются .desktop из ~/.local/share/,
    # которые могли просто выпасть из favorite-apps. При сбоях не убираем ничего:
    # на старый файл может ссылаться .desktop, не разобранный в этом прогоне.
    if not failures:
        for stale in target_dir.glob("*.png"):
            if stale.name.startswith("dock-") or stale.name in produced:
                continue
            stale.unlink()
    # Сбой означает, что часть иконок не пересчитана — их старые записи храним.
    save_sources(sources | fresh_sources if failures else fresh_sources)


    ensure_index_theme()
    print(f"набор иконок: {theme_dir()} (Inherits={parent_theme()})")
    if failures:
        warn(f"пропущено иконок: {failures}")
    return 0 if produced else 1


if __name__ == "__main__":
    sys.exit(main())
