import json
import os
import tempfile
import zipfile

import geopandas as gpd
import requests
from firebase_functions import https_fn
from firebase_functions.options import set_global_options
from shapely.geometry import box

set_global_options(max_instances=5)

_FEUILLETS_INDEX = None

FEUILLETS_INDEX_URL = (
    "https://raw.githubusercontent.com/bastienbouchard/EcoMap/master/assets/feuillets_index.geojson"
)


def _load_index():
    global _FEUILLETS_INDEX
    if _FEUILLETS_INDEX is None:
        resp = requests.get(FEUILLETS_INDEX_URL, timeout=30)
        resp.raise_for_status()
        _FEUILLETS_INDEX = gpd.GeoDataFrame.from_features(
            resp.json()["features"], crs="EPSG:4326"
        )
    return _FEUILLETS_INDEX


def _find_feuillets(bbox):
    index = _load_index()
    return index[index.intersects(bbox)]


def _download_and_clip(lien_gpkg, bbox):
    with tempfile.TemporaryDirectory() as tmp:
        zip_path = os.path.join(tmp, "feuillet.zip")
        resp = requests.get(lien_gpkg, stream=True, verify=False, timeout=300)
        resp.raise_for_status()
        with open(zip_path, "wb") as f:
            for chunk in resp.iter_content(chunk_size=1024 * 1024):
                f.write(chunk)

        with zipfile.ZipFile(zip_path, "r") as z:
            z.extractall(tmp)

        gpkg_file = next(
            os.path.join(tmp, f) for f in os.listdir(tmp) if f.endswith(".gpkg")
        )

        cols = ["type_couv", "gr_ess", "cl_age", "cl_drai", "origine", "type_eco", "superficie", "geometry"]
        gdf = gpd.read_file(gpkg_file, layer=1, bbox=bbox.bounds)
        gdf = gdf[[c for c in cols if c in gdf.columns]].copy()
        gdf = gdf[gdf["type_couv"].notna()]
        gdf = gdf.to_crs("EPSG:4326")
        gdf["geometry"] = gdf["geometry"].simplify(0.0002, preserve_topology=True)
        gdf = gdf[~gdf["geometry"].is_empty]
        return gdf


@https_fn.on_request(
    memory=https_fn.options.MemoryOption.GB_4,
    timeout_sec=540,
    cors=https_fn.options.CorsOptions(cors_origins="*", cors_methods=["GET"]),
)
def get_ecoforestier(req: https_fn.Request) -> https_fn.Response:
    try:
        min_lat = float(req.args.get("min_lat"))
        min_lon = float(req.args.get("min_lon"))
        max_lat = float(req.args.get("max_lat"))
        max_lon = float(req.args.get("max_lon"))
    except (TypeError, ValueError):
        return https_fn.Response(
            json.dumps({"error": "Paramètres requis: min_lat, min_lon, max_lat, max_lon"}),
            status=400,
            mimetype="application/json",
        )

    bbox = box(min_lon, min_lat, max_lon, max_lat)
    feuillets = _find_feuillets(bbox)

    if feuillets.empty:
        return https_fn.Response(
            json.dumps({"error": "Aucun feuillet pour cette zone"}),
            status=404,
            mimetype="application/json",
        )

    gdfs = []
    for _, row in feuillets.iterrows():
        try:
            gdf = _download_and_clip(row["Lien_GPKG"], bbox)
            gdfs.append(gdf)
        except Exception as e:
            print(f"Erreur feuillet {row['Feuillet250K']}: {e}")

    if not gdfs:
        return https_fn.Response(
            json.dumps({"error": "Téléchargement impossible"}),
            status=502,
            mimetype="application/json",
        )

    result = gpd.pd.concat(gdfs) if len(gdfs) > 1 else gdfs[0]
    return https_fn.Response(result.to_json(), mimetype="application/json")
