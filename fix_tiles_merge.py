"""
Corrige les tuiles incomplètes en fusionnant les polygones de plusieurs feuillets.
Relance les feuillets qui couvrent la zone 48-50°N (Monts Valin, nord Lac St-Jean).
"""
import os, json, gzip, tempfile, zipfile, warnings
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

# Feuillets qui couvrent la zone problématique (48-50°N)
FEUILLETS = [
    ("22D", "CHICOUTIMI"),
    ("22E", "RÉSERVOIR PIPMUACAN"),
    ("22L", "LAC PÉRIBONCA"),
    ("32A", "ROBERVAL"),
    ("32H", "RIVIÈRE MISTASSINI"),
    ("22C", "RIVIÈRE-DU-LOUP"),
    ("22B", "BAIE-COMEAU"),
    ("21M", "BAIE-SAINT-PAUL"),
]

COLS = ["type_couv", "gr_ess", "cl_age", "cl_drai", "origine", "type_eco", "superficie", "geometry"]


def load_tile(path):
    """Charge une tuile existante, retourne une liste de features GeoJSON."""
    if not os.path.exists(path):
        return []
    with gzip.open(path, "rt", encoding="utf-8") as f:
        data = json.load(f)
    return data.get("features", [])


def save_tile(path, features):
    geojson = {"type": "FeatureCollection", "features": features}
    with gzip.open(path, "wt", encoding="utf-8") as f:
        json.dump(geojson, f)


def download_gpkg(url, tmp_dir):
    zip_path = os.path.join(tmp_dir, "feuillet.zip")
    print(f"  Téléchargement {url.split('/')[-1]}...", flush=True)
    resp = requests.get(url, stream=True, verify=False, timeout=600)
    resp.raise_for_status()
    total = int(resp.headers.get("content-length", 0))
    downloaded = 0
    with open(zip_path, "wb") as f:
        for chunk in resp.iter_content(chunk_size=1024 * 1024):
            f.write(chunk)
            downloaded += len(chunk)
            if total:
                print(f"\r  {downloaded/total*100:.0f}%", end="", flush=True)
    print()
    with zipfile.ZipFile(zip_path, "r") as z:
        z.extractall(tmp_dir)
    return next(os.path.join(tmp_dir, f) for f in os.listdir(tmp_dir) if f.endswith(".gpkg"))


def process_feuillet(code, nom):
    print(f"\n=== {code} - {nom} ===", flush=True)
    url = _url(code)
    with tempfile.TemporaryDirectory() as tmp:
        try:
            gpkg = download_gpkg(url, tmp)
        except Exception as e:
            print(f"  IGNORÉ: {e}", flush=True)
            return

        print("  Lecture des polygones...", flush=True)
        gdf = gpd.read_file(gpkg, layer=1)
        gdf = gdf[[c for c in COLS if c in gdf.columns]].copy()
        gdf = gdf[gdf["type_couv"].notna()]
        print(f"  {len(gdf)} polygones forestiers", flush=True)
        gdf = gdf.to_crs("EPSG:4326")
        gdf["geometry"] = gdf["geometry"].simplify(0.0002, preserve_topology=True)
        gdf = gdf[~gdf["geometry"].is_empty]

        bounds = gdf.total_bounds  # minx, miny, maxx, maxy
        print(f"  Étendue: lat {bounds[1]:.2f}-{bounds[3]:.2f}, lon {bounds[0]:.2f}-{bounds[2]:.2f}", flush=True)

        lon_start = round(bounds[0] - (bounds[0] % TILE_SIZE), 1)
        lat_start = round(bounds[1] - (bounds[1] % TILE_SIZE), 1)

        tiles_updated = 0
        lon = lon_start
        while lon < bounds[2]:
            lat = lat_start
            while lat < bounds[3]:
                tile_box = box(lon, lat, lon + TILE_SIZE, lat + TILE_SIZE)
                clipped = gdf[gdf.intersects(tile_box)].copy()
                if not clipped.empty:
                    tile_id = f"{lat:.1f}_{lon:.1f}".replace("-", "m").replace(".", "d")
                    path = os.path.join(OUTPUT_DIR, f"{tile_id}.geojson.gz")

                    # Charger les features existantes
                    existing_features = load_tile(path)
                    new_features = json.loads(clipped.to_json())["features"]

                    # Fusionner (dédoublonner par géométrie approximative)
                    existing_geoms = set()
                    for feat in existing_features:
                        coords = feat.get("geometry", {}).get("coordinates", [])
                        if coords:
                            try:
                                first = coords[0][0]
                                existing_geoms.add((round(first[0], 4), round(first[1], 4)))
                            except (IndexError, TypeError):
                                pass

                    added = 0
                    for feat in new_features:
                        coords = feat.get("geometry", {}).get("coordinates", [])
                        if coords:
                            try:
                                first = coords[0][0]
                                key = (round(first[0], 4), round(first[1], 4))
                                if key not in existing_geoms:
                                    existing_features.append(feat)
                                    existing_geoms.add(key)
                                    added += 1
                            except (IndexError, TypeError):
                                existing_features.append(feat)
                                added += 1

                    if added > 0:
                        save_tile(path, existing_features)
                        size = os.path.getsize(path) / 1024
                        print(f"  {tile_id}: +{added} polygones (total {len(existing_features)}, {size:.0f} KB)", flush=True)
                        tiles_updated += 1

                lat = round(lat + TILE_SIZE, 1)
            lon = round(lon + TILE_SIZE, 1)

        print(f"  {tiles_updated} tuiles mises à jour pour {code}", flush=True)


if __name__ == "__main__":
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for code, nom in FEUILLETS:
        try:
            process_feuillet(code, nom)
        except Exception as e:
            print(f"ERREUR {code}: {e}", flush=True)
    print("\n=== FUSION TERMINÉE ===")
    tiles = [f for f in os.listdir(OUTPUT_DIR) if f.endswith(".gz")]
    print(f"{len(tiles)} tuiles dans {OUTPUT_DIR}")
