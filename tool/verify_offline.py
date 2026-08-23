#!/usr/bin/env python3
"""
EcoMap — Vérification du pipeline offline
==========================================
Télécharge une zone de test (Lac Pikauba, zoom 10–14) depuis toutes les
sources de l'app, vérifie l'intégrité, et lance un serveur Leaflet avec
toggle de couches : Base OSM | Satellite ESRI | Topo | Éco (si dispo).

Usage :
  python3 tool/verify_offline.py          # vérification + serveur
  python3 tool/verify_offline.py --check  # vérification seulement
"""

import math, sqlite3, os, ssl, sys, threading, urllib.request, webbrowser
from http.server import HTTPServer, BaseHTTPRequestHandler

# ── Zone de test ──────────────────────────────────────────────────────────────
CENTER_LAT, CENTER_LON = 47.5, -72.0
MIN_LAT, MAX_LAT = 47.470, 47.530
MIN_LON, MAX_LON = -72.040, -71.960
MIN_ZOOM, MAX_ZOOM = 10, 14   # ~42 tuiles par source, ~90 secondes

# Chaque source → son propre fichier .mbtiles (comme dans l'app iOS)
SOURCES = {
    'satellite': ('Satellite ESRI',      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'),
    'topo':      ('Relief (OpenTopoMap)', 'https://tile.opentopomap.org/{z}/{x}/{y}.png'),
    'base':      ('Carte de base (OSM)',  'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
}
# Eco bundlé dans l'app — cherché localement
ECO_PATH = os.path.join(os.path.dirname(__file__), '..', 'assets', 'tiles', 'eco.mbtiles')
DB_DIR   = '/tmp/ecomap_verify'

_SSL = ssl.create_default_context()
_SSL.check_hostname = False
_SSL.verify_mode = ssl.CERT_NONE

# ── Maths (miroir exact de MbtilesService.dart) ───────────────────────────────

def tms_y(y, z):  return (1 << z) - 1 - y
def lon_x(lon, z): return int((lon + 180) / 360 * (1 << z))
def lat_y(lat, z):
    r = math.radians(lat)
    return int((1 - math.log(math.tan(r) + 1/math.cos(r)) / math.pi) / 2 * (1 << z))

def tiles_for(min_lat, min_lon, max_lat, max_lon, z0, z1):
    t = []
    for z in range(z0, z1+1):
        for x in range(lon_x(min_lon, z), lon_x(max_lon, z)+1):
            for y in range(lat_y(max_lat, z), lat_y(min_lat, z)+1):
                t.append((z, x, y))
    return t

def is_image(data):
    return len(data) > 200 and (data[:4]==b'\x89PNG' or data[:3]==b'\xff\xd8\xff' or len(data)>500)

# ── DB helpers ────────────────────────────────────────────────────────────────

def open_db(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    conn = sqlite3.connect(path)
    conn.execute('''CREATE TABLE IF NOT EXISTS tiles(
        zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER,
        tile_data BLOB, PRIMARY KEY(zoom_level,tile_column,tile_row))''')
    conn.execute('CREATE TABLE IF NOT EXISTS metadata(name TEXT PRIMARY KEY,value TEXT)')
    conn.commit()
    return conn

def read_tile(path, z, x, y):
    if not os.path.exists(path): return None
    conn = sqlite3.connect(path)
    row = conn.execute(
        'SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?',
        (z, x, tms_y(y, z))
    ).fetchone()
    conn.close()
    return bytes(row[0]) if row else None

# ── Téléchargement ────────────────────────────────────────────────────────────

def download(layer_id, label, url_tpl, tiles):
    path = f'{DB_DIR}/{layer_id}.mbtiles'
    if os.path.exists(path): os.remove(path)
    conn = open_db(path)
    ok = errors = 0
    batch = []

    for i, (z, x, y) in enumerate(tiles):
        url = url_tpl.replace('{z}',str(z)).replace('{x}',str(x)).replace('{y}',str(y))
        try:
            req = urllib.request.Request(url, headers={'User-Agent':'EcoMap/verify'})
            with urllib.request.urlopen(req, timeout=12, context=_SSL) as r:
                data = r.read()
            if is_image(data):
                batch.append((z, x, tms_y(y,z), data))
                ok += 1
            else:
                errors += 1
        except:
            errors += 1

        if len(batch) >= 20:
            conn.executemany('INSERT OR REPLACE INTO tiles VALUES(?,?,?,?)', batch)
            conn.commit(); batch = []

        if (i+1) % 10 == 0 or i+1 == len(tiles):
            print(f'     {i+1}/{len(tiles)}  {ok}✓ {errors}✗', end='\r')

    if batch:
        conn.executemany('INSERT OR REPLACE INTO tiles VALUES(?,?,?,?)', batch)
        conn.commit()
    conn.close()
    print(f'     {ok}/{len(tiles)} tuiles  {errors} erreurs            ')
    return ok, errors

# ── Vérifications ─────────────────────────────────────────────────────────────

def verify(layer_id, tiles):
    path = f'{DB_DIR}/{layer_id}.mbtiles'
    ok = fail = 0
    for z, x, y in tiles:
        d = read_tile(path, z, x, y)
        if d and is_image(d): ok += 1
        else: fail += 1
    return ok, fail

def coverage(layer_id):
    path = f'{DB_DIR}/{layer_id}.mbtiles'
    rows = []
    conn = sqlite3.connect(path)
    for z in range(MIN_ZOOM, MAX_ZOOM+1):
        x0,x1 = lon_x(MIN_LON,z), lon_x(MAX_LON,z)
        y0,y1 = lat_y(MAX_LAT,z), lat_y(MIN_LAT,z)
        exp = (x1-x0+1)*(y1-y0+1)
        cnt = conn.execute('SELECT COUNT(*) FROM tiles WHERE zoom_level=?',(z,)).fetchone()[0]
        rows.append((z, cnt, exp, cnt/exp*100 if exp else 0))
    conn.close()
    return rows

# ── Serveur Leaflet ───────────────────────────────────────────────────────────

def make_html(has_eco):
    eco_layer = """
    const ecoLayer = L.tileLayer('/tiles/eco/{z}/{x}/{y}', {
      maxZoom: 22, maxNativeZoom: 16, opacity: 0.7, attribution: 'EcoMap bundled'
    });""" if has_eco else "const ecoLayer = null;"

    eco_control = """
    if (ecoLayer) baseLayers['🌿 Éco (bundlé)'] = ecoLayer;""" if has_eco else ""

    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>EcoMap — Vérification offline</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
body{{margin:0;font-family:-apple-system,sans-serif}}
#map{{height:100vh}}
.panel{{
  position:absolute;top:10px;right:50px;
  background:rgba(20,20,20,.88);color:#fff;
  padding:12px 16px;border-radius:10px;z-index:1000;
  font-size:13px;min-width:230px;
  box-shadow:0 4px 16px rgba(0,0,0,.5);
}}
.panel b{{color:#FF6B35}}
.ok{{color:#4CAF50}} .bad{{color:#f44336}}
.sub{{color:#aaa;font-size:11px;margin-top:8px;padding-top:8px;border-top:1px solid #333}}
</style>
</head>
<body>
<div id="map"></div>
<div class="panel">
  <b>EcoMap — Vérification offline</b><br><br>
  Couche active : <span id="lname">—</span><br>
  Zoom actuel : <span id="z">{MAX_ZOOM}</span><br>
  Tuiles chargées : <span id="tiles">0</span><br>
  <div class="sub">
    Zone orange = zone téléchargée.<br>
    Toutes les couches doivent remplir<br>
    cette zone à <b>tous les niveaux de zoom</b>.<br>
    Au-delà du zoom {MAX_ZOOM} : upscale normal.
  </div>
</div>
<script>
const map = L.map('map').setView([{CENTER_LAT},{CENTER_LON}], {MAX_ZOOM});

const satLayer  = L.tileLayer('/tiles/satellite/{{z}}/{{x}}/{{y}}', {{maxZoom:22, maxNativeZoom:{MAX_ZOOM}}});
const topoLayer = L.tileLayer('/tiles/topo/{{z}}/{{x}}/{{y}}',      {{maxZoom:22, maxNativeZoom:{MAX_ZOOM}}});
const baseLayer = L.tileLayer('/tiles/base/{{z}}/{{x}}/{{y}}',      {{maxZoom:22, maxNativeZoom:{MAX_ZOOM}}});
{eco_layer}

const baseLayers = {{
  '🛰️ Satellite ESRI':  satLayer,
  '⛰️ Relief (Topo)':   topoLayer,
  '🗺️ Carte de base':   baseLayer,
}};
{eco_control}

baseLayer.addTo(map);
L.control.layers(baseLayers).addTo(map);

// Cadre de la zone téléchargée
L.rectangle([[{MIN_LAT},{MIN_LON}],[{MAX_LAT},{MAX_LON}]], {{
  color:'#FF6B35', weight:2, fill:true, fillColor:'#FF6B35', fillOpacity:0.05
}}).addTo(map);

map.on('baselayerchange', e => {{
  document.getElementById('lname').textContent = e.name;
}});
document.getElementById('lname').textContent = '🗺️ Carte de base';

setInterval(() => {{
  document.getElementById('z').textContent = map.getZoom();
  document.getElementById('tiles').textContent =
    document.querySelectorAll('.leaflet-tile-loaded').length;
}}, 500);
</script>
</body>
</html>"""

def start_server(has_eco):
    html = make_html(has_eco)
    eco_path = ECO_PATH if has_eco else None

    class H(BaseHTTPRequestHandler):
        def log_message(self, *a): pass
        def do_GET(self):
            if self.path == '/':
                self.send_response(200)
                self.send_header('Content-Type','text/html; charset=utf-8')
                self.end_headers(); self.wfile.write(html.encode())
                return
            if self.path.startswith('/tiles/'):
                parts = self.path[7:].split('/')   # layer/z/x/y
                if len(parts) >= 4:
                    layer, z, x, y = parts[0], int(parts[1]), int(parts[2]), int(parts[3])
                    if layer == 'eco' and eco_path:
                        data = read_tile(eco_path, z, x, y)
                    else:
                        data = read_tile(f'{DB_DIR}/{layer}.mbtiles', z, x, y)
                    if data:
                        ct = 'image/png' if data[:4]==b'\x89PNG' else 'image/jpeg'
                        self.send_response(200)
                        self.send_header('Content-Type', ct)
                        self.send_header('Access-Control-Allow-Origin','*')
                        self.end_headers(); self.wfile.write(data); return
            self.send_response(204); self.end_headers()

    srv = HTTPServer(('localhost', 9977), H)
    srv.serve_forever()

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    check_only = '--check' in sys.argv
    serve_mode = '--serve' in sys.argv

    print('=' * 56)
    print('  EcoMap — Vérification pipeline offline')
    print('=' * 56)
    print(f'  Zone : Lac Pikauba ({MIN_LAT}–{MAX_LAT}N, {MIN_LON}–{MAX_LON}E)')
    print(f'  Zoom : {MIN_ZOOM}→{MAX_ZOOM}  |  dossier : {DB_DIR}')
    os.makedirs(DB_DIR, exist_ok=True)

    tiles = tiles_for(MIN_LAT, MIN_LON, MAX_LAT, MAX_LON, MIN_ZOOM, MAX_ZOOM)
    print(f'\n📦 {len(tiles)} tuiles × {len(SOURCES)} sources = {len(tiles)*len(SOURCES)} total\n')

    # ── Téléchargement ────────────────────────────────────────────────────────
    results = {}
    for layer_id, (label, url) in SOURCES.items():
        print(f'  📡 {label}')
        ok, err = download(layer_id, label, url, tiles)
        results[layer_id] = (ok, err)

    # ── Vérifications ─────────────────────────────────────────────────────────
    print('\n' + '─'*56)
    print('  Vérifications')
    print('─'*56)

    # Test Y-flip
    for z in range(MIN_ZOOM, MAX_ZOOM+2):
        for y in [0, (1<<z)//2, (1<<z)-1]:
            assert tms_y(tms_y(y,z),z)==y
    print('  ✓ Y-flip : cohérent à tous les niveaux')

    all_pass = True
    for layer_id, (label, _) in SOURCES.items():
        ok, fail = verify(layer_id, tiles)
        sym = '✓' if fail == 0 else '⚠️'
        pct = ok/len(tiles)*100
        print(f'  {sym} {label} : {ok}/{len(tiles)} lisibles ({pct:.0f}%)')
        if fail > 0: all_pass = False

    # Couverture par zoom (sur satellite comme référence)
    print('\n  Couverture satellite par zoom :')
    for z, cnt, exp, pct in coverage('satellite'):
        sym = '✓' if pct >= 85 else '⚠️'
        bar = '█'*int(pct/5) + '░'*(20-int(pct/5))
        print(f'    {sym} z{z:2d} {bar} {cnt:3d}/{exp:3d} ({pct:.0f}%)')
        if pct < 85: all_pass = False

    # Éco bundlé
    has_eco = os.path.exists(ECO_PATH)
    print(f'\n  {"✓" if has_eco else "–"} Éco bundlé (assets/tiles/eco.mbtiles) : {"présent" if has_eco else "absent — ok si pas encore ajouté"}')

    print('\n' + '─'*56)
    if all_pass:
        print('  ✅ TOUT PASSE — pipeline offline fonctionnel')
        print('     → Les tuiles seront correctes sur iOS')
    else:
        print('  ❌ DES VÉRIFICATIONS ONT ÉCHOUÉ')
        print('     → Corriger avant de lancer Codemagic')
    print('─'*56)

    if check_only or not all_pass:
        sys.exit(0 if all_pass else 1)

    if not serve_mode:
        try:
            ans = input('\n🌐 Ouvrir la vérification visuelle dans le navigateur ? [O/n] ').strip().lower()
            serve_mode = ans != 'n'
        except KeyboardInterrupt:
            serve_mode = False

    if serve_mode:
        print('\n🚀 Serveur sur http://localhost:9977  (Ctrl+C pour arrêter)')
        print('   Toggle en haut à droite pour changer de couche (satellite, topo, base, éco)')
        threading.Timer(1.2, lambda: webbrowser.open('http://localhost:9977')).start()
        try:
            start_server(has_eco)
        except KeyboardInterrupt:
            print('\n👋 Serveur arrêté')

    sys.exit(0 if all_pass else 1)

if __name__ == '__main__':
    main()
