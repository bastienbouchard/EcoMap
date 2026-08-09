"""
Fusionne EcoMap_tiles/ (ancien) + EcoMap_tiles_new/ (nouveau) en prenant
TOUS les polygones des deux sources pour chaque tuile.
Résultat dans ~/EcoMap_tiles_merged/
"""
import os, gzip, json, hashlib

OLD_DIR = os.path.expanduser("~/EcoMap_tiles")
NEW_DIR = os.path.expanduser("~/EcoMap_tiles_new")
OUT_DIR = os.path.expanduser("~/EcoMap_tiles_merged")
os.makedirs(OUT_DIR, exist_ok=True)

def read_tile(path):
    with gzip.open(path, 'rt', encoding='utf-8') as f:
        return json.load(f)

def geom_hash(geom):
    return hashlib.md5(json.dumps(geom, sort_keys=True).encode()).hexdigest()

all_tiles = set()
for f in os.listdir(OLD_DIR):
    if f.endswith('.geojson.gz'): all_tiles.add(f)
for f in os.listdir(NEW_DIR):
    if f.endswith('.geojson.gz'): all_tiles.add(f)

print(f"{len(all_tiles)} tuiles à traiter\n")

stats = {'merged': 0, 'old_only': 0, 'new_only': 0}

for fname in sorted(all_tiles):
    old_path = os.path.join(OLD_DIR, fname)
    new_path = os.path.join(NEW_DIR, fname)
    out_path = os.path.join(OUT_DIR, fname)

    has_old = os.path.exists(old_path)
    has_new = os.path.exists(new_path)

    if has_old and has_new:
        old_data = read_tile(old_path)
        new_data = read_tile(new_path)

        seen = set()
        features = []
        for feat in old_data['features'] + new_data['features']:
            h = geom_hash(feat['geometry'])
            if h not in seen:
                seen.add(h)
                features.append(feat)

        result = {'type': 'FeatureCollection', 'features': features}
        n_old = len(old_data['features'])
        n_new = len(new_data['features'])
        n_merged = len(features)
        print(f"  {fname}: {n_old} + {n_new} → {n_merged} polygones")
        stats['merged'] += 1

    elif has_old:
        result = read_tile(old_path)
        stats['old_only'] += 1
    else:
        result = read_tile(new_path)
        stats['new_only'] += 1

    with gzip.open(out_path, 'wt', encoding='utf-8') as f:
        json.dump(result, f, separators=(',', ':'))

print(f"\n=== TERMINÉ ===")
print(f"  Fusionnées: {stats['merged']}")
print(f"  Ancien seulement: {stats['old_only']}")
print(f"  Nouveau seulement: {stats['new_only']}")
print(f"  Total: {sum(stats.values())} tuiles dans {OUT_DIR}")
