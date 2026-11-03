#!/usr/bin/env python3
"""Encode short guided GIFs from actual isolated native demo captures only."""
import argparse
import json
import hashlib
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"
BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
WORKFLOWS = {
    "cards-compact": ("layout", (0, 0, 790, 1000), [
        "Cards — give every design room to breathe",
        "Compact — more models, all the same metrics",
        "Cards — switch back with one control",
    ]),
    "print-check": ("print", (0, 0, 440, 760), [
        "Check 1 — daily print growth",
        "Check 2 — one more print; NEW appears",
        "Check 3 — unchanged; NEW clears",
    ]),
    "history-range": ("history", (0, 0, 790, 1080), [
        "24 hours — six metrics, one observed timeline",
        "7 days — the same metrics, a wider view",
        "24 hours — all six metrics remain visible",
    ]),
}

def build(source, output):
    checks = json.loads((source / "CAPTURE-CHECKS.json").read_text())
    assert checks["fictionalDataOnly"] and not checks["networkAndKeychainUsed"]
    assert checks["fullDashboard"] and checks["fullDashboardHeight"] > 1800
    assert checks["nativeCardsCompactActions"] and checks["nativeHistoryRangeActions"]
    assert checks["latestPrintIncrease"] == 1 and checks["unchangedCheckClearsNew"]
    output.mkdir(parents=True, exist_ok=True)
    results = {}
    for name, (prefix, crop, captions) in WORKFLOWS.items():
        frames = []
        for index, caption in enumerate(captions):
            with Image.open(source / "motion" / f"{prefix}-{index}.png") as image:
                assert image.size in [(crop[2], crop[3]), (crop[2]*2, crop[3]*2)]
                native = image.convert("RGB").resize((crop[2], crop[3]), Image.Resampling.LANCZOS)
            frame = Image.new("RGB", (790, native.height + 86), "#1B1C1F")
            frame.paste(native, (0, 86))
            draw = ImageDraw.Draw(frame)
            assert draw.textbbox((0, 0), caption, font=ImageFont.truetype(BOLD, 21))[2] < frame.width - 44
            draw.text((22, 13), caption, font=ImageFont.truetype(BOLD, 21), fill="#F7F8FC")
            draw.text((22, 49), f"OFFLINE DEMO · Fictional observations · Native app capture    {index + 1}/3", font=ImageFont.truetype(FONT, 15), fill="#E6C64D")
            if prefix == "print":
                notes = [("DAILY GROWTH", "Violet makes prints easy to spot. The number covers the selected growth window."), ("LATEST CHECK", "Blue NEW marks the extra print found in this check. Daily growth remains separate."), ("UNCHANGED CHECK", "NEW clears after a successful unchanged check. Today’s print growth stays visible.")]
                title, note = notes[index]
                draw.text((466, 162), title, font=ImageFont.truetype(BOLD, 19), fill="#E6C64D")
                import textwrap
                draw.multiline_text((466, 205), "\n".join(textwrap.wrap(note, width=24)), font=ImageFont.truetype(FONT, 22), fill="#F7F8FC", spacing=10)
                draw.multiline_text((466, 440), "One native model card.\nThree fictional checks.\nNo live account data.", font=ImageFont.truetype(FONT, 18), fill="#C6C7CA", spacing=10)
            frames.append(frame)
        # One shared palette avoids flashing when native controls change state.
        palette_source = Image.new("RGB", (530 * 3, 460))
        for index, frame in enumerate(frames):
            thumb = frame.copy(); thumb.thumbnail((530, 460))
            palette_source.paste(thumb, (530 * index, 0))
        palette = palette_source.quantize(colors=256)
        quantized = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
        gif = output / f"{name}.gif"
        quantized[0].save(gif, save_all=True, append_images=quantized[1:], duration=[2100, 2600, 2300], loop=0, optimize=True, disposal=1)
        frames[1].save(output / f"{name}-poster.png", optimize=True)
        with Image.open(gif) as exported:
            assert exported.n_frames == 3 and exported.info.get("loop") == 0
        assert gif.stat().st_size < 4_000_000
        results[name] = {"frames": 3, "durationSeconds": 7, "bytes": gif.stat().st_size, "source": "isolated native demo"}
    (output / "ANIMATIONS.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))

def verify(output):
    records = json.loads((output / "ANIMATIONS.json").read_text())
    assert set(records) == set(WORKFLOWS)
    for name in WORKFLOWS:
        path = output / f"{name}.gif"
        assert path.stat().st_size == records[name]["bytes"] < 4_000_000
        with Image.open(path) as image:
            assert image.n_frames == 3 and image.info.get("loop") == 0
            assert "comment" not in image.info
            total = 0; native_frames = set()
            for index in range(image.n_frames):
                image.seek(index); total += image.info["duration"]
                native = image.convert("RGB").crop((0, 86, image.width, image.height))
                native_frames.add(hashlib.sha256(native.tobytes()).digest())
            assert total == 7000 and len(native_frames) >= 2
            with Image.open(output / f"{name}-poster.png") as poster:
                assert poster.size == image.size
    print("Verified 3 seven-second looping GIFs, changing native content, static posters and bounded sizes.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("output", type=Path, nargs="?")
    parser.add_argument("--verify", action="store_true", help="Validate existing GIFs/posters in the first directory argument")
    args = parser.parse_args()
    if args.verify:
        verify(args.capture)
    else:
        if args.output is None: parser.error("output directory is required when building")
        build(args.capture, args.output)
        verify(args.output)
