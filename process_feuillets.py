"""
Script de traitement des feuillets écoforestiers pour la Zone 28.
Télécharge les GPKG, découpe en tuiles 0.5°x0.5°, exporte en GeoJSON compressé.
Lancer: python3 process_feuillets.py
"""
import os
import json
import gzip
import tempfile
import zipfile
import requests
import geopandas as gpd
from shapely.geometry import box

OUTPUT_DIR = os.path.expanduser("~/EcoMap_tiles")
TILE_SIZE = 0.5  # degrés (~50km)

def _url(code):
    return f"https://diffusion.mffp.gouv.qc.ca/Diffusion/DonneeGratuite/Foret/DONNEES_FOR_ECO_SUD/Cartes_ecoforestieres_perturbations/02-Donnees/Decoupage250K/{code}/CARTE_ECO_MAJ_{code}_GPKG.zip"

FEUILLETS = [
    # ── Zone 28 (déjà traités, seront ignorés si tuile existe) ──────────────
    ("32J", "LAC ASSINICA"),
    ("32I", "BAIE ABATAGOUCHE"),
    ("22L", "LAC PÉRIBONCA"),
    ("32G", "CHIBOUGAMAU"),
    ("32H", "RIVIÈRE MISTASSINI"),
    ("22E", "RÉSERVOIR PIPMUACAN"),
    ("32B", "RÉSERVOIR GOUIN"),
    ("32A", "ROBERVAL"),
    ("22D", "CHICOUTIMI"),
    ("31P", "LA TUQUE"),
    ("21M", "BAIE-SAINT-PAUL"),

    # ── Laurentides / Lanaudière ─────────────────────────────────────────────
    ("31O", "MONT-LAURIER"),
    ("31N", "LAC NOMININGUE"),
    ("31J", "LAC SIMON"),
    ("31K", "RIVIÈRE GATINEAU"),

    # ── Outaouais ────────────────────────────────────────────────────────────
    ("31G", "OTTAWA"),
    ("31F", "PEMBROKE"),

    # ── Abitibi-Témiscamingue ────────────────────────────────────────────────
    ("32C", "SENNETERRE"),
    ("32D", "ROUYN-NORANDA"),
    ("32E", "LAC MATAGAMI"),
    ("32F", "MATAGAMI"),

    # ── Mauricie / Centre-du-Québec ──────────────────────────────────────────
    ("31I", "MATTAWA"),
    ("31H", "TROIS-RIVIÈRES"),

    # ── Charlevoix / Côte-Nord ouest ────────────────────────────────────────
    ("22C", "RIVIÈRE-DU-LOUP"),
    ("22B", "BAIE-COMEAU"),
    ("22A", "RIMOUSKI"),

    # ── Côte-Nord centre ─────────────────────────────────────────────────────
    ("22F", "SEPT-ÎLES"),
    ("22G", "RIVIÈRE MOISIE"),
    ("22H", "SCHEFFERVILLE SUD"),
    ("22I", "NATASHQUAN"),

    # ── Gaspésie / Bas-Saint-Laurent ────────────────────────────────────────
    ("21N", "MATANE"),
    ("21O", "GASPÉ"),
    ("21P", "PERCÉ"),
    ("21E", "AMQUI"),
    ("21L", "TÉMISCOUATA"),

    # ── Estrie / Bois-Francs (limite sud) ───────────────────────────────────
    ("21C", "SHERBROOKE"),
    ("31C", "MONTREAL SUD"),
]

COLS = ["type_couv", "gr_ess", "cl_age", "cl_drai", "origine", "type_eco", "superficie", "geometry"]


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
                pct = downloaded / total * 100
                print(f"\r  {pct:.0f}%", end="", flush=True)
    print()
    with zipfile.ZipFile(zip_path, "r") as z:
        z.extractall(tmp_dir)
    return next(os.path.join(tmp_dir, f) for f in os.listdir(tmp_dir) if f.endswith(".gpkg"))


def process_feuillet(code, nom, url):
    done_marker = os.path.join(OUTPUT_DIR, f".done_{code}")
    if os.path.exists(done_marker):
        print(f"\n=== {code} - {nom} — déjà fait, ignoré ===", flush=True)
        return
    print(f"\n=== {code} - {nom} ===", flush=True)
    with tempfile.TemporaryDirectory() as tmp:
        gpkg = download_gpkg(url, tmp)
        print("  Lecture des polygones...", flush=True)
        gdf = gpd.read_file(gpkg, layer=1)
        gdf = gdf[[c for c in COLS if c in gdf.columns]].copy()
        gdf = gdf[gdf["type_couv"].notna()]
        print(f"  {len(gdf)} polygones forestiers", flush=True)
        gdf = gdf.to_crs("EPSG:4326")
        gdf["geometry"] = gdf["geometry"].simplify(0.0002, preserve_topology=True)
        gdf = gdf[~gdf["geometry"].is_empty]

        bounds = gdf.total_bounds  # minx, miny, maxx, maxy
        lon_start = round(bounds[0] - (bounds[0] % TILE_SIZE), 1)
        lat_start = round(bounds[1] - (bounds[1] % TILE_SIZE), 1)
        lon_end = bounds[2]
        lat_end = bounds[3]

        lon = lon_start
        tile_count = 0
        while lon < lon_end:
            lat = lat_start
            while lat < lat_end:
                tile_box = box(lon, lat, lon + TILE_SIZE, lat + TILE_SIZE)
                clipped = gdf[gdf.intersects(tile_box)].copy()
                if not clipped.empty:
                    tile_id = f"{lat:.1f}_{lon:.1f}".replace("-", "m").replace(".", "d")
                    path = os.path.join(OUTPUT_DIR, f"{tile_id}.geojson.gz")
                    if not os.path.exists(path):
                        geojson = clipped.to_json()
                        with gzip.open(path, "wt", encoding="utf-8") as f:
                            f.write(geojson)
                        size = os.path.getsize(path) / 1024
                        print(f"  Tuile {tile_id}: {size:.0f} KB", flush=True)
                        tile_count += 1
                lat += TILE_SIZE
            lon += TILE_SIZE
        print(f"  {tile_count} tuiles créées pour {code}", flush=True)
        open(done_marker, 'w').close()  # marque ce feuillet comme terminé


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print(f"Dossier de sortie: {OUTPUT_DIR}")
    print(f"Taille des tuiles: {TILE_SIZE}° (~50km)\n")

    for code, nom in FEUILLETS:
        try:
            process_feuillet(code, nom, _url(code))
        except requests.exceptions.HTTPError as e:
            print(f"  IGNORÉ {code}: {e}", flush=True)
        except Exception as e:
            print(f"ERREUR {code}: {e}", flush=True)

    tiles = [f for f in os.listdir(OUTPUT_DIR) if f.endswith(".gz")]
    total_mb = sum(os.path.getsize(os.path.join(OUTPUT_DIR, f)) for f in tiles) / 1024 / 1024
    print(f"\n=== TERMINÉ ===")
    print(f"{len(tiles)} tuiles, {total_mb:.0f} MB total")
    print(f"Dossier: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
