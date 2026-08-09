"""
Traitement des NOUVEAUX feuillets écoforestiers (manquants de la 1ère passe).
Sauvegarde dans ~/EcoMap_tiles_new/ pour upload différentiel.
"""
import os, json, gzip, tempfile, zipfile, requests, geopandas as gpd
from shapely.geometry import box

OUTPUT_DIR = os.path.expanduser("~/EcoMap_tiles_new")
TILE_SIZE = 0.5

COLS = ["type_couv", "gr_ess", "cl_age", "cl_drai", "origine", "type_eco",
        "dep_sur", "code_couv", "cl_dens", "superficie", "geometry"]

NOUVEAUX = [
    ("21E", "SHERBROOKE"),
    ("21K", "BAIE DES CHALEURS"),
    ("21L", "AMQUI"),
    ("21M", "MATANE"),
    ("21N", "RIVIÈRE-DU-LOUP"),
    ("21O", "RIMOUSKI"),
    ("22A", "SEPT-ÎLES"),
    ("22B", "HAVRE-SAINT-PIERRE"),
    ("22C", "NATASHQUAN"),
    ("22D", "RIVIÈRE NATASHQUAN"),
    ("22E", "LAC WALKER"),
    ("22F", "RIVIÈRE MOISIE"),
    ("22H", "WABUSH"),
    ("22J", "RIVIÈRE AUX GRAINES"),
    ("22K", "SCHEFFERVILLE NORD"),
    ("22L", "LAC CANIAPISCAU"),
    ("22M", "LAC MINTO"),
    ("22N", "RIVIÈRE KOGALUK"),
    ("22O", "LAC BIENVILLE NORD"),
    ("22P", "LAC NAOCOCANE"),
    ("31A", "LAC ONTARIO"),
    ("31B", "SHEFFIELD"),
    ("31F", "MONTREAL"),
    ("31G", "PEMBROKE"),
    ("31H", "LAC MEMPHRÉMAGOG"),
    ("31J", "TEMISCOUATA"),
    ("31K", "RIVIÈRE-DU-LOUP SUD"),
    ("31L", "MANIWAKI"),
    ("31O", "TÉMISCAMINGUE"),
    ("31P", "NORTH BAY"),
    ("32A", "SAULT STE MARIE"),
    ("32B", "KAPUSKASING"),
    ("32C", "HEARST"),
    ("32G", "LAC OPASATICA"),
    ("32J", "MATAGAMI"),
    ("32K", "LAC EVANS"),
    ("32L", "LAC BIENVILLE"),
    ("32O", "LAC DES LOUPS MARINS"),
    ("32P", "LAC MINTO SUD"),
]

def _url(code):
    return f"https://diffusion.mffp.gouv.qc.ca/Diffusion/DonneeGratuite/Foret/DONNEES_FOR_ECO_SUD/Cartes_ecoforestieres_perturbations/02-Donnees/Decoupage250K/{code}/CARTE_ECO_MAJ_{code}_GPKG.zip"

def download_gpkg(url, tmp_dir):
    zip_path = os.path.join(tmp_dir, "feuillet.zip")
    print(f"  Téléchargement...", flush=True)
    resp = requests.get(url, stream=True, verify=False, timeout=600)
    resp.raise_for_status()
    total = int(resp.headers.get("content-length", 0))
    downloaded = 0
    with open(zip_path, "wb") as f:
        for chunk in resp.iter_content(chunk_size=1024*1024):
            f.write(chunk)
            downloaded += len(chunk)
            if total:
                print(f"\r  {downloaded/total*100:.0f}%", end="", flush=True)
    print()
    with zipfile.ZipFile(zip_path) as z:
        z.extractall(tmp_dir)
    return next(os.path.join(tmp_dir, f) for f in os.listdir(tmp_dir) if f.endswith(".gpkg"))

def process(code, nom, url):
    print(f"\n=== {code} - {nom} ===", flush=True)
    with tempfile.TemporaryDirectory() as tmp:
        gpkg = download_gpkg(url, tmp)
        gdf = gpd.read_file(gpkg, layer=1)
        gdf = gdf[[c for c in COLS if c in gdf.columns]].copy()
        gdf = gdf[gdf["type_couv"].notna()]
        print(f"  {len(gdf)} polygones", flush=True)
        gdf = gdf.to_crs("EPSG:4326")
        gdf["geometry"] = gdf["geometry"].simplify(0.0002, preserve_topology=True)
        gdf = gdf[~gdf["geometry"].is_empty]

        bounds = gdf.total_bounds
        lon_start = round(bounds[0] - (bounds[0] % TILE_SIZE), 1)
        lat_start = round(bounds[1] - (bounds[1] % TILE_SIZE), 1)
        lon, tile_count = lon_start, 0
        while lon < bounds[2]:
            lat = lat_start
            while lat < bounds[3]:
                clipped = gdf[gdf.intersects(box(lon, lat, lon+TILE_SIZE, lat+TILE_SIZE))].copy()
                if not clipped.empty:
                    tile_id = f"{lat:.1f}_{lon:.1f}".replace("-","m").replace(".","d")
                    path = os.path.join(OUTPUT_DIR, f"{tile_id}.geojson.gz")
                    if os.path.exists(path):
                        print(f"  {tile_id}: déjà présent, skip")
                        tile_count += 1
                        lat += TILE_SIZE
                        continue
                    geojson = json.loads(clipped.to_json())
                    for feat in geojson['features']:
                        geom = feat['geometry']
                        if geom['type'] == 'Polygon':
                            geom['coordinates'] = [[[round(x,4),round(y,4)] for x,y in ring] for ring in geom['coordinates']]
                        elif geom['type'] == 'MultiPolygon':
                            geom['coordinates'] = [[[[round(x,4),round(y,4)] for x,y in ring] for ring in poly] for poly in geom['coordinates']]
                    with gzip.open(path, "wt", encoding="utf-8") as f:
                        json.dump(geojson, f, separators=(',',':'))
                    print(f"  {tile_id}: {os.path.getsize(path)//1024} KB", flush=True)
                    tile_count += 1
                lat += TILE_SIZE
            lon += TILE_SIZE
        print(f"  {tile_count} tuiles", flush=True)

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for code, nom in NOUVEAUX:
        try:
            process(code, nom, _url(code))
        except Exception as e:
            print(f"ERREUR {code}: {e}", flush=True)

    tiles = [f for f in os.listdir(OUTPUT_DIR) if f.endswith(".gz")]
    total_mb = sum(os.path.getsize(os.path.join(OUTPUT_DIR, f)) for f in tiles) / 1024 / 1024
    print(f"\n=== TERMINÉ — {len(tiles)} tuiles, {total_mb:.0f} MB ===")
    print(f"Dossier: {OUTPUT_DIR}")

if __name__ == "__main__":
    main()
