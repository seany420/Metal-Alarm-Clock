"""Synthesizes the built-in alarm: drop-E palm-mute chugs, double kick, and a tolling bell.
Writes a 30 s mono WAV; convert to CAF with:
  ffmpeg -i riff.wav -c:a pcm_s16le ios/MetalAlarm/Resources/Sounds/bell-riff.caf
"""
import math, random, struct, sys, wave

SR = 22050
LEN = 30.0
N = int(SR * LEN)
buf = [0.0] * N
gtr = [0.0] * N

STEP = 60 / 184 / 4
NOTE = {'E': 82.41, 'F': 87.31, 'G': 98.0, 'B': 116.54}
PAT = 'ee-ee-ef' 'ee-ee-B-' 'ee-ee-ef' 'G-F-E-B-'

def saw(ph):
    return 2.0 * (ph - math.floor(ph + 0.5))

def pluck(t0, f, open_):
    dur = STEP * (1.9 if open_ else 0.85)
    s0, n = int(t0 * SR), int((dur + 0.03) * SR)
    cut = 2600 if open_ else 800
    a = 1 - math.exp(-2 * math.pi * cut / SR)
    lp = 0.0
    for i in range(n):
        k = s0 + i
        if k >= N: break
        t = i / SR
        x = sum(saw(f * r * t + d) for r, d in ((1, 0), (1.5, .13), (2, .31))) / 3
        lp += a * (x - lp)
        env = min(1, t / .004) * math.exp(-t * (4.6 / dur))
        gtr[k] += lp * env

def kick(t0):
    s0 = int(t0 * SR); ph = 0.0
    for i in range(int(.18 * SR)):
        k = s0 + i
        if k >= N: break
        t = i / SR
        f = 42 + 108 * math.exp(-t / .035)
        ph += f / SR
        buf[k] += .85 * math.sin(2 * math.pi * ph) * math.exp(-t / .045)

def snare(t0):
    s0 = int(t0 * SR); hp = 0.0; prev = 0.0
    for i in range(int(.2 * SR)):
        k = s0 + i
        if k >= N: break
        t = i / SR
        x = random.uniform(-1, 1)
        hp = .7 * (hp + x - prev); prev = x
        buf[k] += .55 * hp * math.exp(-t / .05) + .25 * math.sin(2 * math.pi * 190 * t) * math.exp(-t / .03)

def bell(t0):
    s0 = int(t0 * SR)
    parts = ((.5, .5), (1, .45), (1.19, .3), (1.5, .22), (2, .28), (2.52, .14), (3.01, .1))
    for i in range(int(4.5 * SR)):
        k = s0 + i
        if k >= N: break
        t = i / SR
        env = min(1, t / .01) * math.exp(-t / 1.1)
        buf[k] += .5 * env * sum(a * math.sin(2 * math.pi * 220 * r * t) for r, a in parts)

random.seed(666)
i, t = 0, 0.05
while t < LEN:
    ch = PAT[i % 32]
    if ch != '-':
        pluck(t, NOTE[ch.upper()], ch.isupper())
    if i % 2 == 0: kick(t)
    if i % 8 == 4: snare(t)
    if i % 64 == 0: bell(t)
    i += 1; t += STEP

out = []
for k in range(N):
    g = math.tanh(gtr[k] * 9) * .32
    v = math.tanh((buf[k] + g) * 1.2) * .9
    fade = min(1, (N - k) / (SR * .5))
    out.append(int(max(-1, min(1, v * fade)) * 32000))

with wave.open(sys.argv[1] if len(sys.argv) > 1 else 'riff.wav', 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(struct.pack('<%dh' % len(out), *out))
