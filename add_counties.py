#!/usr/bin/env python3
"""Adds a 'county' field to every entry in JustVisiting/places.json.

Downloads the ONS Counties and Unitary Authorities boundaries (UK, Dec 2023)
as GeoJSON, builds a shapely STRtree index, and assigns each place the name
of the county/UA it falls inside. Places outside any boundary get "".
"""

import json
import subprocess
import sys

from shapely.geometry import Point, shape
from shapely.strtree import STRtree

PLACES_PATH = "JustVisiting/places.json"

ONS_URL = (
    "https://services1.arcgis.com/ESMARspQHYMw9BZ9/arcgis/rest/services"
    "/Counties_and_Unitary_Authorities_December_2023_Boundaries_UK_BUC"
    "/FeatureServer/0/query"
    "?where=1%3D1&outFields=CTYUA23NM&outSR=4326&f=geojson&resultRecordCount=500"
)

# ── 1. Download ONS boundary GeoJSON ─────────────────────────────────────────

print("Downloading ONS county/UA boundaries…", flush=True)
r = subprocess.run(
    ["curl", "-sk", "--max-time", "30", ONS_URL],
    capture_output=True,
)
if r.returncode != 0:
    print(f"curl error: {r.stderr.decode()}", file=sys.stderr)
    sys.exit(1)

geojson = json.loads(r.stdout)
features = geojson["features"]
print(f"  Downloaded {len(features)} county/UA polygons.", flush=True)

# ── 2. Build shapely geometries + STRtree ─────────────────────────────────────

geometries = []
names = []
for feat in features:
    name = feat["properties"].get("CTYUA23NM", "")
    try:
        geom = shape(feat["geometry"])
        if not geom.is_valid:
            geom = geom.buffer(0)
        if geom.is_valid and not geom.is_empty:
            geometries.append(geom)
            names.append(name)
    except Exception:
        pass

print(f"  Built {len(geometries)} valid geometries.", flush=True)
tree = STRtree(geometries)

# ── 3. Load places ────────────────────────────────────────────────────────────

print(f"Loading {PLACES_PATH}…", flush=True)
with open(PLACES_PATH, encoding="utf-8") as f:
    places = json.load(f)

# ── 4. Assign counties ────────────────────────────────────────────────────────

print(f"Assigning counties to {len(places):,} places…", flush=True)
matched = 0
for place in places:
    pt = Point(place["lon"], place["lat"])
    candidates = tree.query(pt, predicate="within")
    if len(candidates):
        idx = int(candidates[0]) if len(candidates) == 1 else min(
            candidates, key=lambda i: geometries[i].centroid.distance(pt)
        )
        place["county"] = names[idx]
        matched += 1
    else:
        place["county"] = ""

print(f"  Matched {matched:,} / {len(places):,}  ({matched*100//len(places)}%)", flush=True)

# ── 5. Write ──────────────────────────────────────────────────────────────────

print(f"Writing {PLACES_PATH}…", flush=True)
with open(PLACES_PATH, "w", encoding="utf-8") as f:
    json.dump(places, f, ensure_ascii=False, separators=(",", ":"))

print("Done.", flush=True)
