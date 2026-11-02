"""공부 타이머의 공부 소리(ASMR) 3개를 (2026-11-02, 결정 D-59) 직접 만든다 — 내려받은 파일이 아니라 잡음을 걸러 만든 소리 (저작권 · 다운로드 없음).
20초, 22.05kHz 모노 → 끝 0.8초를 처음과 겹쳐(크로스페이드) 반복해도 이음매가 안 들리게 → ffmpeg로 mp3.
"""
import os
import subprocess
import wave

import numpy as np

SR = 22050
SEC = 20
# 실행: frontend/ 에서 `python tool/make_asmr.py` (numpy · imageio-ffmpeg 필요). 시드가 고정이라 매번 같은 소리.
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'audio', 'bgm')
try:
    import imageio_ffmpeg

    FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
except ImportError:
    FFMPEG = 'ffmpeg'
rng = np.random.default_rng(7)
N = SR * SEC
t = np.arange(N) / SR


def lowpass(x, a):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        y[i] = acc
    return y


def onepole_hp(x, a):
    return x - lowpass(x, a)


def brown(n):
    w = rng.standard_normal(n)
    b = np.cumsum(w)
    b -= lowpass(b, 0.002)  # 아주 느린 흐름 빼기
    return b / (np.abs(b).max() + 1e-9)


def env(n, attack, release):
    e = np.ones(n)
    a = int(attack * SR)
    r = int(release * SR)
    if a:
        e[:a] = np.linspace(0, 1, a)
    if r:
        e[-r:] = np.linspace(1, 0, r)
    return e


def loopify(x, fade=0.8):
    f = int(fade * SR)
    head = x[:f].copy()
    body = x[f:].copy()
    ramp = np.linspace(0, 1, f)
    body[-f:] = body[-f:] * (1 - ramp) + head * ramp
    return body


def rain():
    w = rng.standard_normal(N)
    hiss = onepole_hp(lowpass(w, 0.55), 0.08) * 0.22
    # 크고 작은 빗방울 (짧은 딸깍)
    drops = np.zeros(N)
    for _ in range(SEC * 70):
        i = rng.integers(0, N - 400)
        ln = rng.integers(60, 260)
        drops[i:i + ln] += rng.standard_normal(ln) * np.exp(-np.linspace(0, 6, ln)) * rng.uniform(0.05, 0.25)
    drops = onepole_hp(drops, 0.2)
    swell = 0.85 + 0.15 * np.sin(2 * np.pi * t / 7.3)
    return (hiss + drops * 0.6) * swell


def pencil():
    bed = brown(N) * 0.05  # 방 공기
    strokes = np.zeros(N)
    i = int(0.3 * SR)
    while i < N - SR:
        ln = int(rng.uniform(0.12, 0.38) * SR)
        g = rng.standard_normal(ln)
        g = onepole_hp(lowpass(g, 0.75), 0.35)  # 종이 긁는 높은 소리
        wob = 0.6 + 0.4 * np.abs(np.sin(np.linspace(0, rng.uniform(3, 9) * np.pi, ln)))
        strokes[i:i + ln] += g * env(ln, 0.02, 0.06) * wob * rng.uniform(0.18, 0.32)
        i += ln + int(rng.uniform(0.08, 0.6) * SR)
        if rng.random() < 0.06:  # 가끔 쉬는 틈
            i += int(rng.uniform(0.8, 1.8) * SR)
    return bed + strokes


def cafe():
    rumble = lowpass(brown(N), 0.05) * 0.35
    murmur = rng.standard_normal(N)
    murmur = onepole_hp(lowpass(murmur, 0.12), 0.02)
    am = 0.5 + 0.5 * np.abs(np.sin(2 * np.pi * t * 0.9) * np.sin(2 * np.pi * t * 0.31 + 1))
    voices = murmur * am * 0.5
    clinks = np.zeros(N)
    for _ in range(9):
        i = rng.integers(0, N - SR)
        ln = int(0.5 * SR)
        f = rng.uniform(1800, 3200)
        k = np.arange(ln) / SR
        clinks[i:i + ln] += np.sin(2 * np.pi * f * k) * np.exp(-k * 14) * 0.08
    return rumble + voices + clinks


def save(name, x):
    x = loopify(x)
    x = x / (np.abs(x).max() + 1e-9) * 0.6
    wav = os.path.join(OUT, name + '.wav')
    with wave.open(wav, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    mp3 = os.path.join(OUT, name + '.mp3')
    subprocess.run([FFMPEG, '-y', '-loglevel', 'error', '-i', wav, '-b:a', '64k', mp3], check=True)
    os.remove(wav)
    print(name, os.path.getsize(mp3))


save('studyRain', rain())
save('studyPencil', pencil())
save('studyCafe', cafe())
