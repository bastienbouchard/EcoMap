#!/usr/bin/env python3
"""Vérifie quelles tuiles sont présentes sur le CDN R2 pour le Québec."""

import math
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

CDN = 'https://pub-5c51ef289e6943dbb647c2a2d1baa3bf.r2.dev'

# Zone couverte (zone forestière méridionale Québec — chasse orignal)
LAT_MIN, LAT_MAX = 45.0, 53.0
LON_MIN, LON_MAX = -80.0, -60.0


def tile_name(lat, lon):
    lat_floor = math.floor(lat * 2) / 2
    lon_floor = math.floor(lon * 2) / 2
    lat_int = math.floor(lat_floor)
    lat_frac = round((lat_floor - lat_int) * 10)
    lon_abs = abs(lon_floor)
    lon_int = math.floor(lon_abs)
    lon_frac = round((lon_abs - lon_int) * 10)
    lon_sign = 'm' if lon < 0 else ''
    return f"{lat_int}d{lat_frac}_{lon_sign}{lon_int}d{lon_frac}.geojson.gz"


def build_tile_list():
    tiles = []
    lat = math.floor(LAT_MIN * 2) / 2
    while lat < LAT_MAX:
        lon = math.floor(LON_MIN * 2) / 2
        while lon < LON_MAX:
            tiles.append((lat, lon, tile_name(lat, lon)))
            lon += 0.5
        lat += 0.5
    return tiles


def check(item):
    lat, lon, fname = item
    url = f"{CDN}/{fname}"
    try:
        req = urllib.request.Request(url, method='HEAD')
        resp = urllib.request.urlopen(req, timeout=15)
        size = resp.headers.get('Content-Length', '?')
        return (lat, lon, fname, True, 200, size)
    except urllib.error.HTTPError as e:
        return (lat, lon, fname, False, e.code, 0)
    except Exception as e:
        return (lat, lon, fname, False, -1, str(e))


def main():
    tiles = build_tile_list()
    print(f"Vérification de {len(tiles)} tuiles sur {CDN}")
    print("(Ceci prend ~30 secondes)\n")

    present = []
    missing = []
    errors = []

    with ThreadPoolExecutor(max_workers=40) as ex:
        futures = {ex.submit(check, t): t for t in tiles}
        done = 0
        for f in as_completed(futures):
            result = f.result()
            lat, lon, fname, ok, code, extra = result
            done += 1
            if done % 100 == 0:
                print(f"  {done}/{len(tiles)}...")
            if ok:
                present.append((lat, lon, fname, extra))
            elif code == 404:
                missing.append((lat, lon, fname))
            else:
                errors.append((lat, lon, fname, code))

    print(f"\n{'='*50}")
    print(f"Présentes : {len(present)}")
    print(f"Absentes  : {len(missing)}")
    print(f"Erreurs   : {len(errors)}")
    print('='*50)

    if missing:
        print(f"\n⚠️  {len(missing)} tuiles MANQUANTES :\n")
        by_lat = {}
        for lat, lon, fname in missing:
            by_lat.setdefault(lat, []).append((lon, fname))
        for lat in sorted(by_lat):
            lons = by_lat[lat]
            print(f"  Lat {lat}° : {len(lons)} manquantes")
            for lon, fname in sorted(lons):
                print(f"    - {fname}  (lon {lon}°)")

    if errors:
        print(f"\n⚠️  {len(errors)} erreurs réseau :")
        for lat, lon, fname, code in errors[:10]:
            print(f"  {fname}: code {code}")

    # Résumé par zone de latitude
    print(f"\n📊 Couverture par tranche de latitude :")
    all_lats = sorted(set(lat for lat, _, _ in tiles))
    for lat in all_lats:
        n_total = sum(1 for l, _, _ in tiles if l == lat)
        n_present = sum(1 for l, _, _, _ in present if l == lat)
        pct = int(n_present / n_total * 100) if n_total else 0
        bar = '█' * (pct // 5) + '░' * (20 - pct // 5)
        print(f"  {lat:5.1f}° N  [{bar}] {n_present}/{n_total}")

    # Export liste manquantes
    if missing:
        with open('tuiles_manquantes.txt', 'w') as f:
            for _, _, fname in sorted(missing):
                f.write(fname + '\n')
        print(f"\n💾 Liste exportée dans tuiles_manquantes.txt")


if __name__ == '__main__':
    main()
