#!/usr/bin/env python3
"""Generate placeholder audio for Pixel Blast.

These are deliberately simple chiptune-style WAVs that suit the pixel theme
and are meant to be REPLACED -- see audio/README.md. Keeping them generated
means the repo has working audio without shipping licensed assets, and the
file names double as the contract the game codes against.

Run:  python3 tools/gen_audio.py
"""
import math, os, struct, wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")

# A minor pentatonic scale reads as "game music" without needing chords.
def note(n):
    """MIDI note number -> Hz."""
    return 440.0 * (2.0 ** ((n - 69) / 12.0))


def square(t, f, duty=0.5):
    return 1.0 if (t * f) % 1.0 < duty else -1.0


def tri(t, f):
    p = (t * f) % 1.0
    return 4.0 * abs(p - 0.5) - 1.0


def noise(seed=[1]):
    # xorshift, so the same sound is produced on every run
    seed[0] ^= (seed[0] << 13) & 0xFFFFFFFF
    seed[0] ^= seed[0] >> 17
    seed[0] ^= (seed[0] << 5) & 0xFFFFFFFF
    return (seed[0] / 0x7FFFFFFF) - 1.0


def env(i, n, attack=0.01, release=0.6):
    """Simple attack/decay envelope, 0..1."""
    a = max(1, int(n * attack))
    if i < a:
        return i / a
    k = (i - a) / max(1, n - a)
    return max(0.0, (1.0 - k) ** (1.0 / release))


def write(name, samples, gain=0.5):
    path = os.path.abspath(os.path.join(OUT, name))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = max(1e-6, max(abs(s) for s in samples))
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s / peak * gain)) * 32767))
            for s in samples))
    print("  %-26s %5.2fs  %6.1f KB" % (name, len(samples) / RATE,
                                        os.path.getsize(path) / 1024))


def blip(notes, dur=0.09, wave_fn=square, duty=0.5, release=0.6):
    out = []
    for m in notes:
        n = int(RATE * dur)
        f = note(m)
        for i in range(n):
            t = i / RATE
            v = wave_fn(t, f, duty) if wave_fn is square else wave_fn(t, f)
            out.append(v * env(i, n, release=release))
    return out


def sweep(a, b, dur, wave_fn=square):
    n = int(RATE * dur)
    out, phase = [], 0.0
    for i in range(n):
        k = i / n
        f = note(a) + (note(b) - note(a)) * k
        phase += f / RATE
        v = 1.0 if phase % 1.0 < 0.5 else -1.0
        out.append(v * env(i, n))
    return out


def burst(dur, low=False):
    n = int(RATE * dur)
    out, last = [], 0.0
    for i in range(n):
        s = noise()
        if low:                      # crude low-pass for a heavier thump
            last = last * 0.86 + s * 0.14
            s = last * 3.0
        out.append(s * env(i, n, release=0.35))
    return out


def music(bars=8, bpm=104):
    """A short looping bed: pentatonic arpeggio over a simple bass."""
    beat = 60.0 / bpm
    step = beat / 2.0                       # eighth notes
    steps = bars * 8
    n = int(RATE * step * steps)
    out = [0.0] * n
    arp = [57, 60, 64, 67, 69, 67, 64, 60]  # A minor pentatonic
    bass = [33, 33, 40, 40, 36, 36, 38, 38]
    for s in range(steps):
        start = int(s * step * RATE)
        # lead
        f = note(arp[s % len(arp)] + (12 if (s // 32) % 2 else 0))
        ln = int(step * RATE * 0.9)
        for i in range(ln):
            if start + i >= n: break
            out[start + i] += square(i / RATE, f, 0.25) * env(i, ln, release=0.4) * 0.28
        # bass, on every other step
        if s % 2 == 0:
            bf = note(bass[(s // 2) % len(bass)])
            bn = int(step * RATE * 1.8)
            for i in range(bn):
                if start + i >= n: break
                out[start + i] += tri(i / RATE, bf) * env(i, bn, release=0.5) * 0.45
    return out


if __name__ == "__main__":
    print("generating audio:")
    # UI
    write("sfx/tap.wav",       blip([76], 0.05, duty=0.25), 0.35)
    write("sfx/deal.wav",      blip([72, 79], 0.045, duty=0.125), 0.30)
    # placing and clearing
    write("sfx/place.wav",     blip([69, 64], 0.055, duty=0.5), 0.40)
    write("sfx/clear.wav",     blip([72, 76, 79, 84], 0.075), 0.45)
    write("sfx/combo.wav",     blip([76, 81, 84, 88, 91], 0.07, duty=0.25), 0.50)
    # powers
    write("sfx/bomb.wav",      burst(0.55, low=True), 0.60)
    write("sfx/laser.wav",     sweep(96, 48, 0.30), 0.45)
    write("sfx/collapse.wav",  blip([72, 67, 62, 57], 0.08, wave_fn=tri), 0.45)
    write("sfx/fit.wav",       blip([64, 69, 74], 0.06, duty=0.25), 0.42)
    # run end
    write("sfx/game_over.wav", blip([69, 65, 62, 57], 0.20, wave_fn=tri, release=0.8), 0.50)
    write("music/theme.wav",   music(), 0.55)
    print("done -> audio/")
