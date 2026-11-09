#!/usr/bin/env python3
"""One-off: add the Journey redesign prompts (15 scenes, 5 map nodes, 4 map regions) to prompts.json."""
import json
import pathlib

P = pathlib.Path(__file__).resolve().parent / "prompts.json"
d = json.loads(P.read_text(encoding="utf-8"))

COMP = ("Composition: calm darker center and lower 40 percent (soft shadow, ground, no busy detail), "
        "interest in the upper half and the edges, strong dark vignette, clear horizontal light-to-dark flow, "
        "no people, no characters, no text, no letters, no logos, kid-friendly")

scenes = {
    "dusty_road_a": "wide landscape backdrop, a sandy gravel road at golden dusk with a plain wooden signpost (no writing) and dry grass",
    "dusty_road_b": "wide landscape backdrop, a gravel crossroads with a hitching post and a lantern on a pole at dusk",
    "dusty_road_in": "wide landscape backdrop, a gravel crossroads clearing with a stone campfire ring, a parked cart and long shadows at dusk",
    "wildflower_meadow_a": "wide landscape backdrop, rolling fields of wildflowers in the evening with far hills and a warm sky",
    "wildflower_meadow_b": "wide landscape backdrop, a path through tall wildflowers and a stone wall with a wooden gate in the evening",
    "wildflower_meadow_in": "wide landscape backdrop, the middle of a flower meadow with a ring of standing stones and drifting fireflies at dusk",
    "willow_bridge_a": "wide landscape backdrop, a calm river and a distant stone bridge under willow trees at dusk",
    "willow_bridge_b": "wide landscape backdrop, the foot of an arched stone bridge with hanging lanterns and willow branches at dusk",
    "willow_bridge_in": "wide landscape backdrop, the middle of a stone bridge with water below, willow branches and lanterns on the rails at dusk",
    "mountain_pass_a": "wide landscape backdrop, a switchback trail climbing rocky slopes with pine trees and snowy peaks under a sunset sky",
    "mountain_pass_b": "wide landscape backdrop, a narrow mountain ledge with a wooden rope railing and a lantern at sunset",
    "mountain_pass_in": "wide landscape backdrop, a rocky overlook ledge with a small campfire, a crooked pine and a huge view of peaks at sunset",
    "tavern_gate_a": "wide landscape backdrop, a big cozy tavern on a hill seen from the road at dusk, every window glowing warmly",
    "tavern_gate_b": "wide landscape backdrop, a stone gate arch with hanging lanterns and cobblestones leading toward a glowing tavern at dusk",
    "tavern_gate_in": "wide landscape backdrop, a lantern-lit courtyard just inside a tavern gate with a stone fountain, barrels and warm light spilling from the main doors",
}
for key, text in scenes.items():
    d["scene_subjects"][key] = f"{text}. {COMP}"

d["map_node_subjects"].update({
    "dusty_road": "a wooden signpost on a gravel road",
    "wildflower_meadow": "a patch of bright wildflowers with a butterfly",
    "willow_bridge": "a small arched stone bridge over water",
    "mountain_pass": "a snowy peak with a winding trail",
    "tavern_gate": "a lantern-lit stone gate arch",
})

d["map_region_subjects"].update({
    "region_road": "a sandy gravel road, dry grass, scattered stones, a wooden signpost and a campfire ring, beige and tan tones, seen from above",
    "region_meadow": "wildflower fields, hedgerows, and a walled lantern garden with fairy lights and flower beds, seen from above",
    "region_river": "a gentle winding river, willow trees, reeds and a stone bridge, seen from above",
    "region_tavern": "a big cozy tavern on a hill with warm glowing windows, a lantern-lit gate, a courtyard and cobblestone steps, seen from above",
})

P.write_text(json.dumps(d, indent=2, ensure_ascii=False), encoding="utf-8")
print("scenes", len(d["scene_subjects"]), "nodes", len(d["map_node_subjects"]), "regions", len(d["map_region_subjects"]))
