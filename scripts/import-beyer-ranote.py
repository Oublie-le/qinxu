#!/usr/bin/env python3
"""Rebuild verified Beyer student lessons from openly licensed RANOTE data.

The JSON is a *playback* timeline. Its gated note-off times are never used as
notation durations: noteheads/dots/flags in the matching SVG determine those.
Every published source input is pinned in source-lock.json. Run --check to
compare generated XML/manifest without modifying application resources.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from fractions import Fraction
import hashlib
import html
import json
from pathlib import Path
import re
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".local-build/research-beyer"
DEST = ROOT / "Sources/QinXuApp/Resources/Books/Beyer"
HOST = "https://ranote.zzxxccvv.com"
LICENSE = "https://creativecommons.org/licenses/by/4.0/"
SELECTED = [n for n in range(1, 44) if n not in (15, 19, 23, 29, 38)] + [61]
NATURALS = (0, 2, 4, 5, 7, 9, 11)
STEPS = "CDEFGAB"


def cls(element):
    return element.get("class", "")


def glyph(element):
    return element.get("href", "").split("-")[0].lstrip("#")


def rational(value):
    result = Fraction(value).limit_denominator(96)
    if abs(float(result) - value) > 0.00011:
        raise ValueError(f"Non-notational onset: {value}")
    return result


def sub(parent, tag, value=None, **attrs):
    element = ET.SubElement(parent, tag, attrs)
    if value is not None:
        element.text = str(value)
    return element


def source_files(number, fetch=False):
    paths = {
        "notes.json": f"/scores/beyer-op101-{number:03}/notes.json",
        "score.svg": f"/scores/beyer-op101-{number:03}/score-1100.svg",
        "page.html": f"/en/s/beyer-op101-{number:03}",
    }
    result = {}
    for suffix, remote in paths.items():
        path = CACHE / f"{number:03}-{suffix}"
        if not path.exists():
            if not fetch:
                raise ValueError(f"Missing {path}; use --fetch to retrieve public sources")
            request = urllib.request.Request(HOST + remote, headers={"User-Agent": "QinXu-source-verification"})
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(urllib.request.urlopen(request, timeout=30).read())
        result[suffix] = (path.read_bytes(), HOST + remote)
    return result


def decode_score(number, files):
    playback = json.loads(files["notes.json"][0])
    page = files["page.html"][0].decode()
    if "This score data is released under CC BY 4.0" not in page:
        raise ValueError("Per-score CC BY 4.0 declaration missing")
    source_match = re.search(r"Source edition:.*?p\. (\d+)(?:[–-](\d+))?", page)
    if not source_match:
        raise ValueError("Original edition page missing")
    source_page = int(source_match[2] or source_match[1]) if number < 12 else int(source_match[1])
    svg_text = re.sub(r"<\?xml[^>]*\?>", "", files["score.svg"][0].decode())
    root = ET.fromstring("<root>" + svg_text + "</root>")
    for element in root.iter():
        if cls(element) in ("fermata", "trill", "mordent", "turn", "pedal", "arpeg", "gliss", "octave", "trem"):
            raise ValueError("Unverified duration/pitch/performance instruction in source engraving")
        # Verified against Peters pp.22–23: No.10's sole "staccato" direction
        # belongs to the teacher's Seconda on p.22, not the student's Prima.
        if number == 10 and cls(element) == "dir" and "".join(element.itertext()) == "staccato":
            continue
        if cls(element) in ("dir", "tempo") and re.search(
            r"non\s+legato|staccato|rit[.a]|accel|rall|D\.?\s*[CS]\.?|coda|fine|swing", "".join(element.itertext()), re.I
        ):
            raise ValueError("Unverified textual articulation or navigation instruction")
    parents = {child: parent for parent in root.iter() for child in parent}
    student_ids = {note["id"] for note in playback["notes"] if note["s"] <= 2}
    note_staffs = {note["id"]: note["s"] for note in playback["notes"]}
    engraving = {}
    visible_student_ids = set()
    clefs = {}
    meter_by_measure = {}
    meter = None
    for measure_index, measure in enumerate(x for x in root.iter() if cls(x) == "measure"):
        next_meter = None
        staves = [x for x in measure if cls(x) == "staff"]
        for visual_index, staff_element in enumerate(staves, 1):
            # Empty staves are suppressed after the first system. Their visual
            # position is therefore not a reliable hand/teacher assignment.
            assigned = {note_staffs[x.get("id")] for x in staff_element.iter()
                        if cls(x) == "note" and x.get("id") in note_staffs}
            if not assigned:
                if measure_index == 0:
                    assigned = {visual_index}  # first system retains empty staves and their clefs
                else:
                    continue
            if len(assigned) != 1:
                raise ValueError("Source staff contains inconsistent part assignments")
            staff = next(iter(assigned))
            if staff > 2:
                continue
            lines = [x for x in staff_element if x.tag.endswith("path")]
            ys = [float(re.match(r"M[-\d.]+ ([\d.-]+)", x.get("d", ""))[1]) for x in lines[:5]]
            if len(ys) != 5:
                raise ValueError("Missing five staff lines")
            half_space = (ys[-1] - ys[0]) / 8
            for element in staff_element:
                if cls(element) == "clef":
                    codes = [glyph(x) for x in element.iter() if x.tag.endswith("use")]
                    if codes == ["E050"]:
                        clefs[staff] = 4 * 7 + 2  # E4 on bottom line of G2 clef
                    elif codes == ["E062"]:
                        clefs[staff] = 2 * 7 + 4  # G2 on bottom line of F4 clef
                    else:
                        raise ValueError(f"Unsupported source clef {codes}")
                if cls(element) == "meterSig":
                    codes = [glyph(x) for x in element.iter() if x.tag.endswith("use")]
                    if codes == ["E08A"]:
                        new_meter = (4, 4)
                    elif len(codes) == 2 and all(re.fullmatch(r"E08[0-9]", x) for x in codes):
                        new_meter = tuple(int(x[-1]) for x in codes)
                    else:
                        raise ValueError(f"Unsupported source meter {codes}")
                    meter_x = min(float(re.search(r"translate\(([-\d.]+),", x.get("transform"))[1])
                                  for x in element.iter() if x.tag.endswith("use"))
                    head_xs = [float(re.search(r"translate\(([-\d.]+),", x.get("transform"))[1])
                               for x in staff_element.iter() if x.tag.endswith("use") and glyph(x).startswith("E0A")]
                    if head_xs and meter_x > max(head_xs):
                        next_meter = new_meter  # courtesy signature at preceding system end
                    else:
                        meter = new_meter
            for note in (x for x in staff_element.iter() if cls(x) == "note"):
                note_id = note.get("id")
                visible_student_ids.add(note_id)
                ancestors = []
                current = note
                while current in parents:
                    current = parents[current]
                    ancestors.append(current)
                    if current is staff_element:
                        break
                if any(cls(x) in ("beam", "tuplet", "graceGrp") for x in ancestors):
                    raise ValueError("Student beam/tuplet/grace requires separate verification")
                chord = next((x for x in ancestors if cls(x) == "chord"), None)
                owner = chord if chord is not None else note
                if any(cls(x) == "artic" for x in owner.iter()):
                    raise ValueError("Student articulation is not represented by current practice model")
                heads = [x for x in note.iter() if x.tag.endswith("use") and glyph(x).startswith("E0A")]
                if len(heads) != 1 or glyph(heads[0]) not in ("E0A2", "E0A3", "E0A4"):
                    raise ValueError("Unsupported or ambiguous notehead")
                duration = {"E0A2": Fraction(4), "E0A3": Fraction(2), "E0A4": Fraction(1)}[glyph(heads[0])]
                flags = [x for x in owner.iter() if cls(x) == "flag"]
                if flags:
                    codes = [glyph(x) for flag in flags for x in flag.iter() if x.tag.endswith("use")]
                    if len(codes) != 1 or codes[0] not in ("E240", "E241", "E242", "E243", "E244", "E245"):
                        raise ValueError("Unsupported flag")
                    duration /= 2 ** ((int(codes[0][-2:], 16) - 0x40) // 2 + 1)
                dots = [x for x in owner if cls(x) == "dots"]
                if dots:
                    dot_columns = {x.get("cx") for dots_element in dots for x in dots_element if x.tag.endswith("ellipse")}
                    if len(dot_columns) not in (1, 2):
                        raise ValueError("Ambiguous augmentation dots")
                    duration *= sum(Fraction(1, 2 ** k) for k in range(len(dot_columns) + 1))
                y = float(re.search(r"translate\([-\d.]+, ([\d.-]+)\)", heads[0].get("transform"))[1])
                distance = (ys[-1] - y) / half_space
                if abs(distance - round(distance)) > 0.02:
                    raise ValueError("Notehead does not align to a staff pitch")
                diatonic = clefs[staff] + round(distance)
                octave, step = divmod(diatonic, 7)
                engraving[note_id] = {"duration": duration, "staff": staff, "step": STEPS[step], "octave": octave,
                                      "natural": 12 * (octave + 1) + NATURALS[step]}
        if meter is None:
            raise ValueError("Missing source meter")
        meter_by_measure[measure.get("id")] = meter
        if next_meter is not None:
            meter = next_meter
    if student_ids != visible_student_ids:
        raise ValueError(f"Notation/playback note IDs differ (ties or omitted notes): {len(student_ids)} / {len(visible_student_ids)}")
    notes = []
    for original in playback["notes"]:
        if original["s"] > 2:
            continue
        encoded = engraving[original["id"]]
        if encoded["staff"] != original["s"]:
            raise ValueError("Staff mismatch")
        alter = original["p"] - encoded["natural"]
        if alter != 0:
            # First batch is entirely natural pitches. Future accidentals require
            # verifying both the SVG accidental/key signature and playback pitch.
            raise ValueError("Accidental/key signature requires separate verification")
        if abs(float(encoded["duration"]) - original["d"]) > 0.01:
            raise ValueError("Notation/playback duration differs beyond endpoint gating")
        notes.append({**original, **encoded, "q": rational(original["q"]), "alter": alter})
    measures = []
    for index, original in enumerate(playback["measures"]):
        start = rational(original["q"])
        end = rational(playback["measures"][index + 1]["q"] if index + 1 < len(playback["measures"]) else playback["end"])
        measures.append({**original, "start": start, "length": end - start, "meter": meter_by_measure[original["id"]],
                         "notes": [note for note in notes if note["m"] == index]})
    return playback["bpm"], measures, source_page


def write_note(parent, duration, staff, note=None, chord=False):
    element = sub(parent, "note")
    if chord:
        sub(element, "chord")
    if note is None:
        sub(element, "rest")
    else:
        pitch = sub(element, "pitch")
        sub(pitch, "step", note["step"])
        if note["alter"]:
            sub(pitch, "alter", note["alter"])
        sub(pitch, "octave", note["octave"])
    ticks = duration * 96
    if ticks.denominator != 1:
        raise ValueError("Non-integral notation duration")
    sub(element, "duration", ticks.numerator)
    sub(element, "voice", staff)
    types = {Fraction(4): "whole", Fraction(2): "half", Fraction(1): "quarter", Fraction(1, 2): "eighth", Fraction(1, 4): "16th"}
    for base, name in types.items():
        for dots in range(3):
            if base * sum(Fraction(1, 2 ** k) for k in range(dots + 1)) == duration:
                sub(element, "type", name)
                for _ in range(dots):
                    sub(element, "dot")
                sub(element, "staff", staff)
                return
    sub(element, "staff", staff)


def encode_lesson(number, label, measures, bpm):
    root = ET.Element("score-partwise", version="4.0")
    sub(root, "movement-title", "拜厄 · " + label)
    identification = sub(root, "identification")
    sub(identification, "creator", "费迪南德·拜厄", type="composer")
    sub(identification, "rights", "RANOTE 录谱数据，CC BY 4.0；琴序转换与中文标题；" + LICENSE)
    sub(identification, "source", HOST + f"/en/s/beyer-op101-{number:03}")
    parts = sub(root, "part-list")
    sub(sub(parts, "score-part", id="P1"), "part-name", "钢琴学生声部")
    part = sub(root, "part", id="P1")
    meter = measures[0]["meter"]
    for index, measure in enumerate(measures):
        if measure["meter"] != meter:
            raise ValueError("Meter change within lesson")
        element = sub(part, "measure", number=str(index + 1))
        length = measure["length"]
        if length != Fraction(meter[0] * 4, meter[1]):
            element.set("implicit", "yes")
        if index == 0:
            attributes = sub(element, "attributes")
            sub(attributes, "divisions", 96)
            time = sub(attributes, "time")
            sub(time, "beats", meter[0]); sub(time, "beat-type", meter[1])
            sub(attributes, "staves", 2)
            for staff, sign, line in [(1, "G", 2), (2, "F", 4)]:
                clef = sub(attributes, "clef", number=str(staff))
                sub(clef, "sign", sign); sub(clef, "line", line)
            sub(sub(element, "direction"), "sound", tempo=str(bpm))
        for staff in (1, 2):
            if staff == 2:
                sub(sub(element, "backup"), "duration", int(length * 96))
            groups = defaultdict(list)
            for note in measure["notes"]:
                if note["s"] == staff:
                    groups[note["q"] - measure["start"]].append(note)
            cursor = Fraction(0)
            for onset, group in sorted(groups.items()):
                if onset < cursor:
                    raise ValueError("Overlapping student voices need explicit voicing")
                if onset > cursor:
                    write_note(element, onset - cursor, staff)
                group.sort(key=lambda note: (-note["duration"], note["p"]))
                for note_index, note in enumerate(group):
                    write_note(element, note["duration"], staff, note, chord=note_index > 0)
                cursor = onset + group[0]["duration"]
            if cursor > length:
                raise ValueError("Note extends past measure without a verified tie")
            if cursor < length:
                write_note(element, length - cursor, staff)
    ET.indent(root, space="  ")
    return ET.tostring(root, encoding="utf-8", xml_declaration=True) + b"\n"


def build(fetch=False):
    output = {}
    lessons = []
    locks = {}
    evidence = []
    for number in SELECTED:
        files = source_files(number, fetch)
        for suffix, (data, url) in files.items():
            locks[f"{number:03}-{suffix}"] = {"url": url, "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
        bpm, measures, page = decode_score(number, files)
        segments = []
        if number in (1, 2):
            size, count = (8, 13) if number == 1 else (16, 9)
            for variation in range(count):
                selected = [m for m in measures if variation * size < m["n"] <= (variation + 1) * size]
                title = f"第{number}首 · " + ("主题" if variation == 0 else f"变奏{variation}")
                suffix = "theme" if variation == 0 else f"v{variation:02}"
                source_page = (11 if variation <= 6 else 13) if number == 1 else (15 if variation <= 4 else 17)
                segments.append((title, suffix, selected, source_page))
        else:
            segments = [(f"第{number}首", None, measures, page)]
        for title, suffix, selected, source_page in segments:
            filename = f"{number:03}" + ("-" + suffix if suffix else "") + ".musicxml"
            identifier = "beyer-op101-" + filename.removesuffix(".musicxml")
            xml = encode_lesson(number, title, selected, bpm)
            output[filename] = xml
            repeated = len({m["id"] for m in selected}) != len(selected)
            notes = ["仅学生声部；教师伴奏不计入练习。" if number < 12 else "双手学生练习谱。",
                     "中文重排保留音高、记谱时值与左右手；指法、力度与连奏线请参照公版原页。",
                     "默认速度供练习调整，不代表原书标注的唯一速度。"]
            if repeated:
                notes.append("原谱反复已按公开演奏顺序展开，小节编号为展开后的连续编号。")
            lessons.append({"id": identifier, "title": title, "filename": filename, "sourcePage": source_page, "notes": notes})
            evidence.append({"id": identifier, "source": files["page.html"][1], "measures": len(selected),
                             "notes": sum(len(m["notes"]) for m in selected), "beats": float(sum(m["length"] for m in selected)),
                             "repeatExpanded": repeated, "notationDurationSource": "SVG notehead + augmentation dots + flags (not playback d)"})
    output["manifest.json"] = (json.dumps({"version": 1, "lessons": lessons}, ensure_ascii=False, indent=2) + "\n").encode()
    output["source-lock.json"] = (json.dumps({"version": 1, "license": LICENSE, "inputs": locks}, indent=2) + "\n").encode()
    output["verification.json"] = (json.dumps({"version": 1, "lessons": evidence}, ensure_ascii=False, indent=2) + "\n").encode()
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true", help="Fetch missing publicly served source files")
    parser.add_argument("--check", action="store_true", help="Verify source hashes and compare all generated files")
    args = parser.parse_args()
    output = build(args.fetch)
    # Even a normal rebuild cannot silently accept changed upstream source data.
    lock = DEST / "source-lock.json"
    if lock.exists():
        previous = json.loads(lock.read_bytes())
        updated = json.loads(output["source-lock.json"])
        if previous["license"] != updated["license"] or any(updated["inputs"].get(key) != value for key, value in previous["inputs"].items()):
            raise SystemExit("Pinned source checksum changed. Review source differences before updating the lock.")
    if args.check:
        mismatches = [name for name, data in output.items() if not (DEST / name).exists() or (DEST / name).read_bytes() != data]
        if mismatches:
            raise SystemExit("Generated files differ: " + ", ".join(mismatches))
        print(f"PASS: {len(output) - 3} Beyer lesson files, pinned source inputs, engraving durations and manifest")
    else:
        DEST.mkdir(parents=True, exist_ok=True)
        for name, data in output.items():
            (DEST / name).write_bytes(data)
        print(f"Generated {len(output) - 3} complete lesson segments in {DEST}")


if __name__ == "__main__":
    main()
