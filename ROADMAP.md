# Heart of Gold — iOS Companion App Roadmap

A spaceship-bridge driving companion: your car is the Heart of Gold, every drive is an away mission.

## Feasibility verdict

Every requested feature is achievable with standard iOS APIs. The only items needing
third-party services are the always-on trigger word (Picovoice Porcupine or similar)
and high-quality character voices / generated stories (Claude API + optional ElevenLabs TTS).
Nothing requires jailbreaking, special entitlements, or App Review exceptions —
background audio + location behind Maps is a fully supported pattern (it's what
every nav and podcast app does).

## Feature → technology map

| Feature | Technology | Phase |
|---|---|---|
| Startup routine, ship sounds, "Shields at 98%" | AVAudioPlayer + AVSpeechSynthesizer | **POC** |
| Speed tracking / GPS listening | CoreLocation (`speed`, distance accumulation) | **POC** |
| Runs in background behind Maps | Background modes `audio` + `location`, AVAudioSession `.duckOthers` | **POC** |
| Travel modes (Roadtrip / Errands, Power / Eco) | App state + different sound/event tables | **POC** (2 modes) |
| Randomized encounters on distance/time triggers | Local event engine (canned lines for POC) | **POC** |
| Acceleration sound effects | CoreLocation speed delta (or CoreMotion) | Phase 2 |
| Voice commands ("play message", "power down") | SFSpeechRecognizer, on-device, push-to-talk button first | Phase 2 |
| Message beep + "play message" queue | Local notification sound + queued TTS | Phase 2 |
| Generated one-shot adventures, drive-length-aware | Claude API: generate episode outline at trip start, beats fired by distance/time | Phase 3 |
| Choose-your-own-adventure w/ consequences | Claude API + voice-choice input, persisted story state | Phase 3 |
| Mystery mode (clue every 5 miles), escort, first contact | Story templates feeding the generator | Phase 3 |
| Weather & date awareness | WeatherKit + Date, injected into story prompt | Phase 3 |
| Eddie-style character voice | ElevenLabs / OpenAI TTS (fallback: AVSpeech premium voice) | Phase 3 |
| Always-listening trigger word | Picovoice Porcupine SDK | Phase 4 |
| Music playback (loaded music) | AVAudioPlayer bundled tracks; MusicKit if Apple Music | Phase 4 |
| Gyroscope mode | CoreMotion | Phase 4 |
| 2-player / navigator crew interface | Passenger-facing UI screen | Phase 4 |
| Camera use | TBD — no safe driving use case yet | Backlog |

## POC scope ("Bridge Online" demo)

One SwiftUI app that proves the core loop end-to-end:

1. **Startup sequence** — tap "Power Up": engine-hum sound ramps, then TTS:
   "Systems online. Shields at 98%. Infinite Improbability Drive on standby."
2. **Two travel modes** — Roadtrip / Errands toggle changes greeting + event frequency.
3. **Live speed readout** — GPS speed shown as "Sublight velocity", with spoken
   callouts crossing thresholds ("Entering cruise velocity").
4. **Random encounters** — every 2–5 min (or N miles), a beep + a canned bridge
   report from a small hand-written pool ("Medbay reports all crew nominal…").
5. **Background audio** — keeps speaking over/behind Apple Maps with audio ducking.
6. **Power down** — button triggers shutdown TTS + sound.

Explicitly deferred from POC: speech recognition, LLM stories, wake word, weather, music.

### POC architecture (leaves room for everything else)

```
HeartOfGold/
  App/                    SwiftUI entry, single bridge screen
  Audio/AudioEngine.swift   AVAudioSession config (playback, duckOthers), SFX + TTS queue
  Voice/ShipVoice.swift     TTS wrapper — swap AVSpeech → ElevenLabs later
  Trip/TripTracker.swift    CoreLocation: speed, distance, trip duration
  Events/EventEngine.swift  timer/distance-triggered events from an EventSource protocol
  Events/CannedEvents.swift POC event pool — later replaced by ClaudeStorySource
  Modes/TravelMode.swift    Roadtrip / Errands enum driving event tables
```

The `EventSource` protocol is the seam: POC uses `CannedEvents`; Phase 3 drops in
a Claude-backed source without touching the audio/trip layers.

## Setup steps & dependencies

1. **Xcode** — install from the Mac App Store (free, ~12 GB). Includes iOS SDK + Simulator.
2. **Apple ID in Xcode** — Settings → Accounts. A *free* account lets you install
   to your own iPhone immediately (app expires after 7 days, just re-run from Xcode).
3. **Apple Developer Program ($99/yr)** — required for TestFlight, WeatherKit, and
   90-day builds. Recommended before Phase 3; not needed to start the POC.
4. **iPhone in Developer Mode** — Settings → Privacy & Security → Developer Mode
   (prompted on first Xcode install).
5. **No third-party packages needed for the POC.** Later: Anthropic API key (Phase 3),
   Picovoice account (Phase 4), ElevenLabs key (optional Phase 3).
6. **Assets** — a handful of royalty-free sci-fi SFX (freesound.org) dropped into the bundle.

### Info.plist / capabilities for the POC
- `NSLocationWhenInUseUsageDescription` (+ Always for background tracking)
- Background Modes capability: **Audio**, **Location updates**
- Later: `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`

## Phase plan

- **Phase 1 — POC (a weekend):** scope above; drive around town with it running behind Maps.
- **Phase 2 — Interaction (1–2 weeks):** push-to-talk voice commands, message queue
  ("play message"), acceleration SFX, power/eco sound personalities.
- **Phase 3 — The Improbability Drive (2–4 weeks):** Claude-generated one-shot
  adventures sized to trip length, story types (mystery/escort/first contact),
  choices with consequences, pause-tolerance (gas-station handling = story just
  waits for a location/speed resume signal), weather/date flavor, better voice.
- **Phase 4 — Full bridge crew:** wake word, music, gyroscope play, navigator mode,
  fail-states and resource management.

## Known risks / gotchas

- **Wake word:** iOS apps can't listen while fully backgrounded for long periods
  without the audio session running; Porcupine works but costs battery. Push-to-talk
  (or a steering-wheel-mounted Bluetooth button) is the pragmatic driver-safe answer.
- **TTS during CarPlay/Maps:** ducking works, but test interruption recovery
  (phone calls, Siri) early — it's the fiddliest part of the POC.
- **LLM latency in the car:** generate the episode outline at trip start and
  pre-synthesize the next beat's audio while driving, so cell dead zones don't stall the story.
- **App Review for TestFlight:** first build gets a light review; a personal
  audio/companion app passes easily. Free-account sideload avoids it entirely.
