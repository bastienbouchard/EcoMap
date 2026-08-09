"""
Traite CARTE_ECO_MAJ_PROV.gpkg → tuiles 0.5°x0.5° pour le Québec.
Couche: pee_maj_prov (9.8M polygones, EPSG:32198)
Usage: python3 process_prov.py [LAT_MIN LAT_MAX]
"""
import os, sys, json, gzip
import numpy as np
import geopandas as gpd
from shapely.geometry import box
from pyproj import Transformer

GPKG  = os.path.expanduser("~/Downloads/CARTE_ECO_MAJ_PROV.gpkg")
OUT   = os.path.expanduser("~/EcoMap_tiles_v5")
LAYER = "pee_maj_prov"
STEP  = 0.5

# Emprise Québec (WGS84) — peut être surchargée par argv
LAT_MIN_DEF, LAT_MAX_DEF = 44.5, 57.0
LON_MIN, LON_MAX = -80.0, -57.0

LAT_MIN, LAT_MAX = LAT_MIN_DEF, LAT_MAX_DEF

# Méridien central EPSG:32198 (Lambert Québec) — y minimum pour une latitude donnée
CENTRAL_MERIDIAN = -68.5

os.makedirs(OUT, exist_ok=True)

to_32198 = Transformer.from_crs("EPSG:4326", "EPSG:32198", always_xy=True)
to_wgs84 = Transformer.from_crs("EPSG:32198", "EPSG:4326", always_xy=True)

def bbox_32198(lon_min, lat_min, lon_max, lat_max):
    """
    Calcule la bbox en EPSG:32198 pour une région WGS84.
    Inclut le méridien central pour corriger le biais Lambert
    (les y minimaux se trouvent au méridien central, pas aux coins).
    """
    xs, ys = [], []
    lons = [lon_min, lon_max]
    if lon_min < CENTRAL_MERIDIAN < lon_max:
        lons.append(CENTRAL_MERIDIAN)
    for lon in lons:
        for lat in [lat_min, lat_max]:
            x, y = to_32198.transform(lon, lat)
            xs.append(x); ys.append(y)
    return (min(xs), min(ys), max(xs), max(ys))

# Colonnes à garder
KEEP = ["type_couv", "gr_ess", "cl_age", "cl_haut", "cl_dens",
        "origine", "an_origine", "perturb", "an_perturb",
        "cl_drai", "dep_sur", "type_eco", "co_ter",
        "geocode", "reb_ess1", "reb_ess2", "geometry"]

lats = []
lat = LAT_MIN
while lat < LAT_MAX:
    lats.append(round(lat, 1))
    lat = round(lat + STEP, 1)

tile_count = 0
feat_count = 0

for lat in lats:
    native_bbox = bbox_32198(LON_MIN, lat - 0.1, LON_MAX, lat + STEP + 0.1)
    try:
        band = gpd.read_file(GPKG, layer=LAYER, bbox=native_bbox)
    except Exception as e:
        print(f"Erreur bande {lat}°N: {e}", flush=True)
        continue

    if band.empty:
        continue

    band = band[[c for c in KEEP if c in band.columns]].copy()
    band = band[~band.geometry.is_empty & band.geometry.notna()]
    # Filtre < 1 ha en EPSG:32198 (métrique) — polygones invisibles à l'écran
    band = band[band.geometry.area >= 10000]

    if band.empty:
        continue

    # Centroïdes en EPSG:32198 (précis) → convertir en WGS84
    centroids_32198 = band.geometry.centroid
    clons_arr, clats_arr = to_wgs84.transform(
        centroids_32198.x.values, centroids_32198.y.values
    )

    # Convertir géométries en WGS84 et simplifier
    band = band.to_crs("EPSG:4326")
    band["_clat"] = clats_arr
    band["_clon"] = clons_arr
    band["geometry"] = band["geometry"].simplify(0.0002, preserve_topology=True)
    band = band[~band.geometry.is_empty]
    band = band[band.geometry.geom_type.isin(["Polygon", "MultiPolygon"])]

    if band.empty:
        continue

    tiles_in_band = 0
    lon = LON_MIN
    while lon < LON_MAX:
        lon = round(lon, 1)
        mask = (
            (band["_clon"] >= lon) & (band["_clon"] < lon + STEP) &
            (band["_clat"] >= lat) & (band["_clat"] < lat + STEP)
        )
        clip = band[mask].drop(columns=["_clat", "_clon"])

        if not clip.empty:
            gj = json.loads(clip.to_json())
            for feat in gj['features']:
                geom = feat['geometry']
                if geom['type'] == 'Polygon':
                    geom['coordinates'] = [
                        [[round(x,4), round(y,4)] for x,y in ring]
                        for ring in geom['coordinates']
                    ]
                elif geom['type'] == 'MultiPolygon':
                    geom['coordinates'] = [
                        [[[round(x,4), round(y,4)] for x,y in ring] for ring in poly]
                        for poly in geom['coordinates']
                    ]

            lat_str  = f"{abs(lat):.1f}".replace(".", "d")
            lon_sign = "m" if lon < 0 else ""
            lon_str  = f"{abs(lon):.1f}".replace(".", "d")
            fname = f"{lat_str}_{lon_sign}{lon_str}.geojson.gz"

            with gzip.open(os.path.join(OUT, fname), "wt", encoding="utf-8") as f:
                json.dump(gj, f, separators=(',', ':'))

            n = len(gj['features'])
            feat_count += n
            tile_count += 1
            tiles_in_band += 1
            print(f"  {lat_str}_{lon_sign}{lon_str}: {n}", flush=True)

        lon = round(lon + STEP, 1)

    print(f"Bande {lat}°N: {tiles_in_band} tuiles", flush=True)

print(f"\n=== TERMINÉ: {tile_count} tuiles, {feat_count:,} polygones → {OUT}")
