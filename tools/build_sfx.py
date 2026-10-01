#!/usr/bin/env python3
"""Build block.exe's sound effects from tools/sfx_src/.

Reads tools/sfx_src/manifest.json, cuts each chosen source WAV to length with a
fade-out, normalises it to -1 dBFS, applies its gain and writes
assets/sfx/<name>.wav as 22.05 kHz 16-bit mono. The firmware keeps only the
first 64 KB of a sample, so a longer result is an error. Standard library only;
the same inputs always give the same bytes.

    python3 tools/build_sfx.py                     build assets/sfx/
    python3 tools/build_sfx.py --preview out.wav   also write every sound into one file
    python3 tools/build_sfx.py --suggest-start     print where each source's sound begins
"""
import argparse
import array
import json
import sys
import wave
from pathlib import Path

RATE = 22050
MAX_BYTES = 65536
PEAK = 10 ** (-1 / 20)   # -1 dBFS
FADE_IN_MS = 2           # only when the cut starts mid-sound
ONSET_DB = -40
EDIT_FIELDS = ("start_ms", "length_ms", "fade_ms", "gain_db")
NAMES = ("ui_move", "ui_select", "ui_back", "key", "save", "move", "rotate",
         "hard_drop", "lock", "clear", "tetris", "level_up", "game_over", "high_score")

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "tools" / "sfx_src"
OUT_DIR = ROOT / "assets" / "sfx"


class BuildError(Exception):
    pass


def read_source(path):
    """A source WAV's samples as floats in -1..1. It must be 22.05 kHz 16-bit mono."""
    path = Path(path)
    if not path.is_file():
        raise BuildError(f"{path.name}: missing source file")
    with wave.open(str(path), "rb") as w:
        fmt = (w.getframerate(), w.getsampwidth(), w.getnchannels())
        if fmt != (RATE, 2, 1):
            raise BuildError(f"{path.name}: must be {RATE} Hz 16-bit mono, "
                             f"not {fmt[0]} Hz {8 * fmt[1]}-bit {fmt[2]}-channel")
        data = array.array("h")
        data.frombytes(w.readframes(w.getnframes()))
    if sys.byteorder == "big":
        data.byteswap()
    return [s / 32768 for s in data]


def edit(samples, entry):
    """Cut, fade and level one sound as its manifest entry says."""
    start = round(entry["start_ms"] * RATE / 1000)
    length = round(entry["length_ms"] * RATE / 1000)
    out = samples[start:start + length]
    if not out:
        raise BuildError("nothing left after the cut")
    fade_in = min(round(FADE_IN_MS * RATE / 1000), len(out)) if start > 0 else 0
    for i in range(fade_in):
        out[i] *= i / fade_in
    fade = min(round(entry["fade_ms"] * RATE / 1000), len(out))
    for i in range(fade):
        out[len(out) - 1 - i] *= i / fade
    peak = max(abs(s) for s in out)
    if peak == 0:
        raise BuildError("the cut is silent")
    scale = PEAK / peak * 10 ** (entry["gain_db"] / 20)
    return [s * scale for s in out]


def onset_ms(samples, threshold_db=ONSET_DB):
    """Where a sound first rises above the threshold, in ms (0 if it never does)."""
    level = 10 ** (threshold_db / 20)
    for i, s in enumerate(samples):
        if abs(s) >= level:
            return round(i * 1000 / RATE)
    return 0


def to_pcm(samples):
    data = array.array("h", (max(-32768, min(32767, round(s * 32767))) for s in samples))
    if sys.byteorder == "big":
        data.byteswap()
    return data.tobytes()


def write_wav(path, pcm):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm)


def load_manifest(src_dir):
    path = Path(src_dir) / "manifest.json"
    if not path.is_file():
        raise BuildError(f"{path}: missing manifest")
    sounds = json.loads(path.read_text())["sounds"]
    for name, entry in sounds.items():
        if name not in NAMES:
            raise BuildError(f"{name}: not a sound block.exe plays")
        missing = [k for k in EDIT_FIELDS if k not in entry]
        if missing:
            raise BuildError(f"{name}: manifest entry lacks {', '.join(missing)}")
        if "source" not in entry and "synth" not in entry:
            raise BuildError(f"{name}: manifest entry needs a source or a synth table")
    return sounds


def render(name, entry, src_dir):
    try:
        if "synth" in entry:
            raise BuildError("synth entries need the fallback synthesiser (plan Task 9)")
        return edit(read_source(Path(src_dir) / entry["source"]), entry)
    except BuildError as e:
        raise BuildError(f"{name}: {e}") from None


def build(src_dir=SRC_DIR, out_dir=OUT_DIR):
    """Build every sound in the manifest; nothing is written unless all succeed."""
    built = {}
    for name, entry in sorted(load_manifest(src_dir).items()):
        pcm = to_pcm(render(name, entry, src_dir))
        if len(pcm) > MAX_BYTES:
            raise BuildError(f"{name}: {len(pcm)} bytes of PCM, over the {MAX_BYTES}-byte sample limit")
        built[name] = pcm
    for name, pcm in built.items():
        write_wav(Path(out_dir) / f"{name}.wav", pcm)
    return built


def write_preview(path, built, gap_ms=400):
    """Every built sound in play order, with a gap after each, in one WAV."""
    gap = bytes(2 * round(gap_ms * RATE / 1000))
    write_wav(path, b"".join(built[n] + gap for n in NAMES if n in built))


def main(argv=None):
    parser = argparse.ArgumentParser(description="Build block.exe's sound effects from tools/sfx_src/.")
    parser.add_argument("--preview", metavar="WAV", help="also write every sound, one after another, to WAV")
    parser.add_argument("--suggest-start", action="store_true",
                        help="print where each source's sound begins, then stop")
    args = parser.parse_args(argv)
    try:
        if args.suggest_start:
            for name, entry in sorted(load_manifest(SRC_DIR).items()):
                if "source" in entry:
                    print(f"{name}: start_ms {onset_ms(read_source(SRC_DIR / entry['source']))}")
            return 0
        built = build()
        print(f"built {len(built)} sounds into {OUT_DIR.relative_to(ROOT)}")
        missing = [n for n in NAMES if n not in built]
        if missing:
            print("not in the manifest yet: " + ", ".join(missing))
        if args.preview:
            write_preview(args.preview, built)
            print(f"preview: {args.preview}")
        return 0
    except BuildError as e:
        print(f"build_sfx: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
