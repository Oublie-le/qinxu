#!/usr/bin/env python3
"""Compare native inference's acoustic note onsets against an aligned SMF reference.
No offset grading, tuning or expected-score filtering is performed.
"""
import argparse
import bisect
import hashlib
import json
from pathlib import Path
import statistics
import struct


def note_onsets(path):
    data = path.read_bytes()
    if data[:4] != b'MThd':
        raise ValueError('Expected a Standard MIDI File')
    length = int.from_bytes(data[4:8], 'big')
    _, tracks, division = struct.unpack('>HHH', data[8:14])
    if division & 0x8000:
        raise ValueError('SMPTE MIDI timing is not supported by this evaluation script')
    cursor = 8 + length
    notes, tempos = [], [(0, 500000)]
    for _ in range(tracks):
        if data[cursor:cursor+4] != b'MTrk':
            raise ValueError('Missing MIDI track')
        count = int.from_bytes(data[cursor+4:cursor+8], 'big')
        chunk = data[cursor+8:cursor+8+count]
        cursor += 8 + count
        i, tick, running = 0, 0, None
        def vlq():
            nonlocal i
            value = 0
            for _ in range(4):
                b = chunk[i]; i += 1; value = (value << 7) | (b & 127)
                if b < 128: return value
            raise ValueError('Invalid variable-length MIDI number')
        while i < len(chunk):
            tick += vlq()
            status = chunk[i]
            if status & 128:
                i += 1
                if status < 240: running = status
            else:
                if running is None: raise ValueError('Missing running status')
                status = running
            if status == 255:
                kind = chunk[i]; i += 1
                size = vlq(); payload = chunk[i:i+size]; i += size
                if kind == 81: tempos.append((tick, int.from_bytes(payload, 'big')))
            elif status in (240, 247):
                size = vlq(); i += size
            elif status < 240:
                size = 1 if status >> 4 in (12, 13) else 2
                payload = chunk[i:i+size]; i += size
                if status >> 4 == 9 and payload[1] > 0:
                    notes.append((tick, payload[0]))
            else:
                raise ValueError('Unsupported MIDI system event')
    tempo_by_tick = dict(tempos)
    ticks = sorted(tempo_by_tick)
    seconds = [0.0]
    for n in range(1, len(ticks)):
        seconds.append(seconds[-1] + (ticks[n] - ticks[n-1]) * tempo_by_tick[ticks[n-1]] / division / 1e6)
    def timestamp(t):
        n = bisect.bisect_right(ticks, t) - 1
        return seconds[n] + (t - ticks[n]) * tempo_by_tick[ticks[n]] / division / 1e6
    return sorted((timestamp(t), pitch) for t, pitch in notes)


def match(reference, predicted, tolerance):
    # Maximum-cardinality one-to-one pitch/onset matching. Closer edges tried first.
    edges = [sorted((j for j, (rt, rp) in enumerate(reference)
                     if rp == pitch and abs(rt-t) <= tolerance), key=lambda j: abs(reference[j][0]-t))
             for t, pitch in predicted]
    assigned = {}
    def visit(i, seen):
        for j in edges[i]:
            if j in seen: continue
            seen.add(j)
            if j not in assigned or visit(assigned[j], seen):
                assigned[j] = i; return True
        return False
    for i in range(len(predicted)): visit(i, set())
    tp = len(assigned)
    precision = tp / len(predicted) if predicted else 0
    recall = tp / len(reference) if reference else 0
    return {'tolerance_ms': round(tolerance*1000), 'matched': tp,
            'false_positive': len(predicted)-tp, 'missed': len(reference)-tp,
            'precision': precision, 'recall': recall,
            'f1': 2*precision*recall/(precision+recall) if precision+recall else 0}


def percentile(values, p):
    values = sorted(values)
    return values[min(len(values)-1, int((len(values)-1)*p))]

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference', type=Path)
    parser.add_argument('predictions', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    prediction = json.loads(args.predictions.read_text())
    start, end = prediction['firstAnalyzed'], prediction['lastAnalyzed']
    reference = [(t,p) for t,p in note_onsets(args.reference) if start <= t <= end]
    predicted = [(e['time'], e['pitch']) for e in prediction['events'] if e['isOn'] and start <= e['time'] <= end]
    report = {'reference_sha256': hashlib.sha256(args.reference.read_bytes()).hexdigest(),
              'interval_seconds': [start, end], 'reference_onsets': len(reference), 'predicted_onsets': len(predicted),
              'onset_metrics': [match(reference, predicted, t) for t in [.05, .10]],
              'model_revision': prediction['modelRevision'], 'windows': prediction['windows'],
              'max_active_pitches': prediction['maxActivePitches'],
              'inference_ms_median': statistics.median(prediction['inferenceSeconds'])*1000,
              'inference_ms_p95': percentile(prediction['inferenceSeconds'], .95)*1000,
              'buffered_delivery_delay_ms_median': statistics.median(prediction['deliveryDelaySeconds'])*1000,
              'buffered_delivery_delay_ms_p95': percentile(prediction['deliveryDelaySeconds'], .95)*1000,
              'processing_seconds': prediction['processingSeconds'],
              'limitations': 'One offline Mac recording; no device latency, room, digital-piano, pedal, key-release or general accuracy claim.'}
    args.output.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))
