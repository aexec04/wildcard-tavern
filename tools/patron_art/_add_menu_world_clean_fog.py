"""Register menu_fog_edge_clean in prompts.json (menu_world_subjects). The image is NOT generated: it is
tools/despill_menu_world.py applied to menu_fog_edge.png (pink halo removed), so the prompt text is only a label."""
import json
import pathlib

P = pathlib.Path(__file__).with_name("prompts.json")
d = json.loads(P.read_text(encoding="utf-8"))
d["menu_world_subjects"]["menu_fog_edge_clean"] = (
    "DERIVED, not generated: menu_fog_edge with the pink halo despilled by tools/despill_menu_world.py (never regenerate this id)"
)
P.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok")
