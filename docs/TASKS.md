# Task board

Claim a task by putting your branch name in the **Claimed by** column (commit that
change on your branch first). Keep one task per PR. See ROADMAP.md for phase details.

## Phase 1 — POC hardening

| Task | Claimed by | Status |
|---|---|---|
| Verify build once Xcode install completes; fix compile errors | — | open |
| Real-device drive test behind Apple Maps (ducking, background) | — | open (needs human) |
| App icon + launch screen | — | open |

## Phase 2 — Interaction

| Task | Claimed by | Status |
|---|---|---|
| Push-to-talk voice commands (SFSpeechRecognizer): "power down", "status report" | claude/voice-commands | in progress |
| Message queue: hail beep, message waits for "play message" | claude/message-queue | in progress |
| Acceleration/deceleration SFX from speed deltas | claude/acceleration-sfx | in progress |
| Power/Eco mode sound personalities | claude/engine-personality | in progress |

## Phase 3 — Generated adventures

| Task | Claimed by | Status |
|---|---|---|
| ClaudeStorySource implementing EventSource; episode outline at trip start | — | open |
| Story types (mystery/escort/first-contact) prompt templates | — | open |
| Trip-length-aware pacing + gas-station pause handling | — | open |
| Weather/date context injection (WeatherKit — needs paid dev account) | — | open |
| Choice input + consequence state | — | open |
| ElevenLabs/OpenAI TTS voice behind VoiceSynthesizing | — | open |

## Phase 4 — Full bridge crew

| Task | Claimed by | Status |
|---|---|---|
| Wake word via Picovoice Porcupine | — | open |
| Music playback | — | open |
| Gyroscope mode | — | open |
| Navigator/2-player interface | — | open |

## Done

| Task | By |
|---|---|
| Feasibility research + roadmap | claude (2026-07-07) |
| POC scaffold: audio, TTS, GPS, events, bridge UI, SFX | claude (2026-07-07) |
| Repo + multi-agent infrastructure | claude (2026-07-07) |
