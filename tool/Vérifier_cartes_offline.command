#!/bin/bash
# Double-clique ce fichier pour vérifier les cartes offline avant un build Codemagic

cd "$(dirname "$0")/.."
python3 tool/verify_offline.py --serve
