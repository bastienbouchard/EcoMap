import json
import math
import os
import tempfile
import zipfile

import geopandas as gpd
import requests
from firebase_functions import https_fn
from firebase_functions.options import set_global_options, MemoryOption, CorsOptions
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
    memory=MemoryOption.GB_4,
    timeout_sec=540,
    cors=CorsOptions(cors_origins="*", cors_methods=["GET"]),
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


_TILE_SOURCES = {
    "patp": "https://servicescarto.mern.gouv.qc.ca/pes/services/Territoire/PATP_prov_WMS/MapServer/export",
    "cadastre": "https://geo.environnement.gouv.qc.ca/donnees/rest/services/Reference/Cadastre_allege/MapServer/export",
}

def _tile_to_bbox(z: int, x: int, y: int):
    n = 2 ** z
    earth = 20037508.343
    x_min = x / n * 2 * earth - earth
    x_max = (x + 1) / n * 2 * earth - earth
    y_max = earth - y / n * 2 * earth
    y_min = earth - (y + 1) / n * 2 * earth
    return x_min, y_min, x_max, y_max


@https_fn.on_request(
    timeout_sec=30,
    memory=MemoryOption.MB_256,
    cors=CorsOptions(cors_origins="*", cors_methods=["GET"]),
)
def tile_proxy(req: https_fn.Request) -> https_fn.Response:
    layer = req.args.get("layer", "")
    if layer not in _TILE_SOURCES:
        return https_fn.Response("layer invalide", status=400)
    try:
        z = int(req.args["z"])
        x = int(req.args["x"])
        y = int(req.args["y"])
    except (KeyError, ValueError):
        return https_fn.Response("z, x, y requis", status=400)

    x_min, y_min, x_max, y_max = _tile_to_bbox(z, x, y)
    url = _TILE_SOURCES[layer]
    params = {
        "bbox": f"{x_min},{y_min},{x_max},{y_max}",
        "bboxSR": "3857",
        "layers": "show:0",
        "transparent": "true",
        "format": "png32",
        "f": "image",
        "size": "256,256",
    }
    try:
        resp = requests.get(url, params=params, timeout=20, verify=False)
        if resp.status_code != 200:
            return https_fn.Response("Erreur source", status=502)
        return https_fn.Response(
            resp.content,
            status=200,
            mimetype="image/png",
            headers={"Cache-Control": "public, max-age=86400"},
        )
    except Exception as e:
        return https_fn.Response(str(e), status=502)
