#!/bin/bash
# Lance 4 processus parallèles pour générer les tuiles V5 (simplification 0.0004°)
# Bandes: 44.5-47.5 | 47.5-50.5 | 50.5-53.5 | 53.5-57.0

SCRIPT="/Users/bastienbouchard/EcoMap/process_prov.py"
PYTHON="/usr/bin/python3"
LOG_DIR="/tmp"

mkdir -p ~/EcoMap_tiles_v5

echo "=== V5 PARALLEL START ==="
date

$PYTHON "$SCRIPT" 44.5 47.5 > "$LOG_DIR/v5_band1.log" 2>&1 &
PID1=$!
echo "Band 1 (44.5-47.5): PID $PID1 → $LOG_DIR/v5_band1.log"

$PYTHON "$SCRIPT" 47.5 50.5 > "$LOG_DIR/v5_band2.log" 2>&1 &
PID2=$!
echo "Band 2 (47.5-50.5): PID $PID2 → $LOG_DIR/v5_band2.log"

$PYTHON "$SCRIPT" 50.5 53.5 > "$LOG_DIR/v5_band3.log" 2>&1 &
PID3=$!
echo "Band 3 (50.5-53.5): PID $PID3 → $LOG_DIR/v5_band3.log"

$PYTHON "$SCRIPT" 53.5 57.0 > "$LOG_DIR/v5_band4.log" 2>&1 &
PID4=$!
echo "Band 4 (53.5-57.0): PID $PID4 → $LOG_DIR/v5_band4.log"

echo ""
echo "Attente des 4 processus..."
wait $PID1; echo "Band 1 terminée (code $?)"
wait $PID2; echo "Band 2 terminée (code $?)"
wait $PID3; echo "Band 3 terminée (code $?)"
wait $PID4; echo "Band 4 terminée (code $?)"

echo ""
echo "=== V5 TERMINÉ ==="
date
TOTAL=$(ls ~/EcoMap_tiles_v5/*.gz 2>/dev/null | wc -l | tr -d ' ')
echo "Total tuiles: $TOTAL"
