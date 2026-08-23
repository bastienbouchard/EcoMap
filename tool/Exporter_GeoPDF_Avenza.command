#!/bin/bash
# EcoMap — Export GeoPDF pour Avenza Maps
# Double-clique pour lancer
cd "$(dirname "$0")/.."

echo "================================================"
echo "  EcoMap — Export GeoPDF (Avenza Maps)"
echo "================================================"
echo ""

# Vérifier Pillow
if ! python3 -c "import PIL" 2>/dev/null; then
    echo "📦 Installation de Pillow (requis une seule fois)..."
    pip3 install Pillow
    echo ""
fi

# Demander le fichier .mbtiles si pas passé en argument
if [ -n "$1" ]; then
    DB="$1"
else
    echo "Glisse le fichier .mbtiles ici et appuie sur Entrée,"
    echo "ou appuie sur Entrée pour utiliser la zone de test (Lac Pikauba) :"
    read -r DB
    DB="${DB//\'/}"   # enlever les apostrophes ajoutées par le Finder
    DB="${DB// /\\ }" # échapper les espaces
    if [ -z "$DB" ]; then
        DB="/tmp/ecomap_verify/satellite.mbtiles"
        if [ ! -f "$DB" ]; then
            echo ""
            echo "Zone de test absente. Lance d'abord :"
            echo "  python3 tool/verify_offline.py --check"
            read -p "Appuie sur Entrée pour fermer..."
            exit 1
        fi
    fi
fi

echo ""
python3 tool/export_geopdf.py "$DB"

echo ""
echo "Le PDF est sur ton Bureau (~/Desktop)."
echo "AirDrop → iPhone → Ouvrir avec Avenza Maps"
echo ""
read -p "Appuie sur Entrée pour fermer..."
