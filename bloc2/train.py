"""Entraînement d'un modèle de détection de fraude (statut SUSPECTED_FRAUD).

Étapes :
    1. Lecture des données depuis la base (requête SQL agrégée par commande).
    2. Features connues au moment de la commande uniquement (pas de fuite).
    3. Découpage temporel : on apprend sur le passé, on teste sur le futur.
    4. Comparaison de modèles en validation croisée (PR-AUC, classes déséquilibrées).
    5. Évaluation finale du meilleur modèle sur le jeu de test.
    6. Sauvegarde du pipeline (joblib) et des métriques (JSON).

Usage :
    python train.py [--split-date 2017-07-01]
"""
import argparse
import json
from datetime import datetime

import joblib
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.dummy import DummyClassifier
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    average_precision_score, classification_report, confusion_matrix, roc_auc_score,
)
from sklearn.model_selection import StratifiedKFold, cross_val_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

from config import MODELS_DIR, get_logger
from create_db import get_engine

logger = get_logger("train")

# Une ligne = une commande. Le statut sert uniquement à construire la cible.
QUERY = """
SELECT
    o.id                       AS order_id,
    o.order_date,
    o.payment_type,
    o.market,
    o.region                   AS order_region,
    c.state                    AS customer_state,
    COUNT(*)                   AS n_items,
    SUM(i.quantity)            AS total_quantity,
    SUM(i.sales)               AS total_sales,
    MAX(i.unit_price)          AS max_unit_price,
    COUNT(DISTINCT p.category_id) AS n_categories,
    CASE WHEN o.status = 'SUSPECTED_FRAUD' THEN 1 ELSE 0 END AS is_fraud
FROM orders o
JOIN customers   c ON c.id = o.customer_id
JOIN order_items i ON i.order_id = o.id
JOIN products    p ON p.id = i.product_id
GROUP BY o.id, o.order_date, o.payment_type, o.market, o.region, c.state, o.status
"""

CATEGORICAL = ["payment_type", "market", "order_region", "customer_state"]
NUMERICAL = ["n_items", "total_quantity", "total_sales", "max_unit_price",
             "n_categories", "order_hour", "order_weekday", "order_month"]
TARGET = "is_fraud"


def load_dataset() -> pd.DataFrame:
    df = pd.read_sql(QUERY, get_engine(), parse_dates=["order_date"])
    df["order_hour"] = df["order_date"].dt.hour
    df["order_weekday"] = df["order_date"].dt.weekday
    df["order_month"] = df["order_date"].dt.month
    logger.info("%d commandes chargées, taux de fraude %.2f %%", len(df), 100 * df[TARGET].mean())
    return df


def temporal_split(df: pd.DataFrame, split_date: str):
    train = df[df["order_date"] < split_date]
    test = df[df["order_date"] >= split_date]
    logger.info("Train : %d commandes (< %s) | Test : %d commandes", len(train), split_date, len(test))
    return train[CATEGORICAL + NUMERICAL], train[TARGET], test[CATEGORICAL + NUMERICAL], test[TARGET]


def build_pipeline(classifier) -> Pipeline:
    preprocessing = ColumnTransformer([
        ("cat", OneHotEncoder(handle_unknown="ignore", min_frequency=20), CATEGORICAL),
        ("num", StandardScaler(), NUMERICAL),
    ])
    return Pipeline([("prep", preprocessing), ("clf", classifier)])


CANDIDATES = {
    # Référence : prédit toujours la classe majoritaire. Tout modèle doit faire mieux.
    "baseline_dummy": DummyClassifier(strategy="prior"),
    "logistic_regression": LogisticRegression(class_weight="balanced", max_iter=1000),
    "random_forest": RandomForestClassifier(
        n_estimators=200, max_depth=12, min_samples_leaf=20,
        class_weight="balanced", n_jobs=-1, random_state=42,
    ),
}


def compare_models(X, y) -> dict[str, float]:
    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    scores = {}
    for name, clf in CANDIDATES.items():
        cv_scores = cross_val_score(build_pipeline(clf), X, y, cv=cv, scoring="average_precision")
        scores[name] = float(cv_scores.mean())
        logger.info("CV %-20s PR-AUC = %.3f (± %.3f)", name, cv_scores.mean(), cv_scores.std())
    return scores


def evaluate(model: Pipeline, X, y) -> dict:
    proba = model.predict_proba(X)[:, 1]
    pred = model.predict(X)
    metrics = {
        "roc_auc": round(float(roc_auc_score(y, proba)), 4),
        "pr_auc": round(float(average_precision_score(y, proba)), 4),
        "fraud_rate": round(float(y.mean()), 4),  # PR-AUC d'un modèle aléatoire
        "confusion_matrix": confusion_matrix(y, pred).tolist(),
        "report": classification_report(y, pred, output_dict=True, zero_division=0),
    }
    logger.info("Test ROC-AUC = %.3f | PR-AUC = %.3f (hasard = %.3f)",
                metrics["roc_auc"], metrics["pr_auc"], metrics["fraud_rate"])
    logger.info("Matrice de confusion [[VN, FP], [FN, VP]] : %s", metrics["confusion_matrix"])
    logger.info("\n%s", classification_report(y, pred, zero_division=0))
    return metrics


def main(split_date: str) -> None:
    df = load_dataset()
    X_train, y_train, X_test, y_test = temporal_split(df, split_date)

    cv_scores = compare_models(X_train, y_train)
    best_name = max(cv_scores, key=cv_scores.get)
    logger.info("Meilleur modèle : %s", best_name)

    model = build_pipeline(CANDIDATES[best_name]).fit(X_train, y_train)
    test_metrics = evaluate(model, X_test, y_test)

    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    joblib.dump(model, MODELS_DIR / "fraud_model.joblib")
    with (MODELS_DIR / "metrics.json").open("w", encoding="utf-8") as f:
        json.dump({
            "trained_at": datetime.now().isoformat(timespec="seconds"),
            "model": best_name,
            "split_date": split_date,
            "features": CATEGORICAL + NUMERICAL,
            "cv_pr_auc": cv_scores,
            "test": test_metrics,
        }, f, indent=2, ensure_ascii=False)
    logger.info("Modèle et métriques sauvegardés dans %s", MODELS_DIR)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--split-date", default="2017-07-01")
    args = parser.parse_args()
    main(args.split_date)
