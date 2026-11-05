# BGLIT Signage – Controller ↔ Player sync (protocol v2)

The **Controller is the master clock**. Players follow it.

| Endpoint | Purpose |
|---|---|
| `GET /ping` | `{app:"bglit-signage-controller", protocol:2, ip, port}` – used by discovery |
| `GET /playlist.json` | Live state: `version, live, stopped, paused, volume, currentFilename, currentPositionMs, nextFilename, jumpToSeq, seekSeq, syncSeq, shuffle, repeatOne, emergency{active,message}, items[]` |
| `POST /status` | Player heartbeat (every 2 s). Response contains per-device `commands` (volume, muted, rebootSeq, captureSeq, identifySeq, clearCacheSeq) |
| `POST /screenshot?deviceId=` | PNG upload after a CAPTURE command |
| UDP `45454` | Player broadcasts `BGLIT_SIGNAGE_DISCOVER`, controller replies with its ip/port |

Ports tried: 8888, 9090, 5500, 7777, 8080.

Player rules
* Switches item whenever `currentFilename` differs from what it plays and seeks to `currentPositionMs`.
* `seekSeq` / `syncSeq` change → hard seek; `jumpToSeq` change → seek if drift > 1.5 s.
* Drift correction: video/audio 2 s, YouTube 3.5 s, images/PDF 1.5 s.
* When a video ends locally it starts `nextFilename` immediately (no black gap).
* Controller unreachable → keeps looping the last playlist locally, reconnects automatically.
