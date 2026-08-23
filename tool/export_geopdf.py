#!/usr/bin/env python3
"""
EcoMap — Export PDF géoréférencé (OGC GeoPDF)
==============================================
Lit les bounds depuis un .mbtiles existant, re-télécharge chaque fournisseur
satellite séparément, puis génère un PDF géoréférencé par source.
Format OGC GeoPDF : coordonnées GPS embarquées dans le PDF.

Prérequis : pip3 install Pillow

Usage :
  python3 tool/export_geopdf.py <zone.mbtiles> [mapbox_token]
  python3 tool/export_geopdf.py /tmp/ecomap_verify/satellite.mbtiles

Sortie (~/Desktop/) :
  EcoMap_<zone>_esri.pdf
  EcoMap_<zone>_sentinel.pdf
  EcoMap_<zone>_mrnfqc.pdf
  EcoMap_<zone>_mapbox.pdf   (si token fourni)
  EcoMap_<zone>_topo.pdf
  EcoMap_<zone>_topo_eco.pdf

Limite : 10 km × 10 km par PDF. Si la zone est plus grande, zoom réduit.
"""

import json, math, os, ssl, sqlite3, sys, urllib.request, zlib
from io import BytesIO

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Pillow requis :  pip3 install Pillow")
    sys.exit(1)

# ── Config ────────────────────────────────────────────────────────────────────
OUTPUT_DIR = os.path.expanduser('~/Desktop')
MAX_KM     = 10.0          # limite géographique par PDF
MAX_PIXELS = 6144          # résolution max en px (côté le plus long)
EXPORT_ZOOM_MAX = 14       # zoom max pour l'export PDF (≤14 pour rester léger)

_SSL = ssl.create_default_context()
_SSL.check_hostname = False
_SSL.verify_mode = ssl.CERT_NONE

# ── Fournisseurs (mêmes URLs que territoire_download_page.dart) ───────────────
def build_sources(mapbox_token=''):
    sources = [
        ('esri',     'Satellite ESRI',      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'),
        ('sentinel', 'Satellite Sentinel',  'https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2023_3857/default/g/{z}/{y}/{x}.jpg'),
        ('mrnfqc',   'Satellite MRNF QC',   'https://servicesmatriciels.mern.gouv.qc.ca/erdas-iws/ogc/wmts/Imagerie_Continue?layer=Imagerie_GQ&style=default&tilematrixset=GoogleMapsCompatibleExt2:epsg:3857&Service=WMTS&Request=GetTile&Version=1.0.0&Format=image/jpeg&TileMatrix={z}&TileCol={x}&TileRow={y}'),
        ('topo',     'Topo (OpenTopoMap)',   'https://tile.opentopomap.org/{z}/{x}/{y}.png'),
    ]
    if mapbox_token:
        sources.insert(1, ('mapbox', 'Satellite Mapbox',
            f'https://api.mapbox.com/styles/v1/mapbox/satellite-v9/tiles/{{z}}/{{x}}/{{y}}?access_token={mapbox_token}'))
    return sources

# ── Maths tuiles (miroir MbtilesService.dart) ─────────────────────────────────
def tms_y(y, z):   return (1 << z) - 1 - y
def lon_x(lon, z): return int((lon + 180) / 360 * (1 << z))
def lat_y(lat, z):
    r = math.radians(lat)
    return int((1 - math.log(math.tan(r) + 1/math.cos(r)) / math.pi) / 2 * (1 << z))
def tile_lon(x, z):  return x / (1 << z) * 360 - 180
def tile_lat(y, z):
    n = math.pi - 2 * math.pi * y / (1 << z)
    return math.degrees(math.atan(math.sinh(n)))

def haversine_km(lat1, lon1, lat2, lon2):
    R = 6371.0
    dlat, dlon = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon/2)**2
    return R * 2 * math.asin(math.sqrt(a))

# ── Lecture bounds depuis .mbtiles existant ───────────────────────────────────
def read_bounds(db_path, zoom):
    conn = sqlite3.connect(db_path)
    row = conn.execute(
        "SELECT MIN(tile_column), MAX(tile_column), MIN(tile_row), MAX(tile_row) "
        "FROM tiles WHERE zoom_level=?", (zoom,)
    ).fetchone()
    conn.close()
    if not row or row[0] is None:
        return None
    x0, x1, tms0, tms1 = row
    y0 = tms_y(tms1, zoom)
    y1 = tms_y(tms0, zoom)
    return (x0, x1, y0, y1,
            tile_lat(y0, zoom), tile_lat(y1 + 1, zoom),
            tile_lon(x0, zoom), tile_lon(x1 + 1, zoom))

def best_zoom(db_path):
    conn = sqlite3.connect(db_path)
    row = conn.execute("SELECT value FROM metadata WHERE name='maxzoom'").fetchone()
    if not row:
        row = conn.execute("SELECT MAX(zoom_level) FROM tiles").fetchone()
    conn.close()
    return int(row[0]) if row and row[0] else 14

# ── Téléchargement d'une zone dans un dict mémoire ───────────────────────────
def fetch_tiles(url_tpl, x0, x1, y0, y1, zoom):
    """Retourne un dict {(x, y): bytes} pour les tuiles demandées."""
    tiles = {}
    total = (x1 - x0 + 1) * (y1 - y0 + 1)
    done = 0
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            url = (url_tpl
                   .replace('{z}', str(zoom))
                   .replace('{x}', str(x))
                   .replace('{y}', str(y)))
            try:
                req = urllib.request.Request(url, headers={'User-Agent': 'EcoMap/export'})
                with urllib.request.urlopen(req, timeout=12, context=_SSL) as r:
                    data = r.read()
                if len(data) > 200:
                    tiles[(x, y)] = data
            except Exception:
                pass
            done += 1
            print(f'     {done}/{total}', end='\r')
    print()
    return tiles

# ── Assemblage image ──────────────────────────────────────────────────────────
def stitch(tiles_dict, x0, x1, y0, y1):
    TILE = 256
    nx, ny = x1 - x0 + 1, y1 - y0 + 1
    img_w, img_h = nx * TILE, ny * TILE

    scale = 1.0
    if max(img_w, img_h) > MAX_PIXELS:
        scale = max(img_w, img_h) / MAX_PIXELS

    canvas = Image.new('RGB', (img_w, img_h), (40, 40, 40))
    ok = 0
    for xi, x in enumerate(range(x0, x1 + 1)):
        for yi, y in enumerate(range(y0, y1 + 1)):
            data = tiles_dict.get((x, y))
            if data:
                try:
                    tile_img = Image.open(BytesIO(data)).convert('RGB')
                    canvas.paste(tile_img, (xi * TILE, yi * TILE))
                    ok += 1
                except Exception:
                    pass

    if scale > 1.0:
        canvas = canvas.resize((int(img_w / scale), int(img_h / scale)), Image.LANCZOS)

    print(f'     {ok}/{nx*ny} tuiles  →  {canvas.size[0]}×{canvas.size[1]}px')
    return canvas

# ── Overlay éco ───────────────────────────────────────────────────────────────
def draw_eco(canvas, north, south, west, east, eco_path):
    if not eco_path or not os.path.exists(eco_path):
        return
    try:
        with open(eco_path, 'r', encoding='utf-8') as f:
            gj = json.load(f)
    except Exception:
        return

    img_w, img_h = canvas.size
    def to_px(lon, lat):
        return ((lon - west) / (east - west) * img_w,
                (north - lat) / (north - south) * img_h)

    draw = ImageDraw.Draw(canvas, 'RGBA')
    features = gj.get('features', []) if gj.get('type') == 'FeatureCollection' else [gj]
    count = 0
    for feat in features:
        geom = feat.get('geometry', {}) if isinstance(feat, dict) else {}
        rings = []
        if geom.get('type') == 'Polygon':
            rings = geom.get('coordinates', [])
        elif geom.get('type') == 'MultiPolygon':
            for poly in geom.get('coordinates', []):
                rings.extend(poly)
        for ring in rings:
            pts = [to_px(c[0], c[1]) for c in ring
                   if west <= c[0] <= east and south <= c[1] <= north]
            if len(pts) >= 3:
                draw.polygon(pts, fill=(255, 107, 53, 55), outline=(255, 107, 53, 210))
                count += 1
    if count:
        print(f'     {count} polygones éco')

# ── Génération OGC GeoPDF ─────────────────────────────────────────────────────
WGS84_WKT = (
    'GEOGCS["WGS 84",DATUM["WGS_1984",'
    'SPHEROID["WGS 84",6378137,298.257223563]],'
    'PRIMEM["Greenwich",0],'
    'UNIT["degree",0.0174532925199433]]'
)

def _pdf_str(s):
    return s.replace('\\', '\\\\').replace('(', '\\(').replace(')', '\\)')

def make_geopdf(image, north, south, west, east, out_path):
    img_w, img_h = image.size
    target_pt = 700
    if img_w >= img_h:
        pw, ph = target_pt, int(target_pt * img_h / img_w)
    else:
        pw, ph = int(target_pt * img_w / img_h), target_pt

    jpeg_buf = BytesIO()
    image.save(jpeg_buf, format='JPEG', quality=85, optimize=True)
    jpeg_data = jpeg_buf.getvalue()

    objects, offsets = {}, {}

    objects[1] = b'<< /Type /Catalog /Pages 2 0 R >>'
    objects[2] = b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>'

    gpts  = f'{south} {west}  {north} {west}  {north} {east}  {south} {east}'
    lpts  = '0 0  0 1  1 1  1 0'
    wkt   = _pdf_str(WGS84_WKT)
    vp = (f'<< /Type /Viewport /BBox [0 0 1 1] /Measure <<'
          f' /Type /Measure /Subtype /GEO'
          f' /GCS << /Type /GEOCS /WKT ({wkt}) >>'
          f' /GPTS [{gpts}] /LPTS [{lpts}]'
          f' >> >>')
    objects[3] = (
        f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {pw} {ph}]'
        f' /VP [{vp}]'
        f' /Resources << /XObject << /Im1 4 0 R >> >>'
        f' /Contents 5 0 R >>'
    ).encode()

    img_hdr = (f'<< /Type /XObject /Subtype /Image'
               f' /Width {img_w} /Height {img_h}'
               f' /ColorSpace /DeviceRGB /BitsPerComponent 8'
               f' /Filter /DCTDecode /Length {len(jpeg_data)} >>\nstream\n').encode()
    objects[4] = (img_hdr, jpeg_data, b'\nendstream')

    cs = f'q\n{pw} 0 0 {ph} 0 0 cm\n/Im1 Do\nQ\n'.encode()
    cz = zlib.compress(cs)
    objects[5] = (f'<< /Filter /FlateDecode /Length {len(cz)} >>\nstream\n'.encode(),
                  cz, b'\nendstream')

    out = BytesIO()
    def w(b):
        if isinstance(b, str): b = b.encode()
        out.write(b)

    w(b'%PDF-1.7\n%\xe2\xe3\xcf\xd3\n')
    for oid in range(1, 6):
        offsets[oid] = out.tell()
        w(f'{oid} 0 obj\n')
        parts = objects[oid]
        if isinstance(parts, tuple):
            for p in parts:
                out.write(p if isinstance(p, bytes) else p.encode())
        else:
            out.write(parts if isinstance(parts, bytes) else parts.encode())
        w(b'\nendobj\n')

    xref_off = out.tell()
    w(f'xref\n0 6\n0000000000 65535 f \n')
    for oid in range(1, 6):
        w(f'{offsets[oid]:010d} 00000 n \n')
    w(f'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{xref_off}\n%%EOF\n')

    with open(out_path, 'wb') as f:
        f.write(out.getvalue())

# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)

    ref_db = sys.argv[1]
    mapbox_token = sys.argv[2] if len(sys.argv) > 2 else ''

    if not os.path.exists(ref_db):
        print(f'❌ Fichier .mbtiles introuvable : {ref_db}')
        sys.exit(1)

    zone_name = os.path.basename(ref_db).replace('.mbtiles', '').replace('_topo', '').replace('_base', '')

    print('=' * 60)
    print('  EcoMap — Export GeoPDF multi-sources (Avenza Maps)')
    print('=' * 60)
    print(f'  Zone : {zone_name}')
    print()

    # ── Lire bounds + choisir zoom export ────────────────────────────────────
    zoom = min(best_zoom(ref_db), EXPORT_ZOOM_MAX)
    bounds = read_bounds(ref_db, zoom)
    if not bounds:
        # Chercher un zoom disponible
        for z in range(EXPORT_ZOOM_MAX, 8, -1):
            bounds = read_bounds(ref_db, z)
            if bounds:
                zoom = z
                break
    if not bounds:
        print('❌ Aucune tuile trouvée dans ce fichier.')
        sys.exit(1)

    x0, x1, y0, y1, north, south, west, east = bounds
    h_km = haversine_km(south, west, north, west)
    w_km = haversine_km(south, west, south, east)
    print(f'  Bounds : {south:.4f}–{north:.4f}°N, {west:.4f}–{east:.4f}°E')
    print(f'  Zone   : {h_km:.1f} km × {w_km:.1f} km  |  zoom export : {zoom}')

    if h_km > MAX_KM or w_km > MAX_KM:
        print(f'  ⚠️  Zone > {MAX_KM:.0f}km×{MAX_KM:.0f}km')
        print('     → Réduis la zone dans l\'app (carré orange plus petit) pour un meilleur PDF.')
        ans = input('  Continuer quand même ? [o/N] ').strip().lower()
        if ans != 'o':
            sys.exit(0)

    tuiles_total = (x1 - x0 + 1) * (y1 - y0 + 1)
    print(f'  Tuiles : {x1-x0+1}×{y1-y0+1} = {tuiles_total} par source')
    print()

    # ── Éco GeoJSON ──────────────────────────────────────────────────────────
    ref_dir = os.path.dirname(ref_db)
    eco_candidates = [
        os.path.join(ref_dir, zone_name + '.geojson'),
        os.path.join(os.path.dirname(__file__), '..', 'assets', 'eco_zone.geojson'),
    ]
    eco_path = next((p for p in eco_candidates if os.path.exists(p)), None)

    # ── Génération par source ─────────────────────────────────────────────────
    sources = build_sources(mapbox_token)
    generated = []

    for src_id, src_label, url_tpl in sources:
        is_topo = src_id == 'topo'
        print(f'━━ {src_label} ─────────────────────────────────────')

        print('   Téléchargement...')
        tiles = fetch_tiles(url_tpl, x0, x1, y0, y1, zoom)
        if not tiles:
            print('   ⚠️  Aucune tuile reçue — fournisseur ignoré')
            continue

        print('   Assemblage...')
        img = stitch(tiles, x0, x1, y0, y1)

        # PDF satellite ou topo seul
        suffix = src_id
        out_path = os.path.join(OUTPUT_DIR, f'EcoMap_{zone_name}_{suffix}.pdf')
        make_geopdf(img, north, south, west, east, out_path)
        size = os.path.getsize(out_path) / 1024 / 1024
        print(f'   ✅ {os.path.basename(out_path)}  ({size:.1f} MB)')
        generated.append(out_path)

        # Pour topo : générer aussi la version avec éco par-dessus
        if is_topo and eco_path:
            print('   + Overlay éco...')
            img_eco = img.copy()
            draw_eco(img_eco, north, south, west, east, eco_path)
            out_eco = os.path.join(OUTPUT_DIR, f'EcoMap_{zone_name}_topo_eco.pdf')
            make_geopdf(img_eco, north, south, west, east, out_eco)
            size_eco = os.path.getsize(out_eco) / 1024 / 1024
            print(f'   ✅ {os.path.basename(out_eco)}  ({size_eco:.1f} MB)')
            generated.append(out_eco)

        print()

    # ── Résumé ────────────────────────────────────────────────────────────────
    print('=' * 60)
    print(f'  {len(generated)} PDFs générés sur le Bureau :')
    for p in generated:
        print(f'    • {os.path.basename(p)}')
    print()
    print('📲 Les PDFs sont géoréférencés (OGC GeoPDF) :')
    print('   Coordonnées GPS intégrées → ouvrable dans tout viewer PDF géo.')
    print('   Prochaine étape : intégration viewer in-app EcoMap.')

if __name__ == '__main__':
    main()
