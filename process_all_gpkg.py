"""
Traite TOUS les .gpkg dans ~/Downloads/ et génère des tuiles propres.
Pour chaque tuile 0.5°x0.5°, accumule les features de TOUS les feuillets
qui la couvrent — pas d'écrasement, merge complet.
"""
import os, json, gzip, glob, zipfile, tempfile, hashlib
import geopandas as gpd
from shapely.geometry import box

GPKG_DIR   = os.path.expanduser("~/Downloads")
OUTPUT_DIR = os.path.expanduser("~/EcoMap_tiles_final")
TILE_SIZE  = 0.5
COLS = ["type_couv", "gr_ess", "cl_age", "cl_drai", "origine", "type_eco",
        "dep_sur", "code_couv", "cl_dens", "superficie", "geometry"]

os.makedirs(OUTPUT_DIR, exist_ok=True)

# Accumulation en mémoire: {(lat, lon): [features...]}
tiles = {}

def geom_hash(geom):
    return hashlib.md5(json.dumps(geom, sort_keys=True).encode()).hexdigest()

def process_gpkg(gpkg_path, nom):
    print(f"\n=== {nom} ===", flush=True)
    gdf = gpd.read_file(gpkg_path, layer=1)
    gdf = gdf[[c for c in COLS if c in gdf.columns]].copy()
    gdf = gdf[gdf["type_couv"].notna()]
    print(f"  {len(gdf)} polygones bruts", flush=True)
    gdf = gdf.to_crs("EPSG:4326")
    gdf["geometry"] = gdf["geometry"].simplify(0.0002, preserve_topology=True)
    gdf = gdf[~gdf["geometry"].is_empty]

    bounds = gdf.total_bounds
    lon = round(bounds[0] - (bounds[0] % TILE_SIZE), 1)
    tile_count = 0
    while lon < bounds[2]:
        lat = round(bounds[1] - (bounds[1] % TILE_SIZE), 1)
        while lat < bounds[3]:
            clipped = gdf[gdf.intersects(box(lon, lat, lon+TILE_SIZE, lat+TILE_SIZE))].copy()
            if not clipped.empty:
                geojson = json.loads(clipped.to_json())
                for feat in geojson['features']:
                    geom = feat['geometry']
                    if geom['type'] == 'Polygon':
                        geom['coordinates'] = [[[round(x,4),round(y,4)] for x,y in ring] for ring in geom['coordinates']]
                    elif geom['type'] == 'MultiPolygon':
                        geom['coordinates'] = [[[[round(x,4),round(y,4)] for x,y in ring] for ring in poly] for poly in geom['coordinates']]

                key = (round(lat,1), round(lon,1))
                if key not in tiles:
                    tiles[key] = {}
                for feat in geojson['features']:
                    h = geom_hash(feat['geometry'])
                    if h not in tiles[key]:
                        tiles[key][h] = feat
                tile_count += 1
            lat = round(lat + TILE_SIZE, 1)
        lon = round(lon + TILE_SIZE, 1)
    print(f"  {tile_count} tuiles contribuées", flush=True)

# Trouve tous les .gpkg ou .zip contenant un .gpkg
sources = glob.glob(os.path.join(GPKG_DIR, "*.gpkg"))
zips    = glob.glob(os.path.join(GPKG_DIR, "CARTE_ECO_MAJ_*.zip"))

print(f"Trouvé: {len(sources)} .gpkg directs, {len(zips)} .zip\n")

tmp_dirs = []
for z in zips:
    nom = os.path.basename(z).replace("CARTE_ECO_MAJ_","").replace("_GPKG.zip","")
    tmp = tempfile.mkdtemp()
    tmp_dirs.append(tmp)
    with zipfile.ZipFile(z) as zf:
        zf.extractall(tmp)
    gpkg = next((os.path.join(tmp,f) for f in os.listdir(tmp) if f.endswith(".gpkg")), None)
    if gpkg:
        sources.append(gpkg)
        print(f"Extrait: {nom}")

for gpkg in sources:
    nom = os.path.basename(gpkg).replace(".gpkg","")
    try:
        process_gpkg(gpkg, nom)
    except Exception as e:
        print(f"  ERREUR: {e}", flush=True)

# Sauvegarde finale
print(f"\nSauvegarde de {len(tiles)} tuiles...", flush=True)
total_feat = 0
for (lat, lon), feat_dict in sorted(tiles.items()):
    features = list(feat_dict.values())
    total_feat += len(features)

    lat_sign = "" if lat >= 0 else "m"
    lon_sign = "" if lon >= 0 else "m"
    lat_str = f"{abs(lat):.1f}".replace(".","d")
    lon_str = f"{abs(lon):.1f}".replace(".","d")
    fname = f"{lat_str}_{lon_sign}{lon_str}.geojson.gz"
    path = os.path.join(OUTPUT_DIR, fname)

    geojson = {"type": "FeatureCollection", "features": features}
    with gzip.open(path, "wt", encoding="utf-8") as f:
        json.dump(geojson, f, separators=(',',':'))

print(f"\n=== TERMINÉ ===")
print(f"  {len(tiles)} tuiles")
print(f"  {total_feat:,} polygones total")
print(f"  Dossier: {OUTPUT_DIR}")

# Nettoyage
import shutil
for d in tmp_dirs:
    shutil.rmtree(d, ignore_errors=True)
