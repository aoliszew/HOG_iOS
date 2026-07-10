#!/usr/bin/env python3
"""Validate all event JSON files in Content/events/. Run by CI on every PR."""
import json
import re
import sys
from pathlib import Path

EVENTS_DIR = Path(__file__).resolve().parent.parent / "Content" / "events"

TYPES = {"single", "sequence", "branching"}
TRIP_MODES = {"roadtrip", "errands"}
PERSONALITIES = {"power", "eco"}
TIMES = {"morning", "afternoon", "evening", "night"}
DAYS = {"mon", "tue", "wed", "thu", "fri", "sat", "sun"}
WEATHER = {"clear", "cloudy", "rain", "storm", "snow", "fog", "wind"}
PHASES = {"beginning", "middle", "final"}
SFX = {"hail", "shield_up", "alert", "scan", "chime_good", "chime_bad", "dock_clunk",
       "static", "thruster", "power_up", "power_down"}
CONTEXT_KEYS = {
    "tripModes", "personalities", "speedMPH", "tripDistanceMiles", "stopped",
    "hardAccelRecently", "timeOfDay", "daysOfWeek", "weather",
    "requiresFlags", "forbidsFlags", "tripPhase", "stopsRemaining", "states",
    "voyagePhase", "milesToDestination",
}

errors = []


def err(path, msg):
    errors.append(f"{path.name}: {msg}")


def check_enum(path, values, allowed, field):
    if not isinstance(values, list) or not set(values) <= allowed:
        err(path, f"{field} must be a list from {sorted(allowed)}")


def check_range(path, value, field):
    if not isinstance(value, dict) or not set(value) <= {"min", "max"} or not value:
        err(path, f"{field} must be an object with min and/or max")


TEMPLATE_RE = re.compile(r"\{([^{}]*)\}")


def check_templates(path, text, where):
    for body in TEMPLATE_RE.findall(text):
        if body.startswith("n:"):
            m = re.fullmatch(r"n:(-?\d+)-(-?\d+)", body)
            if not m or int(m.group(1)) > int(m.group(2)):
                err(path, f"{where}: bad number placeholder {{{body}}} (want {{n:LO-HI}})")
        elif body.startswith("pick:"):
            options = body[5:].split("|")
            if len(options) < 2 or any(not o.strip() for o in options):
                err(path, f"{where}: bad pick placeholder {{{body}}} (want 2+ non-empty '|' options)")
        else:
            err(path, f"{where}: unknown placeholder {{{body}}} (supported: n:, pick:)")
    if text.count("{") != len(TEMPLATE_RE.findall(text)):
        err(path, f"{where}: unbalanced braces in text")


def check_line(path, node, where):
    if node.get("sfx") is not None and node["sfx"] not in SFX:
        err(path, f"{where}: unknown sfx '{node['sfx']}' (allowed: {sorted(SFX)})")
    if not isinstance(node.get("source"), str) or not node["source"]:
        err(path, f"{where}: missing 'source'")
    if not isinstance(node.get("text"), str) or not node["text"]:
        err(path, f"{where}: missing 'text'")
    else:
        check_templates(path, node["text"], where)


def check_trigger(path, trigger):
    contexts = trigger.get("contexts", {})
    for key in contexts:
        if key not in CONTEXT_KEYS:
            err(path, f"unknown context '{key}' (allowed: {sorted(CONTEXT_KEYS)})")
    if "tripModes" in contexts:
        check_enum(path, contexts["tripModes"], TRIP_MODES, "tripModes")
    if "personalities" in contexts:
        check_enum(path, contexts["personalities"], PERSONALITIES, "personalities")
    if "timeOfDay" in contexts:
        check_enum(path, contexts["timeOfDay"], TIMES, "timeOfDay")
    if "daysOfWeek" in contexts:
        check_enum(path, contexts["daysOfWeek"], DAYS, "daysOfWeek")
    if "weather" in contexts:
        check_enum(path, contexts["weather"], WEATHER, "weather")
    if "tripPhase" in contexts:
        check_enum(path, contexts["tripPhase"], PHASES, "tripPhase")
    if "stopsRemaining" in contexts:
        check_range(path, contexts["stopsRemaining"], "stopsRemaining")
    if "voyagePhase" in contexts:
        check_enum(path, contexts["voyagePhase"], {"outbound", "returning"}, "voyagePhase")
    if "milesToDestination" in contexts:
        check_range(path, contexts["milesToDestination"], "milesToDestination")
    if "states" in contexts:
        v = contexts["states"]
        if not isinstance(v, list) or not v or not all(isinstance(x, str) and len(x) == 2 for x in v):
            err(path, "states must be a list of 2-letter codes (e.g. [\"OH\"])")
    for field in ("speedMPH", "tripDistanceMiles"):
        if field in contexts:
            check_range(path, contexts[field], field)
    for field in ("weight", "cooldownMinutes", "maxPerTrip"):
        if field in trigger and not isinstance(trigger[field], (int, float)):
            err(path, f"trigger.{field} must be a number")


def check_content(path, event):
    etype, content = event["type"], event.get("content")
    if not isinstance(content, dict):
        err(path, "missing 'content' object")
        return
    if etype == "single":
        check_line(path, content, "content")
        responses = content.get("responses", [])
        if not isinstance(responses, list) or len(responses) > 2:
            err(path, "responses must be a list of at most 2 quick replies")
        else:
            for i, r in enumerate(responses):
                if not r.get("label"):
                    err(path, f"responses[{i}]: missing 'label'")
                reaction = r.get("reaction")
                if not isinstance(reaction, dict):
                    err(path, f"responses[{i}]: missing 'reaction' object")
                else:
                    check_line(path, reaction, f"responses[{i}].reaction")
    elif etype == "sequence":
        steps = content.get("steps")
        if not isinstance(steps, list) or not steps:
            err(path, "sequence content needs a non-empty 'steps' list")
            return
        for i, step in enumerate(steps):
            if "wait" in step:
                if not isinstance(step["wait"], dict) or not set(step["wait"]) <= {"seconds", "miles"}:
                    err(path, f"steps[{i}].wait must have 'seconds' and/or 'miles'")
            else:
                check_line(path, step, f"steps[{i}]")
    elif etype == "branching":
        nodes = content.get("nodes")
        entry = content.get("entry")
        if not isinstance(nodes, dict) or not nodes:
            err(path, "branching content needs a 'nodes' object")
            return
        if entry not in nodes:
            err(path, f"entry '{entry}' is not a node")
        targets = set()
        for name, node in nodes.items():
            check_line(path, node, f"node '{name}'")
            nexts = []
            for c in node.get("choices", []):
                has_next, has_one_of = "next" in c, "nextOneOf" in c
                if has_next == has_one_of:
                    err(path, f"node '{name}': each choice needs exactly one of 'next' or 'nextOneOf'")
                if has_next:
                    nexts.append(c["next"])
                if has_one_of:
                    if not isinstance(c["nextOneOf"], list) or len(c["nextOneOf"]) < 2:
                        err(path, f"node '{name}': nextOneOf needs 2+ node ids")
                    else:
                        nexts.extend(c["nextOneOf"])
            if len(node.get("choices", [])) > 3:
                err(path, f"node '{name}': max 3 choices (driver-safe glanceable UI)")
            for c in node.get("choices", []):
                if not c.get("phrases") or not c.get("label"):
                    err(path, f"node '{name}': every choice needs 'label' and 'phrases'")
            if "next" in node:
                nexts.append(node["next"])
            if "timeoutNext" in node:
                nexts.append(node["timeoutNext"])
                if "timeoutSeconds" not in node:
                    err(path, f"node '{name}': timeoutNext without timeoutSeconds")
            if not nexts and not node.get("choices"):
                err(path, f"node '{name}': dead end — needs choices, next, or 'end'")
            for target in nexts:
                if target != "end" and target not in nodes:
                    err(path, f"node '{name}': next '{target}' does not exist")
                targets.add(target)
        unreachable = set(nodes) - targets - {entry}
        if unreachable:
            err(path, f"unreachable nodes: {sorted(unreachable)}")


def main():
    files = sorted(EVENTS_DIR.rglob("*.json"))
    if not files:
        print(f"No event files found under {EVENTS_DIR}")
        return 0
    seen_ids = {}
    for path in files:
        try:
            event = json.loads(path.read_text())
        except json.JSONDecodeError as e:
            err(path, f"invalid JSON: {e}")
            continue
        for field in ("schema", "id", "title", "author", "type"):
            if field not in event:
                err(path, f"missing required field '{field}'")
        if event.get("class") is not None and event["class"] not in {"ambient", "plot"}:
            err(path, "class must be 'ambient' or 'plot'")
        if event.get("type") not in TYPES:
            err(path, f"type must be one of {sorted(TYPES)}")
            continue
        eid = event.get("id", "")
        if eid != path.stem:
            err(path, f"id '{eid}' must match filename '{path.stem}'")
        if eid in seen_ids:
            err(path, f"duplicate id '{eid}' (also in {seen_ids[eid]})")
        seen_ids[eid] = path.name
        check_trigger(path, event.get("trigger", {}))
        check_content(path, event)

    if errors:
        print(f"❌ {len(errors)} problem(s):")
        for e in errors:
            print(f"  - {e}")
        return 1
    print(f"✅ {len(files)} event file(s) valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
