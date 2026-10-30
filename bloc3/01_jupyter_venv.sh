#!/usr/bin/env bash
# =============================================================================
# BLOC 3 — JUPYTER & ENVIRONNEMENTS VIRTUELS PYTHON
# =============================================================================
# Sujet : points 1 (Jupyter) et 4 (environnements virtuels)
# Usage : ./01_jupyter_venv.sh <fonction>   (sans argument : liste des fonctions)
# OS cible : Ubuntu 22.04 / Debian 12 (équivalents Windows en commentaire)
# =============================================================================

set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/techshop}"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 : CRÉER UN ENVIRONNEMENT VIRTUEL (venv)
# ─────────────────────────────────────────────────────────────────────────────
# Un venv = une copie isolée de l'interpréteur + son propre dossier site-packages.
# → chaque projet a ses versions de librairies sans polluer le Python système.

create_venv() {
    echo "=== Création du venv dans ${PROJECT_DIR} ==="
    sudo apt-get install -y python3-venv python3-pip   # paquet requis sur Debian/Ubuntu

    mkdir -p "${PROJECT_DIR}" && cd "${PROJECT_DIR}"
    python3 -m venv .venv                  # crée le dossier .venv/

    # Activation (modifie PATH : python et pip pointent vers .venv/bin/)
    # shellcheck disable=SC1091
    source .venv/bin/activate              # Windows : .venv\Scripts\activate
    which python                           # → .../techshop/.venv/bin/python
    python -m pip install --upgrade pip

    deactivate                             # sortir du venv
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 : GÉRER LES DÉPENDANCES (requirements.txt)
# ─────────────────────────────────────────────────────────────────────────────

manage_requirements() {
    cd "${PROJECT_DIR}"
    # shellcheck disable=SC1091
    source .venv/bin/activate

    pip install fastapi uvicorn pydantic scikit-learn joblib pytest requests \
                prometheus-fastapi-instrumentator python-dotenv

    pip freeze > requirements.txt          # figer les versions exactes
    pip install -r requirements.txt        # réinstaller ailleurs à l'identique
    pip list                               # paquets installés
    pip show fastapi                       # détails d'un paquet

    # Bonne pratique : ne JAMAIS committer le venv
    echo ".venv/" >> .gitignore
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 : ALTERNATIVES (pour info)
# ─────────────────────────────────────────────────────────────────────────────

venv_alternatives() {
    # virtualenv (plus ancien, plus d'options)
    pip install virtualenv && virtualenv -p python3.11 venv311

    # conda
    # conda create -n techshop python=3.11 && conda activate techshop

    # uv (très rapide)
    # uv venv && source .venv/bin/activate && uv pip install -r requirements.txt
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 : JUPYTER — INSTALLATION ET LANCEMENT
# ─────────────────────────────────────────────────────────────────────────────

install_jupyter() {
    cd "${PROJECT_DIR}"
    # shellcheck disable=SC1091
    source .venv/bin/activate
    pip install jupyterlab notebook ipykernel
}

run_jupyter() {
    cd "${PROJECT_DIR}"
    # shellcheck disable=SC1091
    source .venv/bin/activate
    jupyter lab                                            # UI moderne (http://localhost:8888)
    # jupyter notebook                                     # UI classique
    # jupyter lab --no-browser --ip=0.0.0.0 --port=8888    # sur un serveur distant
    # jupyter server list                                  # serveurs + tokens actifs
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 : ENREGISTRER LE VENV COMME KERNEL JUPYTER
# ─────────────────────────────────────────────────────────────────────────────
# Sans ça, le notebook peut tourner avec un autre Python que celui du venv
# → "ModuleNotFoundError" alors que le paquet est bien installé dans .venv.

register_kernel() {
    cd "${PROJECT_DIR}"
    # shellcheck disable=SC1091
    source .venv/bin/activate
    python -m ipykernel install --user --name techshop --display-name "Python (techshop)"
    jupyter kernelspec list                # kernels disponibles
    # jupyter kernelspec uninstall techshop
    # Dans un notebook, vérifier :  import sys; print(sys.executable)
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6 : EXÉCUTER / CONVERTIR UN NOTEBOOK EN LIGNE DE COMMANDE
# ─────────────────────────────────────────────────────────────────────────────

nbconvert_examples() {
    jupyter nbconvert --to script   analyse.ipynb                # → analyse.py
    jupyter nbconvert --to html     analyse.ipynb                # → rapport HTML
    jupyter nbconvert --to notebook --execute --inplace analyse.ipynb   # exécuter (CI)
    # Magics utiles dans une cellule :
    #   !pip install x     → commande shell
    #   %env MA_VAR=1      → variable d'environnement
    #   %timeit f()        → mesure de temps
    #   %%bash             → cellule entière en bash
}

# ─────────────────────────────────────────────────────────────────────────────
# Lancement : ./01_jupyter_venv.sh <fonction>
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ $# -eq 0 ]]; then
        echo "Usage : $0 <fonction>"; declare -F | awk '{print "  - " $3}'
    else
        "$@"
    fi
fi
