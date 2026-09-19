"""Turn a voice memo in memos/ into a timestamped raw transcript next to it.

    python tools/transcribe.py                 # every memo without a .raw.txt yet
    python tools/transcribe.py memos/x.mp3     # just that one
    python tools/transcribe.py --force ...     # redo even if the .raw.txt exists

The transcript is the first step of the `memo` skill (BOG-45): the skill runs
this, then reads the .raw.txt, untangles it into feedback/, and hands that to
triage. Nothing here talks to Linear.

Runs faster-whisper locally. No API key, and no ffmpeg: faster-whisper decodes
mp3/m4a/wav itself through PyAV. The model (medium.en, ~1.5 GB) downloads to
~/.cache/huggingface on first use.

GPU or CPU: CTranslate2 wants cuBLAS 12 and cuDNN 9 as loose DLLs, which on
this machine come from the pip wheels nvidia-cublas-cu12 and nvidia-cudnn-cu12
and live under the *user* site-packages (the Store Python keeps them there,
outside site.getsitepackages()). We add every nvidia/*/bin we can find to the
DLL search path and try cuda float16; if the model refuses to load there we
fall back to cpu int8 and say so. The 2026-09-18 memo is 3h22m: about 20 min
on the RTX 3080, hours on the CPU.

Windows text trap: output is written as bytes, UTF-8, LF, never through
write_text.
"""
import argparse
import datetime as dt
import glob
import os
import site
import sys
import time

MEMOS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "memos")
AUDIO_EXTS = (".mp3", ".m4a", ".wav", ".ogg", ".flac")


def _add_nvidia_dll_dirs():
    roots = list(site.getsitepackages()) + [site.getusersitepackages()]
    found = []
    for root in roots:
        for d in glob.glob(os.path.join(root, "nvidia", "*", "bin")):
            try:
                os.add_dll_directory(d)
            except (AttributeError, OSError):
                pass
            os.environ["PATH"] = d + os.pathsep + os.environ.get("PATH", "")
            found.append(d)
    return found


def _load_model(name, want):
    from faster_whisper import WhisperModel
    import ctranslate2

    if want in ("auto", "cuda") and ctranslate2.get_cuda_device_count() > 0:
        try:
            return WhisperModel(name, device="cuda", compute_type="float16"), "cuda/float16"
        except Exception as e:  # missing cuBLAS/cuDNN DLLs is the usual reason
            if want == "cuda":
                raise
            print(f"cuda unavailable ({str(e)[:120]}); falling back to cpu", file=sys.stderr)
    return WhisperModel(name, device="cpu", compute_type="int8"), "cpu/int8"


def _hms(s):
    s = int(s)
    return f"{s // 3600}:{(s % 3600) // 60:02d}:{s % 60:02d}"


def raw_path(audio):
    return os.path.splitext(audio)[0] + ".raw.txt"


def transcribe(audio, model, device_label, model_name):
    from faster_whisper import decode_audio

    t0 = time.time()
    samples = decode_audio(audio)
    duration = len(samples) / 16000.0
    print(f"{os.path.basename(audio)}: {_hms(duration)} of audio, {device_label}", file=sys.stderr)

    segments, _info = model.transcribe(
        samples,
        beam_size=5,
        vad_filter=True,
        vad_parameters={"min_silence_duration_ms": 700},
        condition_on_previous_text=False,  # long recordings: a bad segment must not poison the next hour
    )
    lines = [
        f"# source: {os.path.basename(audio)}",
        f"# duration: {_hms(duration)}",
        f"# model: {model_name} on {device_label}",
        f"# transcribed: {dt.date.today().isoformat()}",
        "# one line per segment, [h:mm:ss] is where it starts in the recording",
        "",
    ]
    next_report = 600.0
    for seg in segments:
        text = seg.text.strip()
        if not text:
            continue
        lines.append(f"[{_hms(seg.start)}] {text}")
        if seg.start >= next_report:
            print(f"  {_hms(seg.start)} / {_hms(duration)}  ({time.time() - t0:.0f}s elapsed)", file=sys.stderr)
            next_report += 600.0

    out = raw_path(audio)
    with open(out, "wb") as f:
        f.write(("\n".join(lines) + "\n").encode("utf-8"))
    print(f"  -> {out}  ({len(lines) - 6} segments, {time.time() - t0:.0f}s)", file=sys.stderr)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("audio", nargs="*", help="memo files; default: every memo in memos/ without a .raw.txt")
    ap.add_argument("--force", action="store_true", help="transcribe even if the .raw.txt exists")
    ap.add_argument("--model", default="medium.en")
    ap.add_argument("--device", default="auto", choices=("auto", "cuda", "cpu"))
    args = ap.parse_args()

    audios = args.audio or sorted(
        p for p in glob.glob(os.path.join(MEMOS_DIR, "*")) if p.lower().endswith(AUDIO_EXTS)
    )
    todo = [a for a in audios if args.force or not os.path.exists(raw_path(a))]
    skipped = [a for a in audios if a not in todo]
    for a in skipped:
        print(f"skip {os.path.basename(a)}: {os.path.basename(raw_path(a))} exists (--force to redo)", file=sys.stderr)
    if not todo:
        print("nothing to transcribe", file=sys.stderr)
        return 0

    _add_nvidia_dll_dirs()
    model, device_label = _load_model(args.model, args.device)
    for a in todo:
        print(transcribe(a, model, device_label, args.model))
    return 0


if __name__ == "__main__":
    sys.exit(main())
