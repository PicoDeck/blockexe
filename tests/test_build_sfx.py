"""Host tests for tools/build_sfx.py. Run from the repo root:
python3 -m unittest discover -s tests -p 'test_*.py'"""
import importlib.util
import json
import math
import tempfile
import unittest
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("build_sfx", ROOT / "tools" / "build_sfx.py")
build_sfx = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_sfx)
RATE = build_sfx.RATE


def make_wav(path, seconds, freq=440.0, amp=0.5, rate=RATE, channels=1, lead_silence_ms=0):
    frames = int(seconds * rate)
    lead = int(lead_silence_ms * rate / 1000)
    data = bytearray()
    for i in range(frames):
        v = 0 if i < lead else int(amp * 32767 * math.sin(2 * math.pi * freq * i / rate))
        data += v.to_bytes(2, "little", signed=True) * channels
    with wave.open(str(path), "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(data))


def read_pcm(path):
    with wave.open(str(path), "rb") as w:
        raw = w.readframes(w.getnframes())
    return [int.from_bytes(raw[i:i + 2], "little", signed=True) for i in range(0, len(raw), 2)]


class BuildSfxTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.src = Path(self.tmp.name) / "src"
        self.out = Path(self.tmp.name) / "out"
        self.src.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def manifest(self, sounds):
        (self.src / "manifest.json").write_text(json.dumps({"sounds": sounds}))

    def entry(self, **over):
        e = {"source": "a.wav", "start_ms": 0, "length_ms": 100, "fade_ms": 20, "gain_db": 0}
        e.update(over)
        return e

    def test_cuts_to_length(self):
        make_wav(self.src / "a.wav", 1.0)
        self.manifest({"move": self.entry(length_ms=100)})
        built = build_sfx.build(self.src, self.out)
        self.assertEqual(len(built["move"]), 2 * round(100 * RATE / 1000))
        self.assertTrue((self.out / "move.wav").is_file())

    def test_fade_out_ends_at_zero(self):
        make_wav(self.src / "a.wav", 1.0, freq=100)
        self.manifest({"move": self.entry(fade_ms=30)})
        build_sfx.build(self.src, self.out)
        self.assertEqual(read_pcm(self.out / "move.wav")[-1], 0)

    def test_peak_is_minus_1_dbfs_plus_gain(self):
        make_wav(self.src / "a.wav", 1.0, amp=0.2)
        self.manifest({"move": self.entry(fade_ms=0), "lock": self.entry(fade_ms=0, gain_db=-6)})
        build_sfx.build(self.src, self.out)
        loud = max(abs(s) for s in read_pcm(self.out / "move.wav"))
        quiet = max(abs(s) for s in read_pcm(self.out / "lock.wav"))
        self.assertAlmostEqual(loud, 0.891 * 32767, delta=40)
        self.assertAlmostEqual(quiet / loud, 10 ** (-6 / 20), delta=0.01)

    def test_output_is_22050_mono_16_bit(self):
        make_wav(self.src / "a.wav", 0.5)
        self.manifest({"move": self.entry()})
        build_sfx.build(self.src, self.out)
        with wave.open(str(self.out / "move.wav"), "rb") as w:
            self.assertEqual((w.getframerate(), w.getnchannels(), w.getsampwidth()), (RATE, 1, 2))

    def test_onset_finds_the_sound_after_silence(self):
        make_wav(self.src / "a.wav", 1.0, lead_silence_ms=200)
        samples = build_sfx.read_source(self.src / "a.wav")
        self.assertAlmostEqual(build_sfx.onset_ms(samples), 200, delta=2)

    def test_rejects_wrong_format(self):
        make_wav(self.src / "a.wav", 0.5, rate=44100)
        self.manifest({"move": self.entry()})
        with self.assertRaisesRegex(build_sfx.BuildError, "22050 Hz"):
            build_sfx.build(self.src, self.out)

    def test_rejects_stereo(self):
        make_wav(self.src / "a.wav", 0.5, channels=2)
        self.manifest({"move": self.entry()})
        with self.assertRaisesRegex(build_sfx.BuildError, "mono"):
            build_sfx.build(self.src, self.out)

    def test_rejects_missing_field(self):
        make_wav(self.src / "a.wav", 0.5)
        e = self.entry()
        del e["fade_ms"]
        self.manifest({"move": e})
        with self.assertRaisesRegex(build_sfx.BuildError, "lacks fade_ms"):
            build_sfx.build(self.src, self.out)

    def test_rejects_missing_source(self):
        self.manifest({"move": self.entry(source="nope.wav")})
        with self.assertRaisesRegex(build_sfx.BuildError, "missing source"):
            build_sfx.build(self.src, self.out)

    def test_rejects_unknown_sound(self):
        make_wav(self.src / "a.wav", 0.5)
        self.manifest({"boing": self.entry()})
        with self.assertRaisesRegex(build_sfx.BuildError, "not a sound"):
            build_sfx.build(self.src, self.out)

    def test_rejects_over_64_kb(self):
        make_wav(self.src / "a.wav", 2.0)
        self.manifest({"tetris": self.entry(length_ms=1600)})
        with self.assertRaisesRegex(build_sfx.BuildError, "65536"):
            build_sfx.build(self.src, self.out)

    def test_rejects_a_silent_cut(self):
        make_wav(self.src / "a.wav", 1.0, lead_silence_ms=900)
        self.manifest({"move": self.entry(length_ms=100)})
        with self.assertRaisesRegex(build_sfx.BuildError, "silent"):
            build_sfx.build(self.src, self.out)

    def test_nothing_written_when_any_sound_fails(self):
        make_wav(self.src / "a.wav", 0.5)
        self.manifest({"move": self.entry(), "lock": self.entry(source="nope.wav")})
        with self.assertRaises(build_sfx.BuildError):
            build_sfx.build(self.src, self.out)
        self.assertFalse(self.out.exists() and any(self.out.iterdir()))

    def test_same_inputs_same_bytes(self):
        make_wav(self.src / "a.wav", 1.0)
        self.manifest({"move": self.entry(start_ms=37, gain_db=-3.5)})
        build_sfx.build(self.src, self.out)
        first = (self.out / "move.wav").read_bytes()
        build_sfx.build(self.src, self.out)
        self.assertEqual((self.out / "move.wav").read_bytes(), first)

    def test_preview_joins_sounds_with_gaps(self):
        make_wav(self.src / "a.wav", 1.0)
        self.manifest({"move": self.entry(length_ms=100), "lock": self.entry(length_ms=200)})
        built = build_sfx.build(self.src, self.out)
        preview = Path(self.tmp.name) / "preview.wav"
        build_sfx.write_preview(preview, built, gap_ms=400)
        with wave.open(str(preview), "rb") as w:
            frames = w.getnframes()
        expected = round(100 * RATE / 1000) + round(200 * RATE / 1000) + 2 * round(400 * RATE / 1000)
        self.assertEqual(frames, expected)


if __name__ == "__main__":
    unittest.main()
