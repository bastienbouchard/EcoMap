#!/bin/bash
TILES_DIR="$HOME/EcoMap_tiles"
BUCKET="ecomap-tiles"
total=$(ls "$TILES_DIR"/*.gz | wc -l | tr -d ' ')
done=0
failed=0

for f in "$TILES_DIR"/*.gz; do
  fname=$(basename "$f")
  done=$((done + 1))
  echo -n "[$done/$total] $fname... "
  result=$(npx --yes wrangler r2 object put "$BUCKET/$fname" --file "$f" --content-type application/gzip --remote 2>&1)
  if echo "$result" | grep -q "Upload complete"; then
    echo "OK"
  else
    echo "ERREUR: $result"
    failed=$((failed + 1))
  fi
done

echo ""
echo "=== TERMINÉ — $done fichiers, $failed erreurs ==="
