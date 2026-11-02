#!/usr/bin/env python3
"""Generate ROM initialisation files for the Audio DSP project.

  mem/twiddle.mem     512 x 32 : {cos, -sin} Q1.15, W_N^k = exp(-j*2*pi*k/N), N=1024
  mem/hann.mem       1024 x 16 : Hann window, Q1.15
  mem/fir_coeffs.mem  512 x 16 : 4 filter modes x 128 taps (127 used), Q1.15
                                 mode 0 bypass, 1 LPF 3 kHz, 2 HPF 3 kHz, 3 BPF 2-5 kHz

Sample rate after the CIC decimator: 2.5 MHz / 64 = 39062.5 Hz
Pure python (no numpy needed).  Run:  python3 scripts/gen_mem.py
"""
import math, os

FS    = 2.5e6 / 64
N     = 1024
TAPS  = 127          # odd length -> type-I linear phase
M     = (TAPS - 1) // 2
OUT   = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "mem")
os.makedirs(OUT, exist_ok=True)

def q15(x):
    return max(-32768, min(32767, int(round(x * 32768))))

def h16(v):
    return "%04X" % (v & 0xFFFF)

# ---------------- twiddles ----------------
with open(os.path.join(OUT, "twiddle.mem"), "w") as f:
    for k in range(N // 2):
        a = 2 * math.pi * k / N
        f.write(h16(q15(math.cos(a))) + h16(q15(-math.sin(a))) + "\n")

# ---------------- Hann window ----------------
with open(os.path.join(OUT, "hann.mem"), "w") as f:
    for n in range(N):
        f.write(h16(q15(0.5 * (1 - math.cos(2 * math.pi * n / N)))) + "\n")

# ---------------- FIR designs (Hamming-windowed sinc) ----------------
def lpf(fc):
    h = []
    x = 2 * fc / FS
    for n in range(TAPS):
        m = n - M
        ideal = x if m == 0 else math.sin(math.pi * x * m) / (math.pi * m)
        w = 0.54 - 0.46 * math.cos(2 * math.pi * n / (TAPS - 1))
        h.append(ideal * w)
    s = sum(h)
    return [v / s for v in h]            # unity DC gain

def delta():
    return [1.0 if n == M else 0.0 for n in range(TAPS)]

bypass = delta()
low    = lpf(3000.0)
high   = [d - l for d, l in zip(delta(), lpf(3000.0))]
band   = [a - b for a, b in zip(lpf(5000.0), lpf(2000.0))]

with open(os.path.join(OUT, "fir_coeffs.mem"), "w") as f:
    for mode in (bypass, low, high, band):
        taps = [q15(v) for v in mode] + [0] * (128 - TAPS)
        for t in taps:
            f.write(h16(t) + "\n")

def mag(h, f):
    re = sum(v * math.cos(2 * math.pi * f / FS * n) for n, v in enumerate(h))
    im = sum(v * math.sin(2 * math.pi * f / FS * n) for n, v in enumerate(h))
    return 20 * math.log10(max(1e-9, math.hypot(re, im)))

print("fs = %.1f Hz, %d taps" % (FS, TAPS))
for name, h in (("LPF 3k", low), ("HPF 3k", high), ("BPF 2-5k", band)):
    print("%-9s" % name, " ".join("%gk:%+.0fdB" % (fr / 1000, mag(h, fr))
                                   for fr in (500, 1000, 2000, 3000, 4000, 6000, 10000)))
print("wrote twiddle.mem, hann.mem, fir_coeffs.mem to", os.path.abspath(OUT))
