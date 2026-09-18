"""Synthesises every sound effect in the game (no binary audio dependencies).

`python3 tools/gen_assets.py sounds` writes 22 kHz mono WAVs into
`assets/audio/`. Sounds are intentionally short (< 1.5 s) so the whole audio
set stays a few hundred kilobytes and loads instantly on mobile.
"""

from __future__ import annotations

import math
import random

from pixelart import Sound, chord, noise_burst, sequence, tone


def _step_like(seed: int, cutoff: float, decay: float, length: float = 0.16) -> Sound:
    """Footstep / dig noise: a filtered noise burst with a woody body."""
    burst = noise_burst(length, seed)
    burst.lowpass(cutoff, passes=2)
    burst.envelope(0.001, decay, curve=6.0)
    body = tone(160.0, length, "sine", freq_end=90.0)
    body.envelope(0.001, decay * 0.8, curve=7.0)
    burst.mix_into(burst, 0.0, 1.0)
    out = Sound(length)
    out.mix_into(burst, 0.0, 0.85)
    out.mix_into(body, 0.0, 0.25)
    return out.fade_out(0.02)


def sfx_step_stone() -> Sound:
    return _step_like(1, 1800.0, 0.06)


def sfx_step_dirt() -> Sound:
    return _step_like(2, 900.0, 0.09)


def sfx_step_grass() -> Sound:
    return _step_like(3, 2600.0, 0.05)


def sfx_step_sand() -> Sound:
    return _step_like(4, 4200.0, 0.08)


def sfx_step_wood() -> Sound:
    sound = _step_like(5, 1200.0, 0.07)
    knock = tone(240.0, 0.09, "triangle", freq_end=180.0)
    knock.envelope(0.001, 0.05, curve=8.0)
    out = Sound(0.16)
    out.mix_into(sound, 0.0, 0.8)
    out.mix_into(knock, 0.0, 0.5)
    return out


def sfx_step_wool() -> Sound:
    return _step_like(6, 700.0, 0.11)


def sfx_dig_glass() -> Sound:
    burst = noise_burst(0.18, 7)
    burst.highpass(3500.0)
    burst.envelope(0.0005, 0.05, curve=9.0)
    shard = tone(2400.0, 0.16, "triangle", freq_end=3100.0)
    shard.envelope(0.0005, 0.06, curve=8.0)
    out = Sound(0.2)
    out.mix_into(burst, 0.0, 0.9)
    out.mix_into(shard, 0.0, 0.35)
    return out.fade_out(0.03)


def sfx_break_block() -> Sound:
    burst = noise_burst(0.3, 11)
    burst.lowpass(1500.0, passes=2)
    burst.envelope(0.001, 0.11, curve=5.0)
    thud = tone(120.0, 0.28, "sine", freq_end=60.0)
    thud.envelope(0.001, 0.12, curve=5.0)
    out = Sound(0.32)
    out.mix_into(burst, 0.0, 0.9)
    out.mix_into(thud, 0.0, 0.45)
    return out.fade_out(0.04)


def sfx_place_block() -> Sound:
    burst = noise_burst(0.14, 13)
    burst.lowpass(1200.0, passes=2)
    burst.envelope(0.0005, 0.05, curve=8.0)
    knock = tone(300.0, 0.12, "triangle", freq_end=200.0)
    knock.envelope(0.0005, 0.05, curve=7.0)
    out = Sound(0.16)
    out.mix_into(burst, 0.0, 0.7)
    out.mix_into(knock, 0.0, 0.5)
    return out.fade_out(0.02)


def sfx_hurt() -> Sound:
    body = tone(320.0, 0.28, "saw", freq_end=170.0)
    body.lowpass(1800.0)
    body.envelope(0.004, 0.13, curve=4.0)
    grit = noise_burst(0.12, 17)
    grit.lowpass(900.0)
    grit.envelope(0.002, 0.05, curve=6.0)
    out = Sound(0.3)
    out.mix_into(body, 0.0, 0.85)
    out.mix_into(grit, 0.0, 0.3)
    return out.fade_out(0.04)


def sfx_death() -> Sound:
    body = tone(300.0, 0.8, "saw", freq_end=90.0)
    body.lowpass(1400.0)
    body.envelope(0.01, 0.5, curve=3.0)
    return body.fade_out(0.15).normalize(0.9)


def sfx_eat() -> Sound:
    out = Sound(0.5)
    rng = random.Random(19)
    for i in range(3):
        crunch = noise_burst(0.09, rng.randint(0, 999))
        crunch.lowpass(1600.0)
        crunch.envelope(0.001, 0.03, curve=8.0)
        out.mix_into(crunch, i * 0.14, 0.9)
    return out.normalize(0.85)


def sfx_drink() -> Sound:
    out = Sound(0.6)
    for i in range(4):
        gulp = tone(220.0 - i * 12, 0.1, "sine", freq_end=150.0)
        gulp.lowpass(900.0)
        gulp.envelope(0.005, 0.05, curve=6.0)
        out.mix_into(gulp, i * 0.13, 0.8)
    return out.normalize(0.8)


def sfx_level_up() -> Sound:
    notes = [(523.25, 0.1), (659.25, 0.1), (783.99, 0.1), (1046.5, 0.26)]
    sound = sequence(notes, waveform="triangle")
    bell = chord([1046.5, 1568.0], 0.3, waveform="sine")
    bell.envelope(0.005, 0.15, curve=5.0)
    sound.mix_into(bell, 0.3, 0.35)
    return sound.fade_out(0.1).normalize(0.75)


def sfx_xp_pickup() -> Sound:
    sound = tone(1180.0, 0.12, "triangle", freq_end=1620.0)
    sound.envelope(0.002, 0.05, curve=7.0)
    return sound.fade_out(0.03)


def sfx_item_pickup() -> Sound:
    sound = tone(660.0, 0.1, "square", freq_end=990.0)
    sound.envelope(0.002, 0.04, curve=8.0)
    return sound.fade_out(0.02).normalize(0.5)


def sfx_click() -> Sound:
    sound = tone(920.0, 0.05, "square", freq_end=700.0)
    sound.lowpass(3000.0)
    sound.envelope(0.001, 0.02, curve=9.0)
    return sound.normalize(0.5)


def sfx_piston() -> Sound:
    burst = noise_burst(0.2, 23)
    burst.lowpass(700.0, passes=2)
    burst.envelope(0.002, 0.08, curve=6.0)
    thud = tone(90.0, 0.22, "sine", freq_end=55.0)
    thud.envelope(0.002, 0.1, curve=5.0)
    out = Sound(0.24)
    out.mix_into(burst, 0.0, 0.8)
    out.mix_into(thud, 0.05, 0.7)
    return out.fade_out(0.03)


def sfx_lever() -> Sound:
    click = sfx_click()
    wood = tone(420.0, 0.09, "triangle", freq_end=280.0)
    wood.envelope(0.001, 0.04, curve=8.0)
    out = Sound(0.14)
    out.mix_into(click, 0.0, 0.7)
    out.mix_into(wood, 0.02, 0.6)
    return out


def sfx_craft() -> Sound:
    out = Sound(0.5)
    for i, freq in enumerate((880.0, 1180.0)):
        clang = chord([freq, freq * 1.5], 0.3, waveform="triangle")
        clang.envelope(0.001, 0.12, curve=6.0)
        out.mix_into(clang, i * 0.12, 0.5)
    return out.normalize(0.7)


def sfx_splash() -> Sound:
    burst = noise_burst(0.4, 29)
    burst.lowpass(3000.0, passes=2)
    burst.envelope(0.004, 0.16, curve=5.0)
    sweep = tone(700.0, 0.35, "sine", freq_end=200.0)
    sweep.envelope(0.005, 0.15, curve=5.0)
    out = Sound(0.45)
    out.mix_into(burst, 0.0, 0.8)
    out.mix_into(sweep, 0.0, 0.4)
    return out.fade_out(0.08)


def sfx_swim() -> Sound:
    burst = noise_burst(0.35, 31)
    burst.lowpass(1100.0, passes=2)
    burst.envelope(0.02, 0.14, curve=4.0)
    return burst.fade_out(0.08).normalize(0.55)


def sfx_explode() -> Sound:
    out = Sound(1.1)
    boom = noise_burst(1.0, 37)
    boom.lowpass(280.0, passes=3)
    boom.envelope(0.004, 0.45, curve=3.5)
    crack = noise_burst(0.25, 41)
    crack.highpass(900.0)
    crack.envelope(0.001, 0.08, curve=6.0)
    rumble = tone(70.0, 1.0, "sine", freq_end=32.0)
    rumble.envelope(0.01, 0.5, curve=3.0)
    out.mix_into(boom, 0.0, 1.0)
    out.mix_into(crack, 0.0, 0.35)
    out.mix_into(rumble, 0.0, 0.5)
    return out.fade_out(0.2).normalize(0.95)


def sfx_fuse() -> Sound:
    burst = noise_burst(1.3, 43)
    burst.highpass(2600.0)
    # crackling envelope: amplitude follows a fast pulsing pattern
    for i in range(len(burst.samples)):
        pulse = 0.5 + 0.5 * math.sin(i * 0.006)
        burst.samples[i] *= pulse * min(1.0, i / 2000.0)
    return burst.fade_out(0.2).normalize(0.7)


def sfx_bow_shoot() -> Sound:
    twang = tone(420.0, 0.22, "saw", freq_end=120.0)
    twang.lowpass(2400.0)
    twang.envelope(0.001, 0.09, curve=6.0)
    whoosh = noise_burst(0.2, 47)
    whoosh.lowpass(2200.0)
    whoosh.envelope(0.01, 0.07, curve=5.0)
    out = Sound(0.24)
    out.mix_into(twang, 0.0, 0.8)
    out.mix_into(whoosh, 0.02, 0.5)
    return out.fade_out(0.03)


def sfx_arrow_hit() -> Sound:
    burst = noise_burst(0.14, 53)
    burst.lowpass(1400.0)
    burst.envelope(0.001, 0.05, curve=8.0)
    thud = tone(200.0, 0.12, "triangle", freq_end=120.0)
    thud.envelope(0.001, 0.05, curve=8.0)
    out = Sound(0.16)
    out.mix_into(burst, 0.0, 0.8)
    out.mix_into(thud, 0.0, 0.5)
    return out


def sfx_rain_loop() -> Sound:
    sound = Sound(4.0)
    rng = random.Random(59)
    for i in range(90):
        drop = noise_burst(0.05, rng.randint(0, 9999))
        drop.highpass(1800.0)
        drop.envelope(0.001, 0.012, curve=9.0)
        sound.mix_into(drop, rng.uniform(0.0, 3.95), 0.5)
    hiss = noise_burst(4.0, 61)
    hiss.lowpass(3500.0)
    for i in range(len(hiss.samples)):
        # gentle fade at both ends so the loop point is inaudible
        edge = min(i, len(hiss.samples) - i) / (0.35 * hiss.rate)
        hiss.samples[i] *= min(1.0, edge) * 0.5
    out = Sound(4.0)
    out.mix_into(sound, 0.0, 0.7)
    out.mix_into(hiss, 0.0, 0.45)
    return out.normalize(0.7)


def sfx_thunder() -> Sound:
    boom = noise_burst(2.4, 67)
    boom.lowpass(200.0, passes=3)
    boom.envelope(0.02, 1.0, curve=2.5)
    crack = noise_burst(0.5, 71)
    crack.highpass(400.0)
    crack.envelope(0.001, 0.2, curve=4.0)
    out = Sound(2.5)
    out.mix_into(boom, 0.0, 1.0)
    out.mix_into(crack, 0.0, 0.3)
    return out.fade_out(0.4).normalize(0.9)


# --- mob voices ------------------------------------------------------------


def sfx_zombie_idle() -> Sound:
    out = Sound(0.9)
    for i in range(2):
        groan = tone(120.0 - i * 15, 0.4, "saw", freq_end=88.0)
        groan.lowpass(700.0)
        groan.envelope(0.05, 0.2, curve=3.0)
        for k in range(len(groan.samples)):  # slow vibrato growl
            groan.samples[k] *= 1.0 + 0.18 * math.sin(k * 0.004)
        out.mix_into(groan, i * 0.42, 0.9)
    return out.fade_out(0.1).normalize(0.7)


def sfx_zombie_hurt() -> Sound:
    groan = tone(160.0, 0.3, "square", freq_end=100.0)
    groan.lowpass(900.0)
    groan.envelope(0.005, 0.12, curve=5.0)
    return groan.fade_out(0.05).normalize(0.7)


def sfx_skeleton_rattle() -> Sound:
    out = Sound(0.5)
    rng = random.Random(73)
    for i in range(7):
        click = noise_burst(0.03, rng.randint(0, 999))
        click.highpass(2200.0)
        click.envelope(0.0005, 0.01, curve=9.0)
        out.mix_into(click, i * 0.06 + rng.uniform(0.0, 0.02), 0.8)
    return out.normalize(0.7)


def sfx_creeper_hiss() -> Sound:
    burst = noise_burst(1.4, 79)
    burst.highpass(1500.0)
    for i in range(len(burst.samples)):
        fade = min(1.0, i / (0.15 * burst.rate))
        burst.samples[i] *= fade
    return burst.fade_out(0.15).normalize(0.85)


def sfx_cow_moo() -> Sound:
    out = Sound(1.0)
    moo = tone(180.0, 0.85, "saw", freq_end=120.0)
    moo.lowpass(900.0)
    moo.envelope(0.08, 0.4, curve=3.0)
    for k in range(len(moo.samples)):
        moo.samples[k] *= 1.0 + 0.08 * math.sin(k * 0.0025)
    out.mix_into(moo, 0.0, 1.0)
    return out.fade_out(0.15).normalize(0.7)


def sfx_pig_oink() -> Sound:
    out = Sound(0.6)
    for i in range(2):
        oink = tone(300.0 - i * 40, 0.16, "square", freq_end=190.0)
        oink.lowpass(1100.0)
        oink.envelope(0.006, 0.06, curve=6.0)
        out.mix_into(oink, i * 0.2, 0.8)
    return out.normalize(0.6)


def sfx_sheep_baa() -> Sound:
    out = Sound(0.8)
    baa = tone(420.0, 0.6, "saw", freq_end=330.0)
    baa.lowpass(1600.0)
    baa.envelope(0.03, 0.28, curve=4.0)
    for k in range(len(baa.samples)):
        baa.samples[k] *= 1.0 + 0.35 * math.sin(k * 0.02)  # fast bleat vibrato
    out.mix_into(baa, 0.0, 1.0)
    return out.fade_out(0.1).normalize(0.65)


def sfx_chicken_cluck() -> Sound:
    out = Sound(0.5)
    for i, freq in enumerate((900.0, 1150.0, 800.0)):
        cluck = tone(freq, 0.08, "triangle", freq_end=freq * 0.6)
        cluck.envelope(0.002, 0.03, curve=8.0)
        out.mix_into(cluck, i * 0.11, 0.7)
    return out.normalize(0.55)


def sfx_cat_meow() -> Sound:
    out = Sound(0.8)
    meow = tone(620.0, 0.6, "triangle", freq_end=480.0)
    meow.lowpass(2600.0)
    meow.envelope(0.05, 0.28, curve=3.5)
    for k in range(len(meow.samples)):
        meow.samples[k] *= 1.0 + 0.12 * math.sin(k * 0.012)
    out.mix_into(meow, 0.0, 1.0)
    return out.fade_out(0.12).normalize(0.6)


def sfx_villager_hmm() -> Sound:
    out = Sound(0.6)
    hum = tone(240.0, 0.45, "square", freq_end=180.0)
    hum.lowpass(1000.0)
    hum.envelope(0.04, 0.2, curve=4.0)
    out.mix_into(hum, 0.0, 1.0)
    return out.fade_out(0.1).normalize(0.5)


# ---------------------------------------------------------------------------
# Music (short seamless loops)
# ---------------------------------------------------------------------------
#
# Every partial's frequency is quantised to a multiple of 1/loop_length, which
# makes the whole waveform exactly periodic: the loop point is therefore
# click-free without any fading, and pads can sustain across it.

NOTE_NAMES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7,
              "G#": 8, "A": 9, "A#": 10, "B": 11}


def _note_hz(name: str, octave: int) -> float:
    semitone = NOTE_NAMES[name]
    return 440.0 * (2.0 ** ((semitone - 9) / 12.0 + (octave - 4)))


def _quantise(freq: float, loop_seconds: float) -> float:
    step = 1.0 / loop_seconds
    return max(step, round(freq / step) * step)


def _pad_note(target: Sound, freq: float, loop: float, gain: float, partials=(1.0, 2.0, 3.0)) -> None:
    """Sustained, band-limited pad voice that wraps perfectly around the loop."""
    rate = target.rate
    weights = (1.0, 0.32, 0.14)
    for index, partial in enumerate(partials):
        f = _quantise(freq * partial, loop)
        amplitude = gain * weights[index % len(weights)]
        # Slow amplitude shimmer also quantised to the loop for continuity.
        lfo = _quantise(0.13 + 0.07 * index, loop)
        phase = 0.0
        lfo_phase = index * 1.7
        for i in range(len(target.samples)):
            phase += 2.0 * math.pi * f / rate
            lfo_phase += 2.0 * math.pi * lfo / rate
            target.samples[i] += math.sin(phase) * amplitude * (0.85 + 0.15 * math.sin(lfo_phase))


def _bell(target: Sound, freq: float, start: float, length: float, gain: float) -> None:
    """Soft plucked voice used for melodies; never placed across the loop seam."""
    voice = Sound(length, target.rate)
    rate = target.rate
    phase = 0.0
    for i in range(len(voice.samples)):
        t = i / rate
        phase += 2.0 * math.pi * freq / rate
        decay = math.exp(-t * 2.6)
        voice.samples[i] = (math.sin(phase) + 0.25 * math.sin(phase * 2.01)) * decay
    voice.envelope(0.02, length, curve=1.0)
    target.mix_into(voice, start, gain)


def _music_track(loop: float, progression: list, melody: list, master: float = 0.5,
                 pad_gain: float = 0.5, bass: bool = True) -> Sound:
    track = Sound(loop)
    chord_time = loop / len(progression)
    for index, chord in enumerate(progression):
        start = index * chord_time
        # Each chord is rendered for its full slot length plus a small overlap.
        for note in chord:
            _pad_note(track, note, loop, pad_gain / max(1, len(chord)))
        if bass and index % 2 == 0:
            _pad_note(track, chord[0] / 2.0, loop, pad_gain * 0.8, partials=(1.0, 2.0))
    for (note, start, length, gain) in melody:
        if start + length < loop - 0.4:
            _bell(track, note, start, length, gain)
    track.lowpass(4200.0)
    return track.normalize(master)


def _chord(base: str, octave: int, intervals) -> list:
    return [_note_hz(base, octave + shift) for shift in intervals]


def music_day() -> Sound:
    progression = [
        _chord("C", 4, [0, 4, 7, 12]),
        _chord("A", 3, [0, 3, 7, 12]),
        _chord("F", 3, [0, 4, 7, 12]),
        _chord("G", 3, [0, 4, 7, 12]),
    ]
    melody = [
        (_note_hz("E", 5), 0.6, 2.4, 0.22),
        (_note_hz("G", 5), 3.4, 2.0, 0.18),
        (_note_hz("C", 6), 6.2, 2.6, 0.2),
        (_note_hz("D", 6), 9.4, 2.2, 0.16),
        (_note_hz("A", 5), 12.6, 2.5, 0.18),
    ]
    return _music_track(16.0, progression * 1, melody, 0.5, 0.55)


def music_night() -> Sound:
    progression = [
        _chord("A", 3, [0, 3, 7, 12]),
        _chord("F", 3, [0, 4, 7, 12]),
        _chord("D", 3, [0, 3, 7, 12]),
        _chord("E", 3, [0, 4, 7, 11]),
    ]
    melody = [
        (_note_hz("A", 4), 1.2, 3.0, 0.16),
        (_note_hz("C", 5), 5.6, 2.6, 0.15),
        (_note_hz("F", 5), 9.8, 3.2, 0.14),
        (_note_hz("E", 5), 14.0, 2.6, 0.13),
    ]
    return _music_track(20.0, progression, melody, 0.42, 0.45)


def music_cave() -> Sound:
    progression = [
        _chord("D", 2, [0, 3, 7]),
        _chord("D", 2, [0, 3, 6]),
        _chord("C", 2, [0, 3, 7]),
        _chord("D", 2, [0, 4, 7]),
    ]
    melody = [
        (_note_hz("D", 4), 2.4, 3.4, 0.12),
        (_note_hz("F", 4), 8.0, 3.0, 0.1),
        (_note_hz("A", 4), 13.2, 3.4, 0.11),
    ]
    return _music_track(24.0, progression, melody, 0.36, 0.4)


def music_menu() -> Sound:
    progression = [
        _chord("F", 3, [0, 4, 7, 11]),
        _chord("C", 4, [0, 4, 7, 12]),
        _chord("G", 3, [0, 4, 7, 12]),
        _chord("A", 3, [0, 3, 7, 12]),
    ]
    melody = [
        (_note_hz("C", 5), 1.0, 2.8, 0.2),
        (_note_hz("E", 5), 4.4, 2.4, 0.18),
        (_note_hz("G", 5), 7.8, 2.8, 0.17),
        (_note_hz("F", 5), 11.6, 3.2, 0.16),
        (_note_hz("A", 5), 15.4, 3.0, 0.15),
    ]
    return _music_track(20.0, progression, melody, 0.45, 0.5)


SOUNDS = {
    "step_stone": sfx_step_stone,
    "step_dirt": sfx_step_dirt,
    "step_grass": sfx_step_grass,
    "step_sand": sfx_step_sand,
    "step_wood": sfx_step_wood,
    "step_wool": sfx_step_wool,
    "dig_glass": sfx_dig_glass,
    "break_block": sfx_break_block,
    "place_block": sfx_place_block,
    "hurt": sfx_hurt,
    "death": sfx_death,
    "eat": sfx_eat,
    "drink": sfx_drink,
    "level_up": sfx_level_up,
    "xp_pickup": sfx_xp_pickup,
    "item_pickup": sfx_item_pickup,
    "click": sfx_click,
    "piston": sfx_piston,
    "lever": sfx_lever,
    "craft": sfx_craft,
    "splash": sfx_splash,
    "swim": sfx_swim,
    "explode": sfx_explode,
    "fuse": sfx_fuse,
    "bow_shoot": sfx_bow_shoot,
    "arrow_hit": sfx_arrow_hit,
    "rain_loop": sfx_rain_loop,
    "thunder": sfx_thunder,
    "zombie_idle": sfx_zombie_idle,
    "zombie_hurt": sfx_zombie_hurt,
    "skeleton_rattle": sfx_skeleton_rattle,
    "creeper_hiss": sfx_creeper_hiss,
    "cow_moo": sfx_cow_moo,
    "pig_oink": sfx_pig_oink,
    "sheep_baa": sfx_sheep_baa,
    "chicken_cluck": sfx_chicken_cluck,
    "cat_meow": sfx_cat_meow,
    "villager_hmm": sfx_villager_hmm,
}

MUSIC = {
    "music_menu": music_menu,
    "music_day": music_day,
    "music_night": music_night,
    "music_cave": music_cave,
}
