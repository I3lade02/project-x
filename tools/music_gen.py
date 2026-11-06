"""
OVERCLOCK – synthwave / darksynth hudba pro project-x.
Vše je syntéza v numpy/scipy (žádné samply). Výstup: bezešvé smyčky (stemy) pro adaptivní hudbu.
  combat_*.ogg  (120 BPM, 32 taktů = 64 s): pad, bass, drums, arp, lead, heat
  boss_*.ogg    (128 BPM, 32 taktů = 60 s): pad, bass, drums, arp, lead
  menu.ogg      (100 BPM, 16 taktů = 38,4 s): celý mix
Použití: python3 music.py <výstupní složka> [--preview]
"""
import sys, os, subprocess
import numpy as np
from scipy import signal

SR = 44100
TAIL = 6.0
rng = np.random.default_rng(1984)


def hz(m):
    return 440.0 * 2.0 ** ((np.asarray(m, dtype=float) - 69.0) / 12.0)


# ------------------------------------------------------------------ oscilátory (polyBLEP)
def _blep(ph, dt):
    out = np.zeros_like(ph)
    m = ph < dt
    x = ph[m] / dt[m]
    out[m] = x + x - x * x - 1.0
    m = ph > 1.0 - dt
    x = (ph[m] - 1.0) / dt[m]
    out[m] = x * x + x + x + 1.0
    return out


def _phase(freq, n, ph0):
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    dt = f / SR
    return (ph0 + np.cumsum(dt)) % 1.0, dt


def saw(freq, n, ph0=None):
    ph, dt = _phase(freq, n, rng.random() if ph0 is None else ph0)
    return 2.0 * ph - 1.0 - _blep(ph, dt)


def square(freq, n, pw=0.5, ph0=None):
    ph, dt = _phase(freq, n, rng.random() if ph0 is None else ph0)
    s = np.where(ph < pw, 1.0, -1.0)
    return s + _blep(ph, dt) - _blep((ph + 1.0 - pw) % 1.0, dt)


def sine(freq, n, ph0=0.0):
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    return np.sin(2 * np.pi * (ph0 + np.cumsum(f) / SR))


def noise(n):
    return rng.standard_normal(n)


# ------------------------------------------------------------------ obálky a filtry
def adsr(gate_n, a, d, s, r):
    A, D, R = max(1, int(a * SR)), max(1, int(d * SR)), max(1, int(r * SR))
    e = np.full(gate_n, s, dtype=float)
    k = min(A, gate_n)
    e[:k] = np.linspace(0, 1, A)[:k]
    if gate_n > A:
        k2 = min(D, gate_n - A)
        e[A:A + k2] = np.linspace(1, s, D)[:k2]
    last = e[-1] if gate_n > 0 else 0.0
    return np.concatenate([e, np.linspace(last, 0, R)])


def exp_env(n, decay):
    return np.exp(-np.arange(n) / (decay * SR))


def sos(kind, f, order=2):
    return signal.butter(order, f, kind, fs=SR, output="sos")


def filt(x, kind, f, order=2):
    return signal.sosfilt(sos(kind, f, order), x, axis=0)


def _biquad_lp(fc, q):
    w0 = 2 * np.pi * fc / SR
    al = np.sin(w0) / (2 * q)
    c = np.cos(w0)
    a0 = 1 + al
    return np.array([(1 - c) / 2, 1 - c, (1 - c) / 2]) / a0, np.array([1, -2 * c / a0, (1 - al) / a0])


def lp_sweep(x, fc, q=0.8, block=32):
    """lowpass s proměnnou frekvencí (fc = pole stejné délky jako x)"""
    fc = np.broadcast_to(np.asarray(fc, dtype=float), x.shape[:1])
    y = np.empty_like(x)
    zi = np.zeros(2)
    for i in range(0, len(x), block):
        b, a = _biquad_lp(float(np.clip(fc[i], 30, SR * 0.45)), q)
        y[i:i + block], zi = signal.lfilter(b, a, x[i:i + block], zi=zi)
    return y


def st(x, pan=0.0):
    """mono -> stereo s panoramou (-1..1)"""
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    return np.stack([x * l, x * r], axis=1) * 1.414


# ------------------------------------------------------------------ efekty
def make_ir(decay, damp=5500, seed=7, pre=0.012):
    n = int(decay * 1.3 * SR)
    t = np.arange(n) / SR
    r = np.random.default_rng(seed)
    ir = r.standard_normal((n, 2)) * np.exp(-6.9 * t / decay)[:, None]
    ir = signal.sosfilt(sos("low", damp), ir, axis=0)
    fade = int(0.004 * SR)
    ir[:fade] *= np.linspace(0, 1, fade)[:, None]
    ir = np.concatenate([np.zeros((int(pre * SR), 2)), ir])
    return ir / np.sqrt(np.sum(ir ** 2, axis=0))


def reverb(x, ir, wet):
    y = np.stack([signal.fftconvolve(x[:, c], ir[:, c])[:len(x)] for c in range(2)], axis=1)
    return x + wet * y


def pingpong(x, t, fb, wet, damp=4500):
    d = int(t * SR)
    m = x.mean(axis=1)
    y = np.zeros_like(x)
    g = wet
    k = 1
    while g > 0.01 and d * k < len(x):
        sh = d * k
        y[sh:, k % 2] += m[:-sh] * g
        g *= fb
        k += 1
    return x + filt(y, "low", damp)


def pump(n, beat_times, depth, rel, att=0.004):
    """sidechain „pumpování“ podle kopáku (n = délka smyčky; náběh před úderem se přetáčí přes konec)"""
    g = np.ones(n)
    L = int(rel * SR)
    A = int(att * SR)
    seg = 1 - depth * (1 - np.linspace(0, 1, L) ** 1.6)
    pre = 1 - depth * np.linspace(0, 1, A)
    for bt in beat_times:
        i = int(bt * SR)
        if i >= n:
            continue
        k = min(L, n - i)
        g[i:i + k] = np.minimum(g[i:i + k], seg[:k])
        idx = (np.arange(i - A, i)) % n
        g[idx] = np.minimum(g[idx], pre)
    return g[:, None]


def soft(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


# ------------------------------------------------------------------ nástroje
def pad_note(m, dur, cutoff=1800, att=0.25, rel=0.7, voices=3, det=0.09):
    n = int(dur * SR)
    e = adsr(n, att, 0.4, 0.8, rel)
    N = len(e)
    sig = np.zeros((N, 2))
    for v in range(voices):
        d = (v - (voices - 1) / 2) * det
        f = hz(m + d)
        s = saw(f, N)
        pan = -0.7 + 1.4 * v / max(1, voices - 1)
        sig += st(s, pan)
    sig = filt(sig, "low", cutoff)
    return sig * e[:, None] / voices


def bass_note(m, dur, peak=2400, floor=260, dec=0.09, q=1.4, sub=0.6):
    n = int(dur * SR)
    e = adsr(n, 0.002, 0.08, 0.75, 0.03)
    N = len(e)
    f = hz(m)
    s = saw(f, N) * 0.7 + square(f * 0.5, N) * 0.3 * sub
    fc = floor + (peak - floor) * exp_env(N, dec)
    s = lp_sweep(s, fc, q)
    return st(s * e)


def pluck(m, dur, pw=0.3, decay=0.14, cutoff=3800, sq=1.0):
    n = int(dur * SR)
    N = n + int(0.05 * SR)
    f = hz(m)
    s = square(f, N, pw) * sq + saw(f * 1.003, N) * (1 - sq)
    e = exp_env(N, decay)
    e[:40] *= np.linspace(0, 1, 40)
    s = filt(s * e, "low", cutoff)
    return s


def lead_note(m, dur, cutoff=3600, vib=0.15, drive=1.0, glide_from=None):
    n = int(dur * SR)
    e = adsr(n, 0.008, 0.25, 0.75, 0.18)
    N = len(e)
    t = np.arange(N) / SR
    vdepth = np.clip((t - vib) / 0.25, 0, 1) * 0.16          # vibrato po chvíli
    pitch = m + vdepth * np.sin(2 * np.pi * 5.6 * t)
    if glide_from is not None:
        g = np.clip(t / 0.05, 0, 1)
        pitch = glide_from + (pitch - glide_from) * g
    a = saw(hz(pitch + 0.08), N)
    b = saw(hz(pitch - 0.08), N)
    c = square(hz(pitch - 12), N, 0.5) * 0.35
    s = filt(np.stack([a + c, b + c], axis=1) * 0.5, "low", cutoff)
    if drive > 1.0:
        s = soft(s, drive)
    return s * e[:, None]


def reese(m, dur, lfo_rate, drive=3.0):
    n = int(dur * SR)
    e = adsr(n, 0.01, 0.1, 0.9, 0.08)
    N = len(e)
    t = np.arange(N) / SR
    s = saw(hz(m + 0.14), N) + saw(hz(m - 0.14), N) + 0.6 * square(hz(m - 12), N)
    fc = 350 + 1300 * (0.5 - 0.5 * np.cos(2 * np.pi * lfo_rate * t))
    s = lp_sweep(s * 0.4, fc, 2.0)
    return st(soft(s * e, drive))


# ------------------------------------------------------------------ bicí (připravené vzorky)
def kick(punch=1.0):
    N = int(0.45 * SR)
    t = np.arange(N) / SR
    f = 46 + 110 * np.exp(-t / 0.035) * punch
    s = sine(f, N) * np.exp(-t / 0.22)
    click = filt(noise(N) * np.exp(-t / 0.004), "high", 1800) * 0.35
    return soft((s + click) * 1.4, 1.6)


def snare(gate=0.32, ir=None):
    N = int(0.5 * SR)
    t = np.arange(N) / SR
    tone = sine(185 * (1 + 0.4 * np.exp(-t / 0.01)), N) * np.exp(-t / 0.07) * 0.6
    nz = filt(noise(N), "band", [1200, 7000]) * np.exp(-t / 0.15)
    s = st(tone + nz * 0.9)
    if ir is not None:                      # „gated reverb“ – zvuk 80. let
        s = reverb(np.concatenate([s, np.zeros((int(0.6 * SR), 2))]), ir, 1.3)
        n2 = len(s)
        g = np.ones(n2)
        gi = int(gate * SR)
        g[gi:] = 0
        g[gi:gi + int(0.03 * SR)] = np.linspace(1, 0, int(0.03 * SR))
        s = s * g[:, None]
    return s * 0.8


def hat(open_=False):
    N = int((0.35 if open_ else 0.06) * SR)
    t = np.arange(N) / SR
    s = filt(noise(N), "high", 7500) * np.exp(-t / (0.11 if open_ else 0.018))
    return s * 0.5


def crash():
    N = int(2.2 * SR)
    t = np.arange(N) / SR
    metal = sum(square(f, N, 0.5) for f in (387, 563, 812, 1143, 1567)) * 0.15
    s = filt(noise(N) * 0.8 + metal, "high", 4000) * np.exp(-t / 0.7)
    return st(s * 0.5, -0.3)


def tom(f0):
    N = int(0.4 * SR)
    t = np.arange(N) / SR
    s = sine(f0 * (1 + 0.6 * np.exp(-t / 0.04)), N) * np.exp(-t / 0.18)
    return s * 0.9


# ------------------------------------------------------------------ pomocné pro skladbu
class Track:
    def __init__(s, bpm, bars):
        s.bpm = bpm
        s.bars = bars
        s.step = 60.0 / bpm / 4          # šestnáctina
        s.bar = s.step * 16
        s.L = int(round(bars * s.bar * SR))
        s.N = s.L + int(TAIL * SR)

    def buf(s):
        return np.zeros((s.N, 2))

    def t(s, bar, step=0):
        return bar * s.bar + step * s.step

    def kicks(s, steps=(0, 4, 8, 12)):
        return [s.t(b, k) for b in range(s.bars) for k in steps]

    def wrap(s, b):
        out = b[:s.L].copy()
        out[:s.N - s.L] += b[s.L:]
        return out


def place(buf, t, x, gain=1.0, pan=0.0):
    if x.ndim == 1:
        x = st(x, pan)
    i = int(round(t * SR))
    n = min(len(x), len(buf) - i)
    if n > 0:
        buf[i:i + n] += x[:n] * gain


# ======================================================================
#  BOJ – 120 BPM, A moll: Am F C G | Am F G E
# ======================================================================
def combat():
    T = Track(120, 32)
    CH = [(33, [57, 60, 64, 69]), (29, [57, 60, 65, 69]), (36, [55, 60, 64, 67]), (31, [55, 59, 62, 67]),
          (33, [57, 60, 64, 69]), (29, [57, 60, 65, 69]), (31, [55, 59, 62, 67]), (28, [56, 59, 64, 68])]
    chord_at = lambda bar: CH[(bar // 2) % 8]
    stems = {}
    kick_times = T.kicks()

    # --- PAD
    b = T.buf()
    for bar in range(0, T.bars, 2):
        root, v = chord_at(bar)
        for m in v:
            place(b, T.t(bar), pad_note(m, T.bar * 2 - 0.05, cutoff=1900), 0.32)
    b = filt(b, "high", 180)
    b = reverb(b, make_ir(2.6, 5000, 3), 0.35)
    stems["pad"] = T.wrap(b) * pump(T.L, kick_times, 0.55, T.step * 3.2)

    # --- BASA (šestnáctinový „gallop“ s oktávou)
    b = T.buf()
    pat = [0, 0, 12, 0]
    for bar in range(T.bars):
        root, _ = chord_at(bar)
        for k in range(16):
            acc = 1.0 if k % 4 == 0 else 0.78
            place(b, T.t(bar, k), bass_note(root + pat[k % 4], T.step * 0.85), 0.55 * acc)
    stems["bass"] = T.wrap(b) * pump(T.L, kick_times, 0.3, T.step * 2.2)

    # --- BICÍ
    b = T.buf()
    K, SN, HC, HO, CR = kick(), snare(0.34, make_ir(1.4, 7000, 11)), hat(), hat(True), crash()
    for bar in range(T.bars):
        fill = bar % 8 == 7
        for k in (0, 4, 8, 12):
            place(b, T.t(bar, k), K, 0.95)
        for k in (4, 12):
            if not (fill and k == 12):
                place(b, T.t(bar, k), SN, 0.62)
        for k in range(16):
            if k == 14:
                place(b, T.t(bar, k), HO, 0.32, 0.3)
            elif not (fill and k >= 12):
                place(b, T.t(bar, k), HC, 0.30 if k % 4 == 2 else 0.15, 0.25)
        if fill:                                   # přechod do další osmice
            for i, k in enumerate((12, 13, 14, 15)):
                place(b, T.t(bar, k), tom([170, 140, 115, 90][i]), 0.55, [-0.4, -0.1, 0.2, 0.45][i])
            place(b, T.t(bar, 15), SN, 0.35)
        if bar % 8 == 0:
            place(b, T.t(bar), CR, 0.55)
    stems["drums"] = T.wrap(reverb(b, make_ir(0.9, 6000, 5), 0.10))

    # --- ARPEGGIO
    b = T.buf()
    for bar in range(T.bars):
        root, v = chord_at(bar)
        notes = [m + 12 for m in v]
        pat = [0, 1, 2, 3] if bar < 16 else [0, 1, 2, 3, 2, 1]
        for k in range(16):
            gidx = bar * 16 + k
            m = notes[pat[gidx % len(pat)]]
            place(b, T.t(bar, k), pluck(m, T.step * 0.9, 0.28, 0.12, 4200), 0.20, 0.25 if k % 2 else -0.25)
    b = pingpong(b, T.step * 3, 0.42, 0.45)
    b = reverb(b, make_ir(1.8, 6000, 9), 0.2)
    stems["arp"] = T.wrap(b) * pump(T.L, kick_times, 0.25, T.step * 2)

    # --- LEAD (melodie, ve 2. půlce zdvojená o oktávu níž)
    MEL = [
        [(0, 6, 76), (6, 2, 74), (8, 4, 72), (12, 4, 74), (16, 12, 76), (28, 4, 79)],
        [(0, 6, 77), (6, 2, 76), (8, 4, 74), (12, 4, 72), (16, 12, 72), (28, 4, 69)],
        [(0, 6, 72), (6, 2, 74), (8, 4, 76), (12, 4, 79), (16, 12, 79), (28, 4, 76)],
        [(0, 6, 74), (6, 2, 72), (8, 8, 71), (16, 16, 74)],
        [(0, 6, 76), (6, 2, 74), (8, 4, 72), (12, 4, 74), (16, 8, 76), (24, 4, 81), (28, 4, 79)],
        [(0, 8, 77), (8, 4, 76), (12, 4, 77), (16, 12, 81), (28, 4, 79)],
        [(0, 6, 79), (6, 2, 77), (8, 8, 76), (16, 8, 74), (24, 8, 71)],
        [(0, 16, 68), (16, 8, 71), (24, 8, 76)],
    ]
    b = T.buf()
    for cyc in range(2):
        prev = None
        for seg, notes in enumerate(MEL):
            bar0 = cyc * 16 + seg * 2
            for (s0, ln, m) in notes:
                t0 = T.t(bar0, s0)
                x = lead_note(m, ln * T.step * 0.95, 3800, glide_from=prev if (prev is not None and abs(prev - m) <= 5) else None)
                place(b, t0, x, 0.22)
                if cyc == 1:
                    place(b, t0, lead_note(m - 12, ln * T.step * 0.95, 2600), 0.13)
                prev = m
    b = pingpong(b, T.step * 3, 0.35, 0.3)
    b = reverb(b, make_ir(2.2, 5500, 13), 0.28)
    stems["lead"] = T.wrap(b)

    # --- PŘEHŘÁTÍ (zkreslená basa + „alarm“ + ruch nahoru po 4 taktech)
    b = T.buf()
    for bar in range(0, T.bars, 2):
        root, v = chord_at(bar)
        place(b, T.t(bar), reese(root + 12, T.bar * 2 - 0.02, 2.0 * 120 / 60 / 2), 0.32)
    for bar in range(T.bars):
        root, v = chord_at(bar)
        for k in (0, 8):
            n = int(T.step * 3 * SR)
            tt = np.arange(n) / SR
            f = hz(v[-1] + 12) * (1 - 0.12 * tt / (T.step * 3))
            beep = square(f, n, 0.5) * exp_env(n, 0.12)
            place(b, T.t(bar, k), filt(beep, "low", 5000), 0.07, 0.5 if k else -0.5)
    for bar in range(0, T.bars, 4):
        n = int(T.bar * 4 * SR)
        tt = np.linspace(0, 1, n)
        nz = lp_sweep(noise(n), 400 + 7000 * tt ** 2, 1.5, 256) * tt ** 2
        place(b, T.t(bar), st(nz * 0.5), 0.18)
    stems["heat"] = T.wrap(b) * pump(T.L, kick_times, 0.5, T.step * 2.5)
    return T, stems


# ======================================================================
#  BOSS – 128 BPM, frygické A: Am Bb Am G | Am Bb C E
# ======================================================================
def boss():
    T = Track(128, 32)
    CH = [(33, [57, 60, 64, 69]), (34, [58, 62, 65, 70]), (33, [57, 60, 64, 69]), (31, [55, 59, 62, 67]),
          (33, [57, 60, 64, 69]), (34, [58, 62, 65, 70]), (36, [55, 60, 64, 67]), (28, [56, 59, 64, 68])]
    chord_at = lambda bar: CH[(bar // 2) % 8]
    stems = {}
    kick_steps = (0, 4, 8, 10, 12)
    kick_times = T.kicks(kick_steps)

    # --- PAD (trance gate)
    gate = [1, 0, 1, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1]
    b = T.buf()
    for bar in range(0, T.bars, 2):
        root, v = chord_at(bar)
        for m in v:
            place(b, T.t(bar), pad_note(m - 12, T.bar * 2 - 0.03, cutoff=1400, att=0.02, rel=0.2, voices=3, det=0.12), 0.34)
            place(b, T.t(bar), pad_note(m, T.bar * 2 - 0.03, cutoff=2400, att=0.02, rel=0.2, voices=2, det=0.1), 0.18)
    g = np.ones(T.N)
    for bar in range(T.bars + 1):
        for k in range(16):
            i0 = int(T.t(bar, k) * SR)
            i1 = int(T.t(bar, k + 0.75) * SR)
            if i0 < T.N and gate[k] == 0:
                g[i0:min(i1, T.N)] = 0.08
    so = sos("low", 120)
    g, _ = signal.sosfilt(so, g, zi=signal.sosfilt_zi(so) * g[0])
    b = filt(b * g[:, None], "high", 140)
    b = reverb(b, make_ir(1.6, 4500, 21), 0.25)
    stems["pad"] = T.wrap(b)

    # --- BASA (zkreslený gallop)
    b = T.buf()
    pat = [0, 0, 12, 0]
    for bar in range(T.bars):
        root, _ = chord_at(bar)
        for k in range(16):
            acc = 1.0 if k % 4 == 0 else 0.8
            x = bass_note(root + pat[k % 4], T.step * 0.8, peak=3200, floor=300, dec=0.07, q=1.8)
            place(b, T.t(bar, k), soft(x * 1.5, 2.2), 0.42 * acc)
    stems["bass"] = T.wrap(b) * pump(T.L, kick_times, 0.25, T.step * 1.8)

    # --- BICÍ (tvrdší, synkopovaný kopák, tomy)
    b = T.buf()
    K, SN, HC, HO, CR = kick(1.3), snare(0.3, make_ir(1.2, 7000, 23)), hat(), hat(True), crash()
    for bar in range(T.bars):
        fill = bar % 4 == 3
        for k in kick_steps:
            place(b, T.t(bar, k), K, 1.0 if k != 10 else 0.75)
        for k in (4, 12):
            if not (fill and k == 12):
                place(b, T.t(bar, k), SN, 0.65)
        for k in range(16):
            if fill and k >= 12:
                continue
            place(b, T.t(bar, k), HO if k % 8 == 6 else HC, 0.28 if k % 2 == 0 else 0.18, 0.3)
        if fill:
            for i, k in enumerate((12, 13, 14, 15)):
                place(b, T.t(bar, k), tom([190, 150, 120, 95][i]), 0.6, [-0.5, -0.15, 0.2, 0.5][i])
            place(b, T.t(bar, 14), K, 0.7)
            place(b, T.t(bar, 15), SN, 0.4)
        if bar % 8 == 0:
            place(b, T.t(bar), CR, 0.6)
    stems["drums"] = T.wrap(soft(reverb(b, make_ir(0.8, 6000, 25), 0.08), 1.3))

    # --- ARPEGGIO
    b = T.buf()
    for bar in range(T.bars):
        root, v = chord_at(bar)
        notes = [m + 12 for m in v] + [v[1] + 24]
        pat = [0, 2, 1, 3, 2, 4, 3, 1]
        for k in range(16):
            m = notes[pat[(bar * 16 + k) % len(pat)]]
            place(b, T.t(bar, k), pluck(m, T.step * 0.8, 0.5, 0.09, 5000, sq=0.6), 0.18, 0.3 if k % 2 else -0.3)
    b = pingpong(b, T.step * 2, 0.4, 0.4)
    stems["arp"] = T.wrap(b) * pump(T.L, kick_times, 0.3, T.step * 1.6)

    # --- LEAD (agresivní riff)
    MEL = [
        [(0, 2, 76), (2, 2, 77), (4, 4, 76), (8, 2, 74), (10, 2, 72), (12, 4, 71), (16, 4, 69), (20, 4, 72), (24, 8, 76)],
        [(0, 2, 77), (2, 2, 79), (4, 4, 77), (8, 2, 74), (10, 2, 77), (12, 4, 82), (16, 12, 81), (28, 4, 79)],
        [(0, 2, 76), (2, 2, 77), (4, 4, 76), (8, 2, 74), (10, 2, 72), (12, 4, 71), (16, 4, 69), (20, 4, 72), (24, 8, 76)],
        [(0, 4, 79), (4, 4, 77), (8, 4, 74), (12, 4, 71), (16, 16, 74)],
        [(0, 2, 76), (2, 2, 77), (4, 4, 76), (8, 2, 74), (10, 2, 72), (12, 4, 71), (16, 4, 69), (20, 4, 72), (24, 8, 76)],
        [(0, 2, 77), (2, 2, 79), (4, 4, 77), (8, 2, 74), (10, 2, 77), (12, 4, 82), (16, 12, 81), (28, 4, 79)],
        [(0, 4, 79), (4, 4, 76), (8, 4, 72), (12, 4, 76), (16, 8, 79), (24, 8, 84)],
        [(0, 8, 80), (8, 8, 76), (16, 8, 71), (24, 8, 68)],
    ]
    b = T.buf()
    for cyc in range(2):
        prev = None
        for seg, notes in enumerate(MEL):
            bar0 = cyc * 16 + seg * 2
            for (s0, ln, m) in notes:
                gl = prev if (prev is not None and abs(prev - m) <= 4) else None
                place(b, T.t(bar0, s0), lead_note(m, ln * T.step * 0.92, 4200, 0.1, 1.8, gl), 0.2)
                place(b, T.t(bar0, s0), lead_note(m + 12, ln * T.step * 0.92, 5000, 0.1, 1.5, None), 0.07 if cyc else 0.0)
                prev = m
    b = pingpong(b, T.step * 3, 0.3, 0.28)
    b = reverb(b, make_ir(1.8, 5500, 27), 0.22)
    stems["lead"] = T.wrap(b)
    return T, stems


# ======================================================================
#  MENU – 100 BPM, klidnější synthwave: Am F C G | Dm F G E
# ======================================================================
def menu():
    T = Track(100, 16)
    CH = [(33, [57, 60, 64, 69]), (29, [57, 60, 65, 69]), (36, [55, 60, 64, 67]), (31, [55, 59, 62, 67]),
          (38, [57, 62, 65, 69]), (29, [57, 60, 65, 69]), (31, [55, 59, 62, 67]), (28, [56, 59, 64, 68])]
    chord_at = lambda bar: CH[(bar // 2) % 8]
    mix = T.buf()
    half_kicks = [T.t(b, k) for b in range(T.bars) for k in (0, 8)]

    pad = T.buf()
    for bar in range(0, T.bars, 2):
        root, v = chord_at(bar)
        for m in v:
            place(pad, T.t(bar), pad_note(m, T.bar * 2 - 0.05, cutoff=1500, att=0.6, rel=1.2), 0.34)
    pad = reverb(filt(pad, "high", 150), make_ir(3.5, 4000, 31), 0.45)

    bass = T.buf()
    for bar in range(T.bars):
        root, _ = chord_at(bar)
        for k in range(0, 16, 2):
            place(bass, T.t(bar, k), bass_note(root + (12 if k % 8 == 6 else 0), T.step * 1.7, 1300, 200, 0.12, 1.0), 0.5)

    arp = T.buf()
    for bar in range(T.bars):
        root, v = chord_at(bar)
        notes = [m + 12 for m in v]
        for k in range(0, 16, 2):
            m = notes[[0, 1, 2, 3, 2, 1, 2, 3][(k // 2) % 8]]
            place(arp, T.t(bar, k), pluck(m, T.step * 1.8, 0.4, 0.22, 3000, sq=0.7), 0.17, 0.3 if k % 4 else -0.3)
    arp = reverb(pingpong(arp, T.step * 3, 0.45, 0.45, 3500), make_ir(2.5, 5000, 33), 0.3)

    drums = T.buf()
    K, SN, HC = kick(0.8), snare(0.4, make_ir(1.8, 6000, 35)), hat()
    for bar in range(4, T.bars):
        place(drums, T.t(bar, 0), K, 0.75)
        place(drums, T.t(bar, 10), K, 0.45)
        place(drums, T.t(bar, 8), SN, 0.42)
        for k in range(2, 16, 4):
            place(drums, T.t(bar, k), HC, 0.16, 0.25)

    lead = T.buf()
    MEL = [
        [(0, 8, 74), (8, 4, 72), (12, 4, 69), (16, 16, 74)],
        [(0, 8, 72), (8, 8, 69), (16, 16, 65)],
        [(0, 8, 71), (8, 8, 74), (16, 16, 79)],
        [(0, 16, 76), (16, 16, 80)],
    ]
    for seg, notes in enumerate(MEL):
        for (s0, ln, m) in notes:
            x = pluck(m, ln * T.step, 0.5, 0.6, 2600, sq=0.5)
            place(lead, T.t(8 + seg * 2, s0), st(x), 0.2)
    lead = reverb(pingpong(lead, T.step * 6, 0.4, 0.4, 3000), make_ir(3.0, 4500, 37), 0.4)

    p = pump(T.L, half_kicks, 0.35, T.step * 4)
    return T, {"pad": T.wrap(pad) * p, "bass": T.wrap(bass) * p, "arp": T.wrap(arp),
               "drums": T.wrap(drums), "lead": T.wrap(lead)}


# ------------------------------------------------------------------ výstup
def write(path, x, preview=False):
    x = np.clip(x, -1, 1)
    pcm = (x * 32767).astype("<i2").tobytes()
    fmt = ["-c:a", "libmp3lame", "-b:a", "160k"] if preview else ["-c:a", "libvorbis", "-q:a", "5"]
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-"] + fmt + [path],
                   input=pcm, check=True)


# vnímaná hlasitost ~ RMS bez nejhlubších basů
def loudness(x):
    return float(np.sqrt(np.mean(filt(x, "high", 120) ** 2)) + 1e-9)


# poměry hlasitostí jednotlivých vrstev (bicí = 1)
MIX = {
    "combat": {"drums": 1.0, "bass": 0.72, "pad": 0.5, "arp": 0.42, "lead": 0.62, "heat": 0.5},
    "boss": {"drums": 1.0, "bass": 0.78, "pad": 0.55, "arp": 0.42, "lead": 0.62},
    "menu": {"drums": 0.55, "bass": 0.5, "pad": 0.75, "arp": 0.55, "lead": 0.6},
}


def mix_stems(name, stems):
    if "drums" in stems:                       # zkrotit špičky kopáku
        d = stems["drums"]
        stems["drums"] = soft(d / np.max(np.abs(d)), 1.8)
    ref = loudness(stems["drums"])
    return {n: x * (MIX[name][n] * ref / loudness(x)) for n, x in stems.items()}


def normalize_group(stems, peak=0.89):
    total = sum(stems.values())
    k = peak / max(1e-6, np.max(np.abs(total)))
    return {n: s * k for n, s in stems.items()}, k


# náhled: stemy zapínané postupně (jak to bude znít ve hře)
def demo(T, stems, plan):
    out = np.zeros((T.L, 2))
    for n, x in stems.items():
        g = np.zeros(T.L)
        for (b0, b1, v) in plan.get(n, []):
            g[int(T.t(b0) * SR):int(T.t(b1) * SR)] = v
        g = signal.sosfilt(sos("low", 2), g)            # plynulé náběhy (~0,5 s)
        out += x * g[:, None]
    return out


DEMO = {
    "combat": {"pad": [(0, 32, 1)], "bass": [(0, 4, 0.4), (4, 32, 1)], "arp": [(0, 4, 0.35), (4, 32, 1)],
               "drums": [(4, 32, 1)], "lead": [(12, 32, 1)], "heat": [(26, 32, 1)]},
    "boss": {"pad": [(0, 32, 1)], "bass": [(0, 32, 1)], "drums": [(0, 32, 1)], "arp": [(8, 32, 1)], "lead": [(16, 32, 1)]},
}


if __name__ == "__main__":
    out = sys.argv[1]
    prev = "--preview" in sys.argv
    os.makedirs(out, exist_ok=True)
    for name, fn in (("combat", combat), ("boss", boss), ("menu", menu)):
        T, stems = fn()
        stems = mix_stems(name, stems)
        if name == "menu":
            stems = {"menu": sum(stems.values())}
        stems, k = normalize_group(stems)
        for n, s in stems.items():
            fn_out = f"{out}/{n}.ogg" if name == "menu" else f"{out}/{name}_{n}.ogg"
            write(fn_out, s)
            print(f"{fn_out}: {len(s) / SR:.2f}s ({len(s)} vzorků) peak={np.max(np.abs(s)):.2f} rms={np.sqrt(np.mean(s ** 2)):.3f}")
        if prev:
            mixd = demo(T, stems, DEMO[name]) if name in DEMO else stems["menu"]
            write(f"{out}/preview_{name}.mp3", mixd, preview=True)
        print(name, "gain", round(k, 3))
