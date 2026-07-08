# Task board

Claim a task by putting your branch name in the **Claimed by** column (commit that
change on your branch first). Keep one task per PR. See ROADMAP.md for phase details.

## Phase 1 — POC hardening

| Task | Claimed by | Status |
|---|---|---|
| Verify build once Xcode install completes; fix compile errors | — | open |
| Real-device drive test behind Apple Maps (ducking, background) | — | open (needs human) |
| App icon + launch screen | — | open |

## Phase 2.5 — Event system & design (see docs/EVENT_SYSTEM.md)

| Task | Claimed by | Status |
|---|---|---|
| Event schema, validator, examples, design doc | claude/event-system-plan | in review |
| Runtime: ContentLibrary + TriggerEvaluator (drive-state contexts) | claude/event-runtime-core | in review |
| Runtime: EventPlayer for sequence type (time/distance waits) | — | open |
| Runtime: EventPlayer for branching type (voice/tap choices, timeouts, flags) | — | open |
| Migrate CannedEvents to Content/events/*.json | claude/event-runtime-core | in review |
| Event Editor web app (trigger form + branching node editor) | — | open |
| Wireframes: rough exploration board (bridge, author mode, navigator) | — | open |
| Wireframes: clickable HTML mockups of winning direction | — | open |
| Replace synthesized SFX with StoryBlocks assets (Alex has access) | — | open (needs human picks) |

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
| Phase 2: message queue, push-to-talk voice commands, thruster SFX, Power/Eco personalities | claude (2026-07-07, PRs #1, #6) |
