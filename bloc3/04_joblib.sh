#!/usr/bin/env bash
# =============================================================================
# BLOC 3 — JOBLIB : SAUVEGARDER / CHARGER DES MODÈLES ML
# =============================================================================
# Sujet : point 6
# Usage : ./04_joblib.sh <fonction>
# =============================================================================

set -euo pipefail

MODEL_DIR="${MODEL_DIR:-models}"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 : ENTRAÎNER ET SAUVEGARDER UN MODÈLE (train.py)
# ─────────────────────────────────────────────────────────────────────────────
# Ce modèle est celui utilisé par l'API FastAPI (06_fastapi_pydantic.sh).

train_and_dump() {
    pip install scikit-learn joblib numpy
    mkdir -p "${MODEL_DIR}"
    cat > train.py <<'EOF'
import os
import joblib
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

FEATURES = ["age", "anciennete_mois", "nb_commandes", "panier_moyen", "nb_reclamations"]
MODEL_PATH = os.getenv("MODEL_PATH", "models/model.joblib")

# Données fictives TechShop : churn si peu de commandes et beaucoup de réclamations
rng = np.random.default_rng(42)
X = np.column_stack([
    rng.integers(18, 80, 1000),     # age
    rng.integers(0, 72, 1000),      # anciennete_mois
    rng.integers(0, 40, 1000),      # nb_commandes
    rng.uniform(10, 250, 1000),     # panier_moyen
    rng.integers(0, 6, 1000),       # nb_reclamations
])
y = ((X[:, 2] < 5) & (X[:, 4] >= 2)).astype(int)

pipe = Pipeline([("scaler", StandardScaler()),
                 ("clf", RandomForestClassifier(n_estimators=100, random_state=42))])
pipe.fit(X, y)

# dump : sérialise n'importe quel objet Python (modèle, pipeline, dict, array...)
joblib.dump(pipe, MODEL_PATH)

# Sauvegarder un "bundle" : modèle + métadonnées dans un seul fichier
bundle = {"model": pipe, "features": FEATURES, "version": "1.0.0"}
joblib.dump(bundle, MODEL_PATH.replace(".joblib", "_bundle.joblib"))

# Compression (fichier plus petit, chargement un peu plus lent) : 0-9 ou tuple
joblib.dump(pipe, MODEL_PATH + ".gz", compress=("gzip", 3))
print("Modèle sauvegardé :", MODEL_PATH)
EOF
    python3 train.py
    ls -lh "${MODEL_DIR}"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 : CHARGER ET UTILISER LE MODÈLE
# ─────────────────────────────────────────────────────────────────────────────

load_and_predict() {
    python3 - <<'EOF'
import joblib
import numpy as np

pipe = joblib.load("models/model.joblib")
print(type(pipe))
print(pipe.predict(np.array([[35, 24, 12, 58.5, 1]])))
print(pipe.predict_proba(np.array([[52, 3, 1, 20.0, 4]])))

bundle = joblib.load("models/model_bundle.joblib")
print(bundle["features"], bundle["version"])

compressed = joblib.load("models/model.joblib.gz")   # compression détectée automatiquement
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 : AUTRES OBJETS DATA SCIENCE & PIÈGES
# ─────────────────────────────────────────────────────────────────────────────

joblib_tips() {
    python3 - <<'EOF'
import joblib
import numpy as np
from sklearn.preprocessing import StandardScaler

# Un scaler, un encodeur, un gros array numpy... tout se sauvegarde pareil
scaler = StandardScaler().fit(np.random.rand(100, 3))
joblib.dump(scaler, "models/scaler.joblib")
joblib.dump(np.arange(1_000_000), "models/big_array.joblib")

# Parallel / delayed : l'autre usage de joblib (calcul parallèle)
from joblib import Parallel, delayed
print(Parallel(n_jobs=-1)(delayed(pow)(i, 2) for i in range(5)))
EOF
    # Pièges :
    #  - Charger avec la MÊME version de scikit-learn que pour l'entraînement
    #    (sinon InconsistentVersionWarning / erreur) → figer dans requirements.txt
    #  - joblib.load exécute du code (pickle) → ne charger que des fichiers de confiance
    #  - Ne pas committer les gros modèles dans Git → volume Docker / PV Kubernetes
}

# ─────────────────────────────────────────────────────────────────────────────
# Lancement : ./04_joblib.sh <fonction>
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ $# -eq 0 ]]; then
        echo "Usage : $0 <fonction>"; declare -F | awk '{print "  - " $3}'
    else
        "$@"
    fi
fi
