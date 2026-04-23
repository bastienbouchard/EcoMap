import geopandas as gpd
from shapely.geometry import Point
import os

# ── MODIFIE CES VALEURS SELON TON SECTEUR ──────────────────────
lat, lon = 48.2917, -71.322  # Centre du secteur (latitude, longitude)
rayon_km = 20                # Rayon d'extraction en km
# ───────────────────────────────────────────────────────────────

print(f"Chargement... (centre: {lat}, {lon} — rayon: {rayon_km} km)")
gdf = gpd.read_file(
    r"C:\Users\basti\ecomap\data\PRODUITS_IEQM_22D.gpkg",
    layer="pee_ori"
)

gdf = gdf.to_crs("EPSG:4326")

centre = Point(lon, lat)
gdf_zone = gdf[gdf.geometry.distance(centre) < rayon_km / 111]

# Toutes les colonnes utilisées par l'app
cols_disponibles = gdf_zone.columns.tolist()
cols_voulues = ['geocode', 'type_couv', 'gr_ess', 'cl_age', 'cl_haut',
                'origine', 'type_eco', 'cl_drai', 'cl_pent', 'dep_sur',
                'code_couv', 'milieu', 'geometry']
cols = [c for c in cols_voulues if c in cols_disponibles]

gdf_zone = gdf_zone[cols]

# Simplifier les géométries pour réduire la taille du fichier (~33m de précision)
print("Simplification des géométries...")
gdf_zone.geometry = gdf_zone.geometry.simplify(0.0003)
gdf_zone = gdf_zone[~gdf_zone.geometry.is_empty]

print(f"Polygones dans la zone: {len(gdf_zone)}")
print(f"Colonnes: {cols}")

os.makedirs('assets', exist_ok=True)
gdf_zone.to_file("assets/eco_zone.geojson", driver="GeoJSON")

taille = os.path.getsize("assets/eco_zone.geojson") / 1024 / 1024
print(f"assets/eco_zone.geojson créé! ({taille:.1f} MB)")

