"""
model.py - Entraînement du modèle de prédiction du salaire (partie III.I)

  Q.1 jointure SQL employees / jobs / companies
  Q.2 préparation des colonnes + One-Hot Encoding (pandas)
  Q.3 entraînement (train/test split, baseline vs Random Forest)
  Q.4 évaluation + sauvegarde du modèle sur disque

Usage : python model.py
"""
import os

import joblib
import numpy as np
import pandas as pd
from sklearn.dummy import DummyRegressor
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split

from database import get_engine

MODEL_PATH = os.path.join(os.path.dirname(__file__), "models", "salary_model.joblib")

# Q.1 : jointure des 3 tables, uniquement les salaires connus
QUERY = """
SELECT e.age, e.gender, e.country, e.marital_status, e.education_level,
       e.experience_years, e.has_certifications, e.work_hours_per_week,
       e.projects_completed,
       c.name AS company, j.department, j.position_level, j.performance_score,
       j.join_date, j.salary
FROM employees e
JOIN jobs j      ON j.employee_id = e.id
JOIN companies c ON c.id = j.company_id
WHERE j.salary IS NOT NULL
"""

CATEGORICAL = ["gender", "country", "marital_status", "education_level",
               "company", "department", "position_level"]


def load_data(engine):
    return pd.read_sql(QUERY, engine)


def prepare(df):
    """Q.2 : transforme les colonnes et encode les catégories."""
    df = df.copy()
    # ancienneté (en années) plutôt qu'une date brute
    join_date = pd.to_datetime(df.pop("join_date"))
    df["seniority_years"] = (pd.Timestamp("today") - join_date).dt.days / 365.25

    df["has_certifications"] = df["has_certifications"].astype(int)
    # valeur manquante = modalité à part entière pour les catégories
    df[CATEGORICAL] = df[CATEGORICAL].fillna("Unknown")
    # expérience inconnue -> médiane
    df["experience_years"] = df["experience_years"].fillna(df["experience_years"].median())

    df = pd.get_dummies(df, columns=CATEGORICAL, dtype=int)  # One-Hot Encoding
    y = df.pop("salary")
    return df, y


def evaluate(name, model, X_test, y_test):
    pred = model.predict(X_test)
    print(f"{name:15s} MAE={mean_absolute_error(y_test, pred):8.0f}  "
          f"RMSE={np.sqrt(mean_squared_error(y_test, pred)):8.0f}  "
          f"R2={r2_score(y_test, pred):.3f}")


def main():
    X, y = prepare(load_data(get_engine()))
    print(f"Jeu d'entraînement : {X.shape[0]} lignes, {X.shape[1]} features")

    # Q.3 : séparation train / test AVANT l'entraînement (pas de fuite de données)
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42)

    # baseline : prédit toujours la moyenne -> sert de point de comparaison
    baseline = DummyRegressor().fit(X_train, y_train)
    model = RandomForestRegressor(n_estimators=100, max_depth=12,
                                  n_jobs=-1, random_state=42).fit(X_train, y_train)

    # Q.4 : évaluation sur le jeu de test
    evaluate("Baseline", baseline, X_test, y_test)
    evaluate("RandomForest", model, X_test, y_test)

    top = pd.Series(model.feature_importances_, index=X.columns).nlargest(8)
    print("\nVariables les plus importantes :\n", top.round(3).to_string())

    # sauvegarde du modèle + liste des colonnes (nécessaire pour prédire plus tard)
    os.makedirs(os.path.dirname(MODEL_PATH), exist_ok=True)
    joblib.dump({"model": model, "columns": list(X.columns)}, MODEL_PATH)
    print(f"\nModèle sauvegardé : {MODEL_PATH}")


if __name__ == "__main__":
    main()
