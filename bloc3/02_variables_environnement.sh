#!/usr/bin/env bash
# =============================================================================
# BLOC 3 — VARIABLES D'ENVIRONNEMENT (export, .bashrc, Python)
# =============================================================================
# Sujet : points 2 (export / .bashrc) et 3 (variables d'env dans Python)
# Usage : ./02_variables_environnement.sh <fonction>
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 : VARIABLE SHELL vs VARIABLE D'ENVIRONNEMENT
# ─────────────────────────────────────────────────────────────────────────────
# Variable shell     : visible uniquement dans le shell courant.
# Variable exportée  : transmise aux processus enfants (python, docker, ...).

export_basics() {
    MA_VAR="locale"                        # variable shell (non exportée)
    bash -c 'echo "enfant voit : [${MA_VAR:-}]"'      # → vide

    export MA_VAR                          # on l'exporte
    bash -c 'echo "enfant voit : [${MA_VAR:-}]"'      # → locale

    export API_URL="http://localhost:8000" # déclaration + export en une ligne
    echo "${API_URL}"
    env | grep API_URL                     # lister les variables d'environnement
    printenv API_URL                       # afficher une seule variable

    API_PORT=9000 bash -c 'echo "${API_PORT}"'   # variable pour UNE commande seulement
    unset MA_VAR                           # supprimer
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 : PERSISTANCE VIA ~/.bashrc
# ─────────────────────────────────────────────────────────────────────────────
# Un export tapé dans le terminal disparaît à la fermeture.
# ~/.bashrc est lu à chaque ouverture de shell interactif → on y place les exports.

bashrc_persist() {
    cp ~/.bashrc ~/.bashrc.bak             # toujours sauvegarder avant d'éditer

    cat >> ~/.bashrc <<'EOF'

# ── TechShop (bloc 3) ─────────────────────────────
export API_URL="http://localhost:8000"
export MODEL_PATH="$HOME/techshop/models/model.joblib"
export PATH="$HOME/.local/bin:$PATH"       # ajouter un dossier au PATH
alias venv='source .venv/bin/activate'
alias k='kubectl'
EOF

    # Recharger sans fermer le terminal
    # shellcheck disable=SC1090
    source ~/.bashrc                       # équivalent : . ~/.bashrc
    echo "MODEL_PATH=${MODEL_PATH:-non défini}"

    # Pour retirer : éditer ~/.bashrc (nano ~/.bashrc) puis source ~/.bashrc
    # .bashrc  : shells interactifs  | .profile / .bash_profile : shells de login
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 : FICHIER .env (secrets locaux, jamais committé)
# ─────────────────────────────────────────────────────────────────────────────

dotenv_file() {
    cat > .env <<'EOF'
API_URL=http://localhost:8000
API_KEY=change-me
DB_HOST=localhost
DB_PORT=3306
DEBUG=true
EOF
    echo ".env" >> .gitignore

    # Charger le .env dans le shell courant (export de toutes les variables)
    set -a; source .env; set +a
    echo "DB_HOST=${DB_HOST}"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 : LIRE LES VARIABLES DANS UN SCRIPT PYTHON
# ─────────────────────────────────────────────────────────────────────────────

python_env_script() {
    cat > env_demo.py <<'EOF'
import os

# 1) os.environ["X"]   → KeyError si absente (variable obligatoire)
api_url = os.environ["API_URL"]

# 2) os.getenv("X", défaut) → None / défaut si absente (variable optionnelle)
db_port = int(os.getenv("DB_PORT", "3306"))          # toujours une str → convertir
debug = os.getenv("DEBUG", "false").lower() == "true"

# 3) Écrire une variable (visible par ce process et ses enfants uniquement)
os.environ["RUN_ID"] = "42"

# 4) python-dotenv : charger un fichier .env (pip install python-dotenv)
try:
    from dotenv import load_dotenv
    load_dotenv()                     # n'écrase pas les variables déjà définies
except ImportError:
    pass

print(f"API_URL={api_url} DB_PORT={db_port} DEBUG={debug}")
print("API_KEY présente :", "API_KEY" in os.environ)
EOF

    export API_URL="http://localhost:8000"
    python3 env_demo.py
    DB_PORT=5432 DEBUG=true python3 env_demo.py      # surcharge ponctuelle
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 : LES MÊMES VARIABLES DANS DOCKER / CI / K8S (rappel)
# ─────────────────────────────────────────────────────────────────────────────

env_elsewhere() {
    docker run -e API_KEY=secret --env-file .env python:3.11-slim env
    # docker-compose.yml : environment: [API_KEY=...]   ou   env_file: .env
    # .gitlab-ci.yml     : variables:  ou  Settings > CI/CD > Variables (masquées)
    # Kubernetes         : ConfigMap / Secret → envFrom: configMapRef
}

# ─────────────────────────────────────────────────────────────────────────────
# Lancement : ./02_variables_environnement.sh <fonction>
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ $# -eq 0 ]]; then
        echo "Usage : $0 <fonction>"; declare -F | awk '{print "  - " $3}'
    else
        "$@"
    fi
fi
