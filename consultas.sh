#!/usr/bin/env bash
# Corre las 7 preguntas (consultas/q*.sql) y deja resultado + planes en salidas/qN_*.txt,
# luego el uso de índices y las exportaciones (GeoPackage y GeoJSON para los mapas).
#   ./consultas.sh            # todas
#   ./consultas.sh q4 q6      # algunas
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")"
mkdir -p salidas
psqlq() { docker compose exec -T -e PGOPTIONS=--client-min-messages=warning db \
            psql -X -v ON_ERROR_STOP=1 -U postgres -d tarea1 "$@"; }

docker compose up -d --wait >/dev/null
SEL="${*:-q1 q2 q3 q4 q5 q6 q7}"
[[ $# -eq 0 ]] && psqlq -q -c "SELECT pg_stat_reset()" >/dev/null   # el uso de índices cuenta desde aquí

for q in $SEL; do
  f=$(ls consultas/${q}_*.sql | head -1)
  out="salidas/$(basename "${f%.sql}").txt"
  t0=$(date +%s)
  psqlq -e -f "/consultas/$(basename "$f")" > "$out"
  echo "✓ $(basename "$f") → $out ($(( $(date +%s) - t0 )) s)"
done

if [[ $# -eq 0 ]]; then
  sleep 1   # pg_stat_user_indexes se actualiza con un pequeño retraso
  psqlq -f /consultas/z_indices_uso.sql > salidas/indices_uso.txt
  echo "✓ uso de índices → salidas/indices_uso.txt"
  ./scripts/exportar.sh
fi
