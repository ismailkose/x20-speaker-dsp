#!/usr/bin/env bash
# measure-balance.sh — check left/right balance and channel separation of the DSP.
# Plays a short, quiet noise burst on left, right and both channels through the
# DSP and records what actually reaches the speakers (post-processing).
# Needs only python3 (standard library). Lower your volume first.
set -euo pipefail
SINK="$(pw-cli ls Node | sed -n 's/.*node.name = "\(alsa_output[^"]*amd_sdw.HiFi__Speaker__sink\)".*/\1/p' | head -1)"
[ -n "$SINK" ] || { echo "speaker sink not found"; exit 1; }
TARGET="effect_input.x20_dsp"
pw-cli ls Node | grep -q "$TARGET" || { echo "DSP is off — measuring stock output"; TARGET="$SINK"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

python3 - "$T" <<'PY'
import sys, wave, struct, random
d=sys.argv[1]; fs=48000; n=fs*3; random.seed(1)
x=[random.gauss(0,0.08) for _ in range(n)]
for name,(l,r) in {"L":(1,0),"R":(0,1),"C":(1,1)}.items():
    with wave.open(f"{d}/{name}.wav","wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(fs)
        w.writeframes(b"".join(struct.pack("<hh",int(max(-1,min(1,v*l))*32767),int(max(-1,min(1,v*r))*32767)) for v in x))
PY

# Warm-up so the (slow) leveler settles, then measure R, L, C.
for t in L R L R C; do
  pw-record -P '{ node.autoconnect = false node.name = x20measure }' --channels 2 --format s16 --rate 48000 "$T/rec_$t.wav" & RP=$!
  sleep 0.6
  pw-link "$SINK:monitor_FL" x20measure:input_FL; pw-link "$SINK:monitor_FR" x20measure:input_FR
  pw-play --target "$TARGET" "$T/$t.wav"; sleep 0.3; kill $RP; wait $RP 2>/dev/null || true
done >/dev/null 2>&1

python3 - "$T" <<'PY'
import sys, wave, struct, math
d=sys.argv[1]
def rms(t):
    with wave.open(f"{d}/rec_{t}.wav") as w: b=w.readframes(w.getnframes())
    s=struct.unpack("<%dh"%(len(b)//2), b); L=s[0::2]; R=s[1::2]
    a,z=48000, 48000*3
    f=lambda c: math.sqrt(sum(v*v for v in c[a:z])/max(1,len(c[a:z])))/32768+1e-12
    return f(L), f(R)
db=lambda v: 20*math.log10(v)
res={t:rms(t) for t in "LRC"}
(lL,lR),(rL,rR),(cL,cR)=res["L"],res["R"],res["C"]
print(f"left-only  -> left {db(lL):6.1f} dB, right {db(lR):6.1f} dB  (separation {db(lL/lR):5.1f} dB)")
print(f"right-only -> left {db(rL):6.1f} dB, right {db(rR):6.1f} dB  (separation {db(rR/rL):5.1f} dB)")
print(f"both       -> left {db(cL):6.1f} dB, right {db(cR):6.1f} dB")
print(f"balance (left-only vs right-only): {db(lL/rR):+.1f} dB   center balance: {db(cL/cR):+.1f} dB")
print("A balance within ±0.5 dB means the processing is symmetric.")
PY
