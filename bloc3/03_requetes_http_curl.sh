#!/usr/bin/env bash
# =============================================================================
# BLOC 3 — REQUÊTES HTTP : curl (Bash) & requests (Python)
# =============================================================================
# Sujet : points 5 (Python & Bash vers une URL) et 12 (commande curl)
# Prérequis : l'API TechShop tourne (voir 06_fastapi_pydantic.sh → run_api)
# Usage : ./03_requetes_http_curl.sh <fonction>
# =============================================================================

set -euo pipefail

API_URL="${API_URL:-http://localhost:8000}"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 : CURL — LES OPTIONS À CONNAÎTRE
# ─────────────────────────────────────────────────────────────────────────────
#  -X METHOD        méthode HTTP (GET par défaut, POST si -d)
#  -H "K: V"        en-tête
#  -d '...'         corps de la requête  (-d @fichier.json pour un fichier)
#  -i               affiche les en-têtes de réponse
#  -v               verbeux (requête + réponse complètes, debug)
#  -s               silencieux (pas de barre de progression)
#  -o fichier       écrit la réponse dans un fichier   (-O : nom distant)
#  -L               suit les redirections
#  -w '%{http_code}' affiche le code HTTP
#  -u user:pass     authentification basique
#  -f               échoue (code retour ≠ 0) si HTTP >= 400 → utile en script/CI

curl_get() {
    curl "${API_URL}/health"
    curl -s "${API_URL}/health" | python3 -m json.tool     # joli JSON
    curl -i "${API_URL}/health"                            # + en-têtes
    curl -s -o /dev/null -w '%{http_code}\n' "${API_URL}/health"   # code seul
    curl -s "${API_URL}/docs" -o docs.html                 # sauvegarder
    curl -G "${API_URL}/items" --data-urlencode "q=écran 4k"   # query string encodée
}

curl_post_json() {
    curl -X POST "${API_URL}/predict" \
         -H "Content-Type: application/json" \
         -d '{"age": 35, "anciennete_mois": 24, "nb_commandes": 12, "panier_moyen": 58.5, "nb_reclamations": 1}'

    # Depuis un fichier
    cat > client.json <<'EOF'
{"age": 52, "anciennete_mois": 3, "nb_commandes": 1, "panier_moyen": 20.0, "nb_reclamations": 4}
EOF
    curl -s -X POST "${API_URL}/predict" -H "Content-Type: application/json" -d @client.json

    # Données invalides → 422 Unprocessable Entity (validation Pydantic)
    curl -s -w '\nHTTP %{http_code}\n' -X POST "${API_URL}/predict" \
         -H "Content-Type: application/json" -d '{"age": "abc"}'
}

curl_other_methods() {
    curl -X PUT    "${API_URL}/items/1" -H "Content-Type: application/json" -d '{"name":"x"}'
    curl -X DELETE "${API_URL}/items/1"
    curl -H "Authorization: Bearer ${API_TOKEN:-xxx}" "${API_URL}/secure"
    curl -u admin:admin http://localhost:3000/api/health          # Grafana (auth basique)
    curl -F "file=@data.csv" "${API_URL}/upload"                  # multipart / upload
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 : CURL DANS UN SCRIPT (attente, boucle, test de charge)
# ─────────────────────────────────────────────────────────────────────────────

wait_for_api() {
    # Attendre que l'API réponde (utile après docker compose up / en CI)
    for i in $(seq 1 30); do
        if curl -sf "${API_URL}/health" > /dev/null; then
            echo "API prête après ${i} essai(s)"; return 0
        fi
        sleep 2
    done
    echo "API indisponible" >&2; return 1
}

generate_traffic() {
    # Générer du trafic pour alimenter Prometheus / Grafana
    for _ in $(seq 1 100); do
        curl -s -o /dev/null -X POST "${API_URL}/predict" \
             -H "Content-Type: application/json" \
             -d "{\"age\": $((RANDOM % 60 + 18)), \"anciennete_mois\": $((RANDOM % 60)), \"nb_commandes\": $((RANDOM % 30)), \"panier_moyen\": $((RANDOM % 200)).0, \"nb_reclamations\": $((RANDOM % 5))}"
        curl -s -o /dev/null "${API_URL}/health"
    done
    echo "100 requêtes envoyées — voir ${API_URL}/metrics"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 : PYTHON — LIBRAIRIE requests
# ─────────────────────────────────────────────────────────────────────────────

python_requests() {
    pip install requests
    cat > client_api.py <<'EOF'
import os
import requests

API_URL = os.getenv("API_URL", "http://localhost:8000")

# GET
r = requests.get(f"{API_URL}/health", timeout=5)
print(r.status_code, r.json())

# POST JSON (json= sérialise et ajoute Content-Type: application/json)
client = {"age": 35, "anciennete_mois": 24, "nb_commandes": 12,
          "panier_moyen": 58.5, "nb_reclamations": 1}
r = requests.post(f"{API_URL}/predict", json=client, timeout=5)
r.raise_for_status()                  # exception si 4xx / 5xx
print(r.json())

# Paramètres de requête, en-têtes
r = requests.get(f"{API_URL}/items", params={"q": "écran"},
                 headers={"Authorization": "Bearer xxx"}, timeout=5)
print(r.url)

# Gestion d'erreur
try:
    requests.get("http://localhost:9999", timeout=2)
except requests.exceptions.ConnectionError as e:
    print("Connexion impossible :", type(e).__name__)
EOF
    python3 client_api.py
}

python_urllib() {
    # Sans dépendance (bibliothèque standard)
    python3 - <<'EOF'
import json, os, urllib.request
url = os.getenv("API_URL", "http://localhost:8000") + "/predict"
data = json.dumps({"age": 35, "anciennete_mois": 24, "nb_commandes": 12,
                   "panier_moyen": 58.5, "nb_reclamations": 1}).encode()
req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=5) as resp:
    print(resp.status, json.loads(resp.read()))
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# Lancement : ./03_requetes_http_curl.sh <fonction>
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ $# -eq 0 ]]; then
        echo "Usage : $0 <fonction>"; declare -F | awk '{print "  - " $3}'
    else
        "$@"
    fi
fi
