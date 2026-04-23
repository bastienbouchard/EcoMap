import geopandas as gpd
from shapely.geometry import Point
import os

lat, lon = 48.429, -71.068
rayon_km = 5

print("Chargement...")
gdf = gpd.read_file(
    r"C:\Users\basti\ecomap\data\PRODUITS_IEQM_22D.gpkg",
    layer="pee_ori"
)

gdf = gdf.to_crs("EPSG:4326")

centre = Point(lon, lat)
gdf_zone = gdf[gdf.geometry.distance(centre) < rayon_km / 111]

cols = ['geocode', 'type_couv', 'gr_ess', 'cl_age', 'cl_haut', 
        'origine', 'type_eco', 'cl_drai', 'dep_sur', 'geometry']
gdf_zone = gdf_zone[cols]

print(f"Polygones dans la zone: {len(gdf_zone)}")

os.makedirs('assets', exist_ok=True)
gdf_zone.to_file("assets/eco_zone.geojson", driver="GeoJSON")
print("assets/eco_zone.geojson créé!")