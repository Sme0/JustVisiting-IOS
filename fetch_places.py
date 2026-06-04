#!/usr/bin/env python3
"""Fetches UK settlements from the Overpass API and writes places.json
in the format expected by PlacesManager (array of {id, name, lat, lon, type})."""

import json
import subprocess
import sys

QUERY = """[out:json][timeout:180];
(
  node["place"~"^(city|town|village|hamlet)$"](49.9,-8.6,60.9,1.8);
);
out body;
"""

OUT_PATH = "JustVisiting/places.json"

print("Querying Overpass API — this usually takes 60–120 seconds…", flush=True)

result = subprocess.run(
    [
        "curl", "-sk", "--max-time", "210",
        "-H", "User-Agent: JustVisiting-DataScript/1.0",
        "-G", "https://overpass-api.de/api/interpreter",
        "--data-urlencode", f"data={QUERY}",
    ],
    capture_output=True,
)

if result.returncode != 0:
    print(f"ERROR: curl exited {result.returncode}: {result.stderr.decode()}", file=sys.stderr)
    sys.exit(1)

try:
    raw = json.loads(result.stdout)
except json.JSONDecodeError as e:
    print(f"ERROR parsing JSON: {e}", file=sys.stderr)
    print(result.stdout[:500], file=sys.stderr)
    sys.exit(1)

places = []
for el in raw.get("elements", []):
    tags = el.get("tags", {})
    name = tags.get("name")
    place_type = tags.get("place")
    if name and place_type in ("city", "town", "village", "hamlet"):
        places.append({
            "id":   el["id"],
            "name": name,
            "lat":  el["lat"],
            "lon":  el["lon"],
            "type": place_type,
        })

print(f"Fetched {len(places):,} places. Writing {OUT_PATH}…", flush=True)

with open(OUT_PATH, "w", encoding="utf-8") as f:
    json.dump(places, f, ensure_ascii=False, separators=(",", ":"))

print("Done.", flush=True)
