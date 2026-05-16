"""
Corrige les tuiles pour UN seul feuillet (passé en argument).
Usage: python3 fix_one_feuillet.py 32A "ROBERVAL"
"""
import sys, os, json, gzip, tempfile, zipfile, warnings
import requests
import geopandas as gpd
from shapely.geometry import box

warnings.filterwarnings("ignore")

OUTPUT_DIR = os.path.expanduser("~/EcoMap_tiles")
TILE_SIZE = 0.5

def _url(code):
    return (
        f"https://diffusion.mffp.gouv.qc.ca/Diffusion/DonneeGratuite/Foret/"
        f"DONNEES_FOR_ECO_SUD/Cartes_ecoforestieres_perturbations/02-Donnees/"
        f"Decoupage250K/{code}/CARTE_ECO_MAJ_{code}_GPKG.zip"
    )

COLS = ["type_couv", "gr_ess", "cl_age", "cl_drai", "origine", "type_eco", "superficie", "geometry"]


def load_tile(path):
    if not os.path.exists(path):
        return []
    with gzip.open(path, 'rt') as f:
        data = json.load(f)
    return data.get("features", [])


def save_tile(path, features):
    with gzip.open(path, 'wt') as f:
        json.dump({"type": "FeatureCollection", "features": features}, f)


def process(code, nom):
    print(f"=== {code} - {nom} ===", flush=True)
    with tempfile.TemporaryDirectory() as tmp:
        zip_path = os.path.join(tmp, "f.zip")
        url = _url(code)
        print(f"  Téléchargement...", flush=True)
        resp = requests.get(url, stream=True, verify=False, timeout=600)
        resp.raise_for_status()
        total = int(resp.headers.get("content-length", 0))
        done = 0
        with open(zip_path, "wb") as f:
            for chunk in resp.iter_content(1024*1024):
                f.write(chunk); done += len(chunk)
                if total: print(f"\r  {done/total*100:.0f}%", end="", flush=True)
        print()

        with zipfile.ZipFile(zip_path) as z:
            z.extractall(tmp)
        gpkg = next(os.path.join(tmp, f) for f in os.listdir(tmp) if f.endswith(".gpkg"))

        print("  Lecture...", flush=True)
        gdf = gpd.read_file(gpkg, layer=1)
        gdf = gdf[[c for c in COLS if c in gdf.columns]].copy()
        gdf = gdf[gdf["type_couv"].notna()]
        gdf = gdf.to_crs("EPSG:4326")
        gdf["geometry"] = gdf["geometry"].simplify(0.0002, preserve_topology=True)
        gdf = gdf[~gdf["geometry"].is_empty]
        print(f"  {len(gdf)} polygones — bbox: lat {gdf.total_bounds[1]:.2f}-{gdf.total_bounds[3]:.2f}, lon {gdf.total_bounds[0]:.2f}-{gdf.total_bounds[2]:.2f}", flush=True)

        bounds = gdf.total_bounds
        lon_start = round(bounds[0] - (bounds[0] % TILE_SIZE), 1)
        lat_start = round(bounds[1] - (bounds[1] % TILE_SIZE), 1)
        updated = 0

        lon = lon_start
        while lon < bounds[2]:
            lat = lat_start
            while lat < bounds[3]:
                clipped = gdf[gdf.intersects(box(lon, lat, lon+TILE_SIZE, lat+TILE_SIZE))].copy()
                if not clipped.empty:
                    tile_id = f"{lat:.1f}_{lon:.1f}".replace("-","m").replace(".","d")
                    path = os.path.join(OUTPUT_DIR, f"{tile_id}.geojson.gz")
                    existing = load_tile(path)
                    new_feats = json.loads(clipped.to_json())["features"]

                    seen = set()
                    for feat in existing:
                        try:
                            c = feat['geometry']['coordinates'][0][0]
                            seen.add((round(c[0],4), round(c[1],4)))
                        except: pass

                    added = 0
                    for feat in new_feats:
                        try:
                            c = feat['geometry']['coordinates'][0][0]
                            key = (round(c[0],4), round(c[1],4))
                            if key not in seen:
                                existing.append(feat); seen.add(key); added += 1
                        except:
                            existing.append(feat); added += 1

                    if added > 0:
                        save_tile(path, existing)
                        print(f"  {tile_id}: +{added} → {len(existing)} polygones", flush=True)
                        updated += 1
                lat = round(lat + TILE_SIZE, 1)
            lon = round(lon + TILE_SIZE, 1)

        print(f"  {updated} tuiles mises à jour\n", flush=True)


if __name__ == "__main__":
    code = sys.argv[1]
    nom = sys.argv[2] if len(sys.argv) > 2 else code
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    process(code, nom)
