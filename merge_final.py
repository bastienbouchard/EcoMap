"""
Combine les tuiles provinciales (à jour) et les tuiles par feuillet.
Priorité: provincial si ≥ 100 polygones, sinon meilleur feuillet disponible.
Résultat dans ~/EcoMap_tiles_upload/
"""
import os, gzip, json

PROV_DIR    = os.path.expanduser("~/EcoMap_tiles_final")   # provincial à jour
OLD_DIR     = os.path.expanduser("~/EcoMap_tiles")          # feuillets originaux
NEW_DIR     = os.path.expanduser("~/EcoMap_tiles_new")      # feuillets supplémentaires
OUT_DIR     = os.path.expanduser("~/EcoMap_tiles_upload")
PROV_MIN    = 100  # seuil: si provincial a moins que ça, on prend le feuillet

os.makedirs(OUT_DIR, exist_ok=True)

def count_features(path):
    try:
        with gzip.open(path, 'rt') as f:
            return len(json.load(f).get('features', []))
    except:
        return 0

def copy_gz(src, dst):
    with open(src, 'rb') as f:
        data = f.read()
    with open(dst, 'wb') as f:
        f.write(data)

# Collecte tous les noms de tuiles connus
all_tiles = set()
for d in [PROV_DIR, OLD_DIR, NEW_DIR]:
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.endswith('.geojson.gz'):
                all_tiles.add(f)

print(f"{len(all_tiles)} tuiles uniques au total\n")

stats = {'prov': 0, 'feuillet': 0}

for fname in sorted(all_tiles):
    prov_path = os.path.join(PROV_DIR, fname)
    old_path  = os.path.join(OLD_DIR, fname)
    new_path  = os.path.join(NEW_DIR, fname)
    out_path  = os.path.join(OUT_DIR, fname)

    n_prov = count_features(prov_path) if os.path.exists(prov_path) else 0

    if n_prov >= PROV_MIN:
        copy_gz(prov_path, out_path)
        print(f"  PROV  {fname}: {n_prov}")
        stats['prov'] += 1
    else:
        # Prend le meilleur feuillet disponible
        best_path, best_n = None, 0
        for p in [old_path, new_path]:
            if os.path.exists(p):
                n = count_features(p)
                if n > best_n:
                    best_n, best_path = n, p

        if best_path and best_n > n_prov:
            copy_gz(best_path, out_path)
            print(f"  FEUI  {fname}: {best_n} (prov={n_prov})")
            stats['feuillet'] += 1
        elif n_prov > 0:
            copy_gz(prov_path, out_path)
            print(f"  PROV* {fname}: {n_prov} (sparse mais seul dispo)")
            stats['prov'] += 1
        # sinon: aucune donnée utilisable, on skip

total = stats['prov'] + stats['feuillet']
print(f"\n=== TERMINÉ ===")
print(f"  {stats['prov']} tuiles depuis fichier provincial")
print(f"  {stats['feuillet']} tuiles depuis feuillets individuels")
print(f"  {total} tuiles totales → {OUT_DIR}")
