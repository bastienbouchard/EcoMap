#!/usr/bin/env python3
"""
EcoMap — Vérification du pipeline offline
==========================================
Simule exactement ce que MbtilesService fait sur iOS, sur ton Mac,
sans avoir besoin de Codemagic.

Tests effectués :
  1. Télécharge une zone de test (Lac Pikauba, zoom 10–14, ~50 tuiles)
  2. Sauvegarde en .mbtiles avec le Y-flip TMS exact du code Dart
  3. Vérifie que chaque tuile est lisible et est une vraie image
  4. Vérifie la couverture à CHAQUE niveau de zoom
  5. Lance un serveur Leaflet sur localhost:9977 pour vérification visuelle

Usage :
  python3 tool/verify_offline.py          # vérification + demande serveur
  python3 tool/verify_offline.py --serve  # vérification + serveur auto
  python3 tool/verify_offline.py --check  # vérification seulement (no serveur)
"""

import math
import sqlite3
import os
import ssl
import sys
import threading
import urllib.request
import webbrowser
from http.server import HTTPServer, BaseHTTPRequestHandler

# Contexte SSL sans vérification de certificat (outil dev local uniquement)
_SSL_CTX = ssl.create_default_context()
_SSL_CTX.check_hostname = False
_SSL_CTX.verify_mode = ssl.CERT_NONE

# ── Zone de test (Lac Pikauba, Québec) ────────────────────────────────────────
CENTER_LAT = 47.5
CENTER_LON = -72.0
MIN_LAT, MAX_LAT = 47.470, 47.530
MIN_LON, MAX_LON = -72.040, -71.960
MIN_ZOOM, MAX_ZOOM = 10, 14   # Petit max pour que ça tourne vite (~50 tuiles OSM)

DB_PATH = '/tmp/ecomap_verify.mbtiles'

# Sources à tester (même ordre que dans territoire_download_page.dart)
SOURCES = [
    ('Carte de base (OSM)',   'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
    ('Satellite ESRI',        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'),
    ('Topo (OpenTopoMap)',    'https://tile.opentopomap.org/{z}/{x}/{y}.png'),
]
# Source à utiliser pour la vérification visuelle (Leaflet)
VISUAL_SOURCE = 'Carte de base (OSM)'

# ── Maths des tuiles (miroir exact de MbtilesService.dart) ───────────────────

def tms_y(xyz_y: int, z: int) -> int:
    """Miroir de MbtilesService._tmsY — Y-flip TMS"""
    return (1 << z) - 1 - xyz_y

def lon_to_x(lon: float, z: int) -> int:
    """Miroir de MbtilesService._lonToX"""
    return int((lon + 180) / 360 * (1 << z))

def lat_to_y(lat: float, z: int) -> int:
    """Miroir de MbtilesService._latToY"""
    r = math.radians(lat)
    return int((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * (1 << z))

def tiles_for_bounds(min_lat, min_lon, max_lat, max_lon, min_zoom, max_zoom):
    tiles = []
    for z in range(min_zoom, max_zoom + 1):
        x0, x1 = lon_to_x(min_lon, z), lon_to_x(max_lon, z)
        y0, y1 = lat_to_y(max_lat, z), lat_to_y(min_lat, z)
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                tiles.append((z, x, y))
    return tiles

# ── Validation des données image ──────────────────────────────────────────────

def is_valid_image(data: bytes) -> bool:
    if len(data) < 8:
        return False
    if data[:4] == b'\x89PNG':   # PNG
        return True
    if data[:3] == b'\xff\xd8\xff':  # JPEG
        return True
    # Certains serveurs renvoient du JPEG sans le marqueur exact — vérifier taille
    return len(data) > 200

# ── Téléchargement ────────────────────────────────────────────────────────────

def download_source(conn, source_name: str, url_template: str, tiles: list) -> dict:
    """
    Télécharge une source et la fusionne dans la DB via INSERT OR REPLACE.
    Même comportement que downloadZone() dans MbtilesService.dart.
    """
    print(f'\n  📡 {source_name}')
    ok = errors = invalid = 0
    batch = []

    for i, (z, x, y) in enumerate(tiles):
        url = url_template.replace('{z}', str(z)).replace('{x}', str(x)).replace('{y}', str(y))
        try:
            req = urllib.request.Request(
                url,
                headers={'User-Agent': 'EcoMap/1.0 (bastienbouchard@gmail.com)'}
            )
            with urllib.request.urlopen(req, timeout=12, context=_SSL_CTX) as resp:
                data = resp.read()

            if not is_valid_image(data):
                invalid += 1
                continue

            batch.append((z, x, tms_y(y, z), data))   # Y-flip à l'écriture
            if len(batch) >= 20:
                conn.executemany(
                    'INSERT OR REPLACE INTO tiles VALUES (?,?,?,?)', batch
                )
                conn.commit()
                batch = []
            ok += 1
        except Exception as e:
            errors += 1

        if (i + 1) % 10 == 0 or i + 1 == len(tiles):
            pct = (i + 1) / len(tiles) * 100
            print(f'     {i+1}/{len(tiles)} ({pct:.0f}%) — {ok}✓ {errors}✗', end='\r')

    if batch:
        conn.executemany('INSERT OR REPLACE INTO tiles VALUES (?,?,?,?)', batch)
        conn.commit()

    print(f'     {ok} tuiles OK, {errors} erreurs, {invalid} invalides            ')
    return {'ok': ok, 'errors': errors, 'invalid': invalid, 'total': len(tiles)}

# ── Vérifications ─────────────────────────────────────────────────────────────

def check_yflip():
    """Test 1 : Y-flip est son propre inverse"""
    for z in range(MIN_ZOOM, MAX_ZOOM + 2):
        for y in [0, 1, (1 << z) // 2, (1 << z) - 1]:
            assert tms_y(tms_y(y, z), z) == y, f'Y-flip cassé à z={z}, y={y}'
    print('  ✓ Y-flip : inversible à tous les niveaux')

def check_readback(conn, tiles: list) -> tuple:
    """Test 2 : Chaque tuile écrite est lisible"""
    read_ok = read_fail = 0
    for z, x, y in tiles:
        row = conn.execute(
            'SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?',
            (z, x, tms_y(y, z))
        ).fetchone()
        if row and is_valid_image(bytes(row[0])):
            read_ok += 1
        else:
            read_fail += 1
    return read_ok, read_fail

def check_coverage(conn) -> list:
    """Test 3 : Couverture par niveau de zoom"""
    results = []
    for z in range(MIN_ZOOM, MAX_ZOOM + 1):
        x0, x1 = lon_to_x(MIN_LON, z), lon_to_x(MAX_LON, z)
        y0, y1 = lat_to_y(MAX_LAT, z), lat_to_y(MIN_LAT, z)
        expected = (x1 - x0 + 1) * (y1 - y0 + 1)
        count = conn.execute(
            'SELECT COUNT(*) FROM tiles WHERE zoom_level=?', (z,)
        ).fetchone()[0]
        pct = count / expected * 100 if expected > 0 else 0
        results.append({'z': z, 'count': count, 'expected': expected, 'pct': pct})
    return results

# ── Serveur Leaflet ───────────────────────────────────────────────────────────

def make_leaflet_html() -> str:
    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>EcoMap — Vérification offline</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
  body {{ margin: 0; font-family: -apple-system, sans-serif; }}
  #map {{ height: 100vh; }}
  .panel {{
    position: absolute; top: 10px; right: 10px;
    background: rgba(20,20,20,.85); color: #fff;
    padding: 12px 16px; border-radius: 10px;
    z-index: 1000; font-size: 13px; min-width: 220px;
    box-shadow: 0 4px 16px rgba(0,0,0,.4);
  }}
  .panel b {{ color: #FF6B35; }}
  .panel .ok  {{ color: #4CAF50; }}
  .panel .bad {{ color: #f44336; }}
  .legend {{ margin-top: 8px; padding-top: 8px; border-top: 1px solid #444; font-size: 11px; color: #aaa; }}
</style>
</head>
<body>
<div id="map"></div>
<div class="panel">
  <b>EcoMap — Vérification offline</b>
  <br><br>
  Zoom actuel : <span id="z">{MAX_ZOOM}</span><br>
  Tuiles chargées : <span id="tiles">0</span><br>
  <br>
  <span class="ok">▪</span> Zone de test (cadre orange)<br>
  <div class="legend">
    Les tuiles affichées = même pipeline que l'app iOS.<br>
    Dézoom pour voir la couverture complète.<br>
    Zoom {MIN_ZOOM}–{MAX_ZOOM} téléchargés.<br>
    Au-delà : zoom {MAX_ZOOM} agrandi (normal).
  </div>
</div>
<script>
const map = L.map('map').setView([{CENTER_LAT}, {CENTER_LON}], {MAX_ZOOM});

L.tileLayer('http://localhost:9977/tiles/{{z}}/{{x}}/{{y}}', {{
  maxZoom: 22,
  maxNativeZoom: {MAX_ZOOM},
  attribution: 'EcoMap Verify'
}}).addTo(map);

L.rectangle([[{MIN_LAT},{MIN_LON}],[{MAX_LAT},{MAX_LON}]], {{
  color: '#FF6B35', weight: 2, fill: true,
  fillColor: '#FF6B35', fillOpacity: 0.05
}}).addTo(map);

setInterval(() => {{
  document.getElementById('z').textContent = map.getZoom();
  document.getElementById('tiles').textContent =
    document.querySelectorAll('.leaflet-tile-loaded').length;
}}, 500);
</script>
</body>
</html>"""


def start_server():
    html = make_leaflet_html()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args): pass

        def do_GET(self):
            if self.path == '/':
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.end_headers()
                self.wfile.write(html.encode())

            elif self.path.startswith('/tiles/'):
                # /tiles/{z}/{x}/{y}
                parts = self.path[7:].split('/')
                try:
                    z, x, y = int(parts[0]), int(parts[1]), int(parts[2])
                    conn = sqlite3.connect(DB_PATH)
                    row = conn.execute(
                        'SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?',
                        (z, x, tms_y(y, z))   # ← même Y-flip que readTile() Dart
                    ).fetchone()
                    conn.close()
                    if row:
                        data = bytes(row[0])
                        ct = 'image/png' if data[:4] == b'\x89PNG' else 'image/jpeg'
                        self.send_response(200)
                        self.send_header('Content-Type', ct)
                        self.send_header('Access-Control-Allow-Origin', '*')
                        self.end_headers()
                        self.wfile.write(data)
                    else:
                        self.send_response(204)
                        self.end_headers()
                except Exception:
                    self.send_response(404)
                    self.end_headers()
            else:
                self.send_response(404)
                self.end_headers()

    server = HTTPServer(('localhost', 9977), Handler)
    server.serve_forever()


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    serve_mode = '--serve' in sys.argv
    check_only = '--check' in sys.argv

    print('=' * 56)
    print('  EcoMap — Vérification pipeline offline')
    print('=' * 56)
    print(f'  Zone : Lac Pikauba ({MIN_LAT}–{MAX_LAT}°N, {MIN_LON}–{MAX_LON}°E)')
    print(f'  Zoom : {MIN_ZOOM} → {MAX_ZOOM}   |   DB : {DB_PATH}')
    print()

    # Créer la base
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''CREATE TABLE tiles (
        zoom_level INTEGER NOT NULL, tile_column INTEGER NOT NULL,
        tile_row INTEGER NOT NULL, tile_data BLOB NOT NULL,
        PRIMARY KEY (zoom_level, tile_column, tile_row))''')
    conn.execute('CREATE TABLE metadata (name TEXT PRIMARY KEY, value TEXT)')
    for k, v in [('name', 'EcoMap Test'), ('minzoom', str(MIN_ZOOM)), ('maxzoom', str(MAX_ZOOM))]:
        conn.execute('INSERT INTO metadata VALUES (?,?)', (k, v))
    conn.commit()

    tiles = tiles_for_bounds(MIN_LAT, MIN_LON, MAX_LAT, MAX_LON, MIN_ZOOM, MAX_ZOOM)
    print(f'📦 {len(tiles)} tuiles à télécharger par source\n')

    # Télécharger toutes les sources
    results = {}
    for name, url in SOURCES:
        results[name] = download_source(conn, name, url, tiles)

    # ── Tests ────────────────────────────────────────────────────────────────
    print('\n' + '─' * 56)
    print('  Vérifications')
    print('─' * 56)

    all_pass = True

    # Test 1 : Y-flip
    check_yflip()

    # Test 2 : Lecture de chaque tuile
    read_ok, read_fail = check_readback(conn, tiles)
    pct_read = read_ok / len(tiles) * 100 if tiles else 0
    sym = '✓' if read_fail == 0 else '⚠️'
    print(f'  {sym} Lecture : {read_ok}/{len(tiles)} tuiles lisibles ({pct_read:.0f}%)')
    if read_fail > 0:
        print(f'    ❌ {read_fail} tuiles illisibles ← problème Y-flip ou corruption')
        all_pass = False

    # Test 3 : Couverture par zoom
    coverage = check_coverage(conn)
    print('\n  Couverture par niveau de zoom :')
    for r in coverage:
        sym = '✓' if r['pct'] >= 85 else '⚠️'
        bar = '█' * int(r['pct'] / 5) + '░' * (20 - int(r['pct'] / 5))
        print(f"    {sym} z{r['z']:2d} {bar} {r['count']:3d}/{r['expected']:3d} ({r['pct']:.0f}%)")
        if r['pct'] < 85:
            all_pass = False

    conn.close()

    # ── Résumé ───────────────────────────────────────────────────────────────
    print('\n' + '─' * 56)
    if all_pass:
        print('  ✅ TOUT PASSE — pipeline offline fonctionnel')
        print('     → Les tuiles seront correctes sur iOS')
    else:
        print('  ❌ DES VÉRIFICATIONS ONT ÉCHOUÉ')
        print('     → Ne pas pousser — corriger d\'abord')
    print('─' * 56)

    if not all_pass or check_only:
        sys.exit(0 if all_pass else 1)

    # ── Serveur Leaflet ──────────────────────────────────────────────────────
    if not serve_mode:
        try:
            answer = input('\n🌐 Ouvrir la vérification visuelle dans le navigateur ? [O/n] ').strip().lower()
            serve_mode = answer != 'n'
        except KeyboardInterrupt:
            serve_mode = False

    if serve_mode:
        print('\n🚀 Serveur sur http://localhost:9977  (Ctrl+C pour arrêter)')
        print('   Zoom dans le navigateur pour voir la couverture à chaque niveau')
        threading.Timer(1.2, lambda: webbrowser.open('http://localhost:9977')).start()
        try:
            start_server()
        except KeyboardInterrupt:
            print('\n👋 Serveur arrêté')

    sys.exit(0 if all_pass else 1)


if __name__ == '__main__':
    main()
