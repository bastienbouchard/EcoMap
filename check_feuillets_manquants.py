"""
Trouve les feuillets MFFP manquants pour couvrir les tuiles sparse/vides.
"""
import requests, json, urllib3
urllib3.disable_warnings()

TILES = [{"lat": 46.0, "lon": -75.0, "n": 194}, {"lat": 49.0, "lon": -70.5, "n": 313}, {"lat": 48.5, "lon": -78.5, "n": 2}, {"lat": 46.0, "lon": -72.0, "n": 23850}, {"lat": 49.0, "lon": -77.5, "n": 28555}, {"lat": 48.0, "lon": -67.5, "n": 200}, {"lat": 50.0, "lon": -80.0, "n": 4}, {"lat": 49.5, "lon": -68.5, "n": 316}, {"lat": 50.0, "lon": -78.0, "n": 66}, {"lat": 50.5, "lon": -72.0, "n": 18847}, {"lat": 49.0, "lon": -65.5, "n": 14876}, {"lat": 50.5, "lon": -75.0, "n": 19593}, {"lat": 47.5, "lon": -68.0, "n": 1007}, {"lat": 46.5, "lon": -78.0, "n": 27651}, {"lat": 47.0, "lon": -70.0, "n": 1}, {"lat": 45.0, "lon": -72.5, "n": 151}, {"lat": 48.0, "lon": -75.5, "n": 167}, {"lat": 47.0, "lon": -77.0, "n": 172}, {"lat": 48.0, "lon": -72.5, "n": 1}, {"lat": 47.0, "lon": -76.5, "n": 207}, {"lat": 48.0, "lon": -73.0, "n": 230}, {"lat": 45.0, "lon": -74.0, "n": 9239}, {"lat": 47.0, "lon": -71.5, "n": 203}, {"lat": 48.0, "lon": -74.0, "n": 1}, {"lat": 45.0, "lon": -73.0, "n": 18677}, {"lat": 47.5, "lon": -69.5, "n": 31099}, {"lat": 50.5, "lon": -74.5, "n": 109}, {"lat": 50.5, "lon": -73.5, "n": 19020}, {"lat": 49.5, "lon": -69.0, "n": 38048}, {"lat": 50.0, "lon": -79.5, "n": 119}, {"lat": 48.0, "lon": -66.0, "n": 21535}, {"lat": 50.5, "lon": -66.5, "n": 193}, {"lat": 46.0, "lon": -73.5, "n": 90}, {"lat": 49.0, "lon": -76.0, "n": 298}, {"lat": 46.0, "lon": -74.5, "n": 1}, {"lat": 48.5, "lon": -79.0, "n": 200}, {"lat": 49.0, "lon": -71.0, "n": 219}, {"lat": 47.5, "lon": -69.0, "n": 31486}, {"lat": 50.5, "lon": -74.0, "n": 10514}, {"lat": 49.0, "lon": -64.5, "n": 541}, {"lat": 50.5, "lon": -73.0, "n": 20537}, {"lat": 45.0, "lon": -74.5, "n": 95}, {"lat": 48.0, "lon": -73.5, "n": 213}, {"lat": 47.0, "lon": -76.0, "n": 1}, {"lat": 45.0, "lon": -73.5, "n": 5819}, {"lat": 48.0, "lon": -74.5, "n": 236}, {"lat": 47.0, "lon": -71.0, "n": 40}, {"lat": 49.0, "lon": -76.5, "n": 20250}, {"lat": 46.0, "lon": -73.0, "n": 75}, {"lat": 50.5, "lon": -66.0, "n": 12807}, {"lat": 49.0, "lon": -71.5, "n": 215}, {"lat": 48.5, "lon": -79.5, "n": 164}, {"lat": 46.0, "lon": -74.0, "n": 151}, {"lat": 50.0, "lon": -79.0, "n": 151}, {"lat": 49.5, "lon": -69.5, "n": 34913}, {"lat": 48.0, "lon": -66.5, "n": 195}, {"lat": 48.0, "lon": -67.0, "n": 68}, {"lat": 50.0, "lon": -78.5, "n": 54}, {"lat": 49.5, "lon": -68.0, "n": 36149}, {"lat": 48.5, "lon": -78.0, "n": 202}, {"lat": 49.0, "lon": -70.0, "n": 34680}, {"lat": 46.0, "lon": -75.5, "n": 214}, {"lat": 48.5, "lon": -80.0, "n": 6}, {"lat": 49.0, "lon": -77.0, "n": 25396}, {"lat": 46.0, "lon": -72.5, "n": 186}, {"lat": 48.0, "lon": -75.0, "n": 210}, {"lat": 45.0, "lon": -72.0, "n": 23473}, {"lat": 47.0, "lon": -70.5, "n": 215}, {"lat": 46.5, "lon": -78.5, "n": 249}, {"lat": 48.0, "lon": -72.0, "n": 261}, {"lat": 45.0, "lon": -75.0, "n": 195}, {"lat": 47.0, "lon": -77.5, "n": 194}, {"lat": 50.5, "lon": -72.5, "n": 216}, {"lat": 50.5, "lon": -75.5, "n": 19583}, {"lat": 47.5, "lon": -68.5, "n": 11559}, {"lat": 49.0, "lon": -65.0, "n": 11284}, {"lat": 46.5, "lon": -75.5, "n": 28554}, {"lat": 49.5, "lon": -70.0, "n": 34840}, {"lat": 48.0, "lon": -78.0, "n": 192}, {"lat": 46.5, "lon": -72.5, "n": 259}, {"lat": 50.0, "lon": -67.5, "n": 196}, {"lat": 49.5, "lon": -77.0, "n": 21080}, {"lat": 48.0, "lon": -80.0, "n": 1104}, {"lat": 48.5, "lon": -67.0, "n": 203}, {"lat": 49.0, "lon": -68.0, "n": 11757}, {"lat": 51.0, "lon": -70.5, "n": 200}, {"lat": 50.0, "lon": -72.5, "n": 1}, {"lat": 49.5, "lon": -65.0, "n": 75}, {"lat": 50.0, "lon": -75.5, "n": 145}, {"lat": 47.0, "lon": -68.5, "n": 67}, {"lat": 46.0, "lon": -78.5, "n": 141}, {"lat": 47.5, "lon": -70.5, "n": 153}, {"lat": 45.5, "lon": -72.0, "n": 162}, {"lat": 48.5, "lon": -75.0, "n": 23633}, {"lat": 47.5, "lon": -77.5, "n": 178}, {"lat": 45.5, "lon": -75.0, "n": 20984}, {"lat": 48.5, "lon": -72.0, "n": 18840}, {"lat": 47.5, "lon": -76.0, "n": 2}, {"lat": 48.5, "lon": -73.5, "n": 27634}, {"lat": 45.5, "lon": -74.5, "n": 129}, {"lat": 47.5, "lon": -71.0, "n": 31837}, {"lat": 51.0, "lon": -64.0, "n": 1}, {"lat": 48.5, "lon": -74.5, "n": 290}, {"lat": 45.5, "lon": -73.5, "n": 8750}, {"lat": 49.5, "lon": -64.5, "n": 7699}, {"lat": 47.0, "lon": -69.0, "n": 8714}, {"lat": 50.0, "lon": -74.0, "n": 163}, {"lat": 50.0, "lon": -73.0, "n": 230}, {"lat": 49.0, "lon": -69.5, "n": 26122}, {"lat": 51.0, "lon": -71.0, "n": 137}, {"lat": 48.5, "lon": -66.5, "n": 1}, {"lat": 51.0, "lon": -76.0, "n": 35}, {"lat": 50.0, "lon": -66.0, "n": 11364}, {"lat": 46.5, "lon": -73.0, "n": 27635}, {"lat": 49.5, "lon": -76.5, "n": 28952}, {"lat": 46.5, "lon": -74.0, "n": 33237}, {"lat": 48.0, "lon": -79.5, "n": 25754}, {"lat": 49.5, "lon": -71.5, "n": 24661}, {"lat": 47.0, "lon": -69.5, "n": 9569}, {"lat": 50.0, "lon": -74.5, "n": 1}, {"lat": 49.5, "lon": -64.0, "n": 105}, {"lat": 50.0, "lon": -73.5, "n": 188}, {"lat": 45.5, "lon": -74.0, "n": 11295}, {"lat": 48.5, "lon": -73.0, "n": 27475}, {"lat": 47.5, "lon": -76.5, "n": 200}, {"lat": 45.5, "lon": -73.0, "n": 9377}, {"lat": 48.5, "lon": -74.0, "n": 29947}, {"lat": 51.0, "lon": -64.5, "n": 113}, {"lat": 47.5, "lon": -71.5, "n": 35028}, {"lat": 49.5, "lon": -76.0, "n": 360}, {"lat": 46.5, "lon": -73.5, "n": 33077}, {"lat": 50.0, "lon": -66.5, "n": 95}, {"lat": 49.5, "lon": -71.0, "n": 22256}, {"lat": 48.0, "lon": -79.0, "n": 27719}, {"lat": 46.5, "lon": -74.5, "n": 300}, {"lat": 51.0, "lon": -71.5, "n": 173}, {"lat": 49.0, "lon": -69.0, "n": 29178}, {"lat": 48.5, "lon": -66.0, "n": 176}, {"lat": 48.5, "lon": -67.5, "n": 28078}, {"lat": 51.0, "lon": -70.0, "n": 3}, {"lat": 49.0, "lon": -68.5, "n": 143}, {"lat": 48.0, "lon": -78.5, "n": 25174}, {"lat": 49.5, "lon": -70.5, "n": 227}, {"lat": 46.5, "lon": -75.0, "n": 29895}, {"lat": 49.5, "lon": -77.5, "n": 24175}, {"lat": 50.0, "lon": -67.0, "n": 24}, {"lat": 46.5, "lon": -72.0, "n": 25228}, {"lat": 48.5, "lon": -75.5, "n": 26677}, {"lat": 45.5, "lon": -72.5, "n": 152}, {"lat": 47.5, "lon": -70.0, "n": 12315}, {"lat": 46.0, "lon": -78.0, "n": 18999}, {"lat": 48.5, "lon": -72.5, "n": 78}, {"lat": 45.5, "lon": -75.5, "n": 22520}, {"lat": 47.5, "lon": -77.0, "n": 185}, {"lat": 50.0, "lon": -72.0, "n": 218}, {"lat": 50.0, "lon": -75.0, "n": 126}, {"lat": 47.5, "lon": -73.5, "n": 33979}, {"lat": 45.5, "lon": -71.0, "n": 139}, {"lat": 48.5, "lon": -76.0, "n": 1}, {"lat": 47.5, "lon": -74.5, "n": 27554}, {"lat": 45.5, "lon": -76.0, "n": 237}, {"lat": 49.0, "lon": -79.0, "n": 29929}, {"lat": 48.5, "lon": -71.0, "n": 35641}, {"lat": 48.0, "lon": -69.0, "n": 204}, {"lat": 50.0, "lon": -71.5, "n": 223}, {"lat": 50.0, "lon": -76.5, "n": 173}, {"lat": 51.0, "lon": -74.5, "n": 36}, {"lat": 51.0, "lon": -73.5, "n": 77}, {"lat": 46.5, "lon": -76.5, "n": 31024}, {"lat": 49.5, "lon": -73.0, "n": 32446}, {"lat": 44.5, "lon": -74.0, "n": 40}, {"lat": 46.5, "lon": -71.5, "n": 18049}, {"lat": 50.0, "lon": -64.5, "n": 4481}, {"lat": 49.5, "lon": -74.0, "n": 25897}, {"lat": 47.0, "lon": -78.0, "n": 233}, {"lat": 50.0, "lon": -65.0, "n": 3516}, {"lat": 46.5, "lon": -70.0, "n": 200}, {"lat": 49.5, "lon": -75.5, "n": 23019}, {"lat": 46.5, "lon": -77.5, "n": 29082}, {"lat": 49.0, "lon": -78.0, "n": 29291}, {"lat": 45.5, "lon": -77.0, "n": 13974}, {"lat": 48.5, "lon": -70.0, "n": 178}, {"lat": 47.5, "lon": -75.5, "n": 29270}, {"lat": 49.0, "lon": -80.0, "n": 1038}, {"lat": 48.5, "lon": -77.0, "n": 76}, {"lat": 47.5, "lon": -72.5, "n": 300}, {"lat": 50.0, "lon": -77.5, "n": 146}, {"lat": 49.5, "lon": -67.0, "n": 374}, {"lat": 50.0, "lon": -70.5, "n": 3}, {"lat": 48.0, "lon": -68.0, "n": 63}, {"lat": 50.0, "lon": -71.0, "n": 211}, {"lat": 48.0, "lon": -69.5, "n": 134}, {"lat": 50.0, "lon": -76.0, "n": 4}, {"lat": 48.5, "lon": -76.5, "n": 56}, {"lat": 45.5, "lon": -71.5, "n": 241}, {"lat": 47.5, "lon": -73.0, "n": 37739}, {"lat": 48.5, "lon": -71.5, "n": 29137}, {"lat": 49.0, "lon": -79.5, "n": 25589}, {"lat": 45.5, "lon": -76.5, "n": 28301}, {"lat": 47.5, "lon": -74.0, "n": 267}, {"lat": 44.5, "lon": -74.5, "n": 1}, {"lat": 49.5, "lon": -73.5, "n": 27199}, {"lat": 46.5, "lon": -76.0, "n": 241}, {"lat": 49.5, "lon": -74.5, "n": 258}, {"lat": 50.0, "lon": -64.0, "n": 41}, {"lat": 46.5, "lon": -71.0, "n": 22843}, {"lat": 51.0, "lon": -74.0, "n": 12}, {"lat": 48.5, "lon": -64.5, "n": 41}, {"lat": 51.0, "lon": -73.0, "n": 208}, {"lat": 47.0, "lon": -73.0, "n": 265}, {"lat": 45.0, "lon": -71.5, "n": 17715}, {"lat": 48.0, "lon": -76.5, "n": 30421}, {"lat": 50.0, "lon": -69.0, "n": 240}, {"lat": 47.0, "lon": -74.0, "n": 218}, {"lat": 45.0, "lon": -76.5, "n": 465}, {"lat": 49.5, "lon": -79.5, "n": 19147}, {"lat": 48.0, "lon": -71.5, "n": 218}, {"lat": 48.5, "lon": -69.5, "n": 173}, {"lat": 50.5, "lon": -71.0, "n": 16839}, {"lat": 49.0, "lon": -66.5, "n": 149}, {"lat": 50.5, "lon": -76.0, "n": 16577}, {"lat": 48.0, "lon": -64.5, "n": 2153}, {"lat": 46.0, "lon": -76.0, "n": 2}, {"lat": 49.0, "lon": -73.5, "n": 189}, {"lat": 46.0, "lon": -71.0, "n": 27759}, {"lat": 50.5, "lon": -64.0, "n": 145}, {"lat": 47.5, "lon": -79.0, "n": 185}, {"lat": 49.0, "lon": -74.5, "n": 1}, {"lat": 47.5, "lon": -78.5, "n": 170}, {"lat": 50.5, "lon": -65.5, "n": 5638}, {"lat": 46.0, "lon": -70.5, "n": 21453}, {"lat": 49.0, "lon": -75.0, "n": 238}, {"lat": 46.0, "lon": -77.5, "n": 87}, {"lat": 49.0, "lon": -72.0, "n": 239}, {"lat": 48.0, "lon": -65.0, "n": 15060}, {"lat": 49.0, "lon": -67.0, "n": 4620}, {"lat": 48.5, "lon": -68.0, "n": 16090}, {"lat": 50.5, "lon": -70.5, "n": 22505}, {"lat": 47.0, "lon": -75.5, "n": 238}, {"lat": 50.0, "lon": -68.5, "n": 1}, {"lat": 48.0, "lon": -70.0, "n": 89}, {"lat": 49.5, "lon": -78.0, "n": 18401}, {"lat": 47.0, "lon": -72.5, "n": 1}, {"lat": 48.0, "lon": -77.0, "n": 31291}, {"lat": 49.5, "lon": -80.0, "n": 598}, {"lat": 48.0, "lon": -65.5, "n": 30944}, {"lat": 49.0, "lon": -75.5, "n": 166}, {"lat": 47.5, "lon": -78.0, "n": 156}, {"lat": 50.5, "lon": -65.0, "n": 588}, {"lat": 49.0, "lon": -72.5, "n": 1}, {"lat": 46.0, "lon": -77.0, "n": 228}, {"lat": 47.5, "lon": -80.0, "n": 8}, {"lat": 49.5, "lon": -78.5, "n": 204}, {"lat": 48.0, "lon": -70.5, "n": 2}, {"lat": 47.0, "lon": -75.0, "n": 208}, {"lat": 50.0, "lon": -68.0, "n": 252}, {"lat": 48.0, "lon": -77.5, "n": 24040}, {"lat": 47.0, "lon": -72.0, "n": 246}, {"lat": 49.0, "lon": -67.5, "n": 4164}, {"lat": 50.5, "lon": -70.0, "n": 209}, {"lat": 48.5, "lon": -68.5, "n": 103}, {"lat": 50.5, "lon": -71.5, "n": 23519}, {"lat": 48.5, "lon": -69.0, "n": 141}, {"lat": 50.5, "lon": -76.5, "n": 131}, {"lat": 49.0, "lon": -66.0, "n": 14600}, {"lat": 48.0, "lon": -76.0, "n": 285}, {"lat": 45.0, "lon": -71.0, "n": 7845}, {"lat": 47.0, "lon": -73.5, "n": 203}, {"lat": 48.0, "lon": -71.0, "n": 207}, {"lat": 49.5, "lon": -79.0, "n": 18406}, {"lat": 45.0, "lon": -76.0, "n": 2}, {"lat": 50.0, "lon": -69.5, "n": 148}, {"lat": 47.0, "lon": -74.5, "n": 1}, {"lat": 49.0, "lon": -73.0, "n": 197}, {"lat": 46.0, "lon": -76.5, "n": 222}, {"lat": 49.0, "lon": -74.0, "n": 192}, {"lat": 50.5, "lon": -64.5, "n": 17236}, {"lat": 47.5, "lon": -79.5, "n": 165}, {"lat": 46.0, "lon": -71.5, "n": 23855}]

# Tuiles existantes
existing = {(round(t["lat"],1), round(t["lon"],1)): t["n"] for t in TILES}

# Identifie les trous (grille complète QC)
LAT_RANGE = [round(44.5 + i*0.5, 1) for i in range(14)]  # 44.5..51.0
LON_RANGE = [round(-80.0 + i*0.5, 1) for i in range(33)]  # -80.0..-64.0

gaps = []
for lat in LAT_RANGE:
    for lon in LON_RANGE:
        n = existing.get((lat, lon))
        if n is None or n <= 200:
            gaps.append((lat, lon, n))

print(f"\n{len(gaps)} cellules sans données ou sparse\n")

# Mapping approximatif coord → série NTS 250K
# Chaque feuillet couvre ~1°lat × 2°lon
# Séries QC: 21 (44-48N, 60-76W), 22 (48-52N, 60-76W), 31 (44-48N, 76-84W), 32 (48-52N, 76-84W)
LETTERS = list("ABCDEFGHJKLMNOP")  # NTS: I est omis

def lat_lon_to_nts(lat, lon):
    """Renvoie les codes NTS 250K plausibles pour un point."""
    lon = abs(lon)
    # Série
    if lon < 76:
        series = "21" if lat < 48 else "22"
    else:
        series = "31" if lat < 48 else "32"
    # Chaque lettre couvre 1°lat × 2°lon dans une grille 4×4
    # dans la série, on part du coin SW et on va E puis N (serpentin)
    if series in ("21", "22"):
        lon_base = 60.0
    else:
        lon_base = 76.0
    lat_base = 44.0 if series in ("21", "31") else 48.0

    col = int((lon - lon_base) / 2)   # 0-7
    row = int((lat - lat_base) / 1)   # 0-3
    # NTS snake: rows 0-3 bottom-top, cols 0-3 left-right, alternating
    idx = row * 4 + (col % 4 if row % 2 == 0 else 3 - col % 4)
    if 0 <= idx < len(LETTERS):
        return [f"{series}{LETTERS[idx]}"]
    return []

# Collecte tous les feuillets candidats
candidates = set()
for lat, lon, n in gaps:
    for code in lat_lon_to_nts(lat, lon):
        candidates.add(code)

# Feuillets déjà traités (dans process_nouveaux.py et traitement original)
# On vérifie tous les candidats sur le serveur MFFP
BASE = "https://diffusion.mffp.gouv.qc.ca/Diffusion/DonneeGratuite/Foret/DONNEES_FOR_ECO_SUD/Cartes_ecoforestieres_perturbations/02-Donnees/Decoupage250K"

print(f"Vérification de {len(candidates)} feuillets candidats sur MFFP...\n")
available = []
for code in sorted(candidates):
    url = f"{BASE}/{code}/CARTE_ECO_MAJ_{code}_GPKG.zip"
    try:
        r = requests.head(url, timeout=10, verify=False)
        status = r.status_code
    except Exception as e:
        status = f"ERR: {e}"
    mark = "✓" if status == 200 else "✗"
    print(f"  {mark} {code}  ({status})")
    if status == 200:
        available.append(code)

print(f"\n{len(available)} feuillets disponibles: {available}")
