# Event System — design & authoring guide

The modular content system for encounters, events, and quests. Events are **data,
not code**: JSON files in `Content/events/`, validated by CI, authored by anyone —
Alex, Claude agents, Codex — through the same git workflow as code, or via the
Event Editor web tool (`tools/event-editor/`, see Authoring below).

## Core ideas

1. **Full content model from day one.** The schema supports single-response events,
   multi-step sequences, and branching choose-your-own-adventure interactions with
   flags/consequences. The app's playback engine may implement these in stages, but
   content never has to migrate.
2. **Triggers are declarative contexts.** Every event declares the contexts in which
   it is *qualified* to fire. Omitted fields mean "any". The app evaluates only the
   contexts it currently supports (drive state first); events using unsupported
   contexts (weather, time) simply never qualify until that awareness ships — safe
   forward compatibility.
3. **General vs. context-specific is a spectrum, not two buckets.** A "general"
   event is just an event with few/no context constraints. Selection weights let
   context-specific events outrank general filler when their moment arrives.

## Event anatomy (schema v1, `tools/event.schema.json`)

```jsonc
{
  "schema": 1,
  "id": "vogon-poetry-hail",          // unique, kebab-case, matches filename
  "title": "Vogon poetry hail",
  "author": "alex",                    // who wrote it
  "type": "single",                    // single | sequence | branching
  "class": "ambient",                  // ambient | plot; defaults: single→ambient, others→plot
  "tags": ["comms", "humor"],

  "trigger": {
    "contexts": {                      // ALL specified must match; omit = any
      "tripModes": ["roadtrip"],       // roadtrip | errands
      "personalities": ["power"],      // power | eco
      "speedMPH": { "min": 45 },       // driving fast
      "tripDistanceMiles": { "min": 10 },
      "stopped": false,                // true = only while stopped (gas station!)
      "hardAccelRecently": true,       // within last 60s
      "timeOfDay": ["night"],          // morning|afternoon|evening|night (Phase: time)
      "daysOfWeek": ["sat", "sun"],    //                                (Phase: time)
      "weather": ["rain", "storm"],    // WeatherKit conditions          (Phase: weather)
      "requiresFlags": ["met-aliens"], // story state                    (Phase: flags)
      "forbidsFlags": ["ship-damaged"],
      "tripPhase": ["final"],          // arc: beginning | middle | final (needs briefing)
      "stopsRemaining": { "max": 1 }   // errand objectives left (needs briefing)
    },
    "weight": 3,                       // selection weight vs other qualified events
    "cooldownMinutes": 45,             // min gap before this event can repeat
    "maxPerTrip": 1                    // DEFAULT is 1 — repetition is opt-in
  },

  "content": { /* shape depends on type — see below */ },
  "effects": { "setFlags": ["heard-vogon-poetry"] }   // applied on completion
}
```

### `type: "single"` — one transmission
```jsonc
"content": { "source": "COMMS", "text": "A passing Vogon freighter is broadcasting poetry. Recommend we do not answer." }
```

### `type: "sequence"` — scripted multi-step (no choices)
Steps play in order; `wait` gates the next step on time or distance — this is how
an event unfolds across miles ("every 5 miles you get a new clue").
```jsonc
"content": {
  "steps": [
    { "source": "SCIENCE", "text": "Detecting an odd energy signature ahead." },
    { "wait": { "miles": 2 } },
    { "source": "SCIENCE", "text": "The signature is getting stronger, Captain." },
    { "wait": { "seconds": 90 } },
    { "source": "SHIP",    "text": "It was a space whale. It seems happy. Logging first contact." }
  ]
}
```

### `type: "branching"` — choose-your-own-adventure
A node graph. Choices are made by voice (push-to-talk phrases) or tap. `next`
points to another node or `"end"`. Nodes can set flags; a `timeoutNext` handles
the captain ignoring the ship (consequences for not responding).
```jsonc
"content": {
  "entry": "hail",
  "nodes": {
    "hail": {
      "source": "COMMS",
      "text": "An unidentified ship requests docking. Do we allow it, or raise shields?",
      "choices": [
        { "label": "Allow docking", "phrases": ["allow", "dock", "let them in"], "next": "dock" },
        { "label": "Raise shields", "phrases": ["shields", "raise shields"],     "next": "shields" }
      ],
      "timeoutSeconds": 120,
      "timeoutNext": "ignored"
    },
    "dock":    { "source": "SECURITY", "text": "They brought snacks. Excellent decision, Captain.", "setFlags": ["made-friends"], "next": "end" },
    "shields": { "source": "SECURITY", "text": "Shields up. They made a rude gesture and left.", "next": "end" },
    "ignored": { "source": "SHIP", "text": "They got bored and left. A note was attached to the hull. It says: rude.", "next": "end" }
  }
}
```

### Engine guarantees (no authoring required)

- The same event never fires twice in a row, ever.
- Events fire at most once per trip unless they declare a higher `maxPerTrip`.
- `ambient` events stop firing while 5+ messages sit unplayed, and expire from
  the queue after 10 minutes unheard. `plot` events always fire and never expire.
- Branching nodes may offer at most 3 choices (validator-enforced) so the
  driving UI stays glanceable.

## Text templating

Any `text` field may embed placeholders, resolved fresh each time the line plays:

- `{n:88-99}` → a random integer in the range ("Shields at 94 percent")
- `{pick:a hawk|two pigeons|a weather balloon}` → one option at random

The validator checks placeholder syntax on every PR. Use these liberally —
they are the cheapest way to keep repeated stations sounding novel, and the
Event Editor will offer them as first-class inserts.

## Runtime architecture (implementation tasks on the board)

```
Content/events/*.json --(bundle)--> ContentLibrary   (loads + validates at launch)
ShipContext (speed, distance, mode, personality, stopped, flags, clock, weather)
        │
TriggerEvaluator (qualified = contexts match ∧ cooldown ok ∧ maxPerTrip ok)
        │  weighted random pick
EventPlayer (single / sequence / branching state machine; owns waits, choices,
             timeouts; feeds ShipVoice + message queue; applies effects/flags)
```
`ContentEventSource` implements the existing `EventSource` protocol, replacing
`CannedEvents` (which becomes ~8 migrated JSON files). Phase 3's Claude generator
becomes just another producer of the same JSON — generated stories and hand-authored
ones flow through one playback engine.

## Authoring workflows

- **Agents / by hand:** copy an example from `Content/events/examples/`, edit,
  run `python3 tools/validate_events.py`, open a PR. CI runs the validator on
  every PR — invalid content cannot merge.
- **Event Editor (for Alex):** local web app at `tools/event-editor/` — form-based
  trigger builder (dropdowns for contexts, sliders for weights/cooldowns) and a
  visual node editor for branching stories, reading/writing the same JSON files.
  Open a PR from its output like anyone else. *Status: planned — see task board.*
- **Voice-safety rule for all content:** text must work audio-only for the driver.
  Choices need short, distinct spoken phrases.

## Content review checklist (PR reviewers)

- Validator passes; `id` matches filename; author set.
- Branching: every node reachable, every `next` resolves, no orphan flags
  (a flag someone sets should matter to some event, eventually).
- Tone: Hitchhiker's-adjacent, funny > grim; fail states never kill the crew.
