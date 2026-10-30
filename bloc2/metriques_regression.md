# Métriques de régression : MAE, RMSE, MAPE, R²

(+ un bloc [classification](#bonus--métriques-de-classification) à la fin)

Notations : $y_i$ valeur réelle, $\hat{y}_i$ prédiction, $\bar{y}$ moyenne des $y_i$, $n$ nombre d'observations.

Exemple chiffré : notebook [03_regression.ipynb](03_regression.ipynb) (prix de logements simulés).

---

## MAE — Mean Absolute Error (erreur absolue moyenne)

$$\text{MAE} = \frac{1}{n}\sum_{i=1}^{n} |y_i - \hat{y}_i|$$

- **Erreur moyenne dans l'unité de la cible** (ici €) : « on se trompe en moyenne de 28 000 € ».
- Toutes les erreurs pèsent proportionnellement → **robuste aux valeurs aberrantes**.
- La plus simple à expliquer à un interlocuteur métier.

## RMSE — Root Mean Squared Error (racine de l'erreur quadratique moyenne)

$$\text{RMSE} = \sqrt{\frac{1}{n}\sum_{i=1}^{n} (y_i - \hat{y}_i)^2}$$

- Aussi **dans l'unité de la cible**.
- Les erreurs sont mises au carré → **les grosses erreurs pèsent beaucoup plus**
  (une erreur de 100 k€ compte 100 fois plus qu'une erreur de 10 k€).
- Toujours **RMSE ≥ MAE** ; un grand écart entre les deux signale quelques erreurs importantes.
- Métrique de référence quand une grosse erreur coûte cher.

## MAPE — Mean Absolute Percentage Error (erreur absolue moyenne en %)

$$\text{MAPE} = \frac{100}{n}\sum_{i=1}^{n} \left|\frac{y_i - \hat{y}_i}{y_i}\right|$$

- **Erreur relative moyenne, en %** : « on se trompe en moyenne de 11 % ».
- Sans unité → comparable entre problèmes d'échelles différentes.
- ⚠️ **Instable, voire infinie, si $y_i$ est proche de 0**.
- Asymétrique : une sous-estimation est plafonnée à 100 % d'erreur, une surestimation n'a pas
  de limite → pénalise davantage les prédictions trop hautes.

## R² — Coefficient de détermination

$$R^2 = 1 - \frac{\sum (y_i - \hat{y}_i)^2}{\sum (y_i - \bar{y})^2}$$

- **Part de la variance de la cible expliquée par le modèle**, en comparaison d'un modèle
  qui prédirait toujours la moyenne $\bar{y}$.
- **1** : prédiction parfaite.
- **0** : pas mieux que prédire la moyenne.
- **Négatif** : pire que la moyenne.
- Sans unité, mais **ne dit pas si l'erreur est acceptable** pour le métier :
  un R² de 0,9 peut cacher des erreurs de 40 000 €.

---

## Récapitulatif

| Métrique | Unité | Sensible aux grosses erreurs | Usage typique |
|---|---|---|---|
| **MAE** | celle de la cible | non | erreur « moyenne », la plus facile à expliquer |
| **RMSE** | celle de la cible | **oui** | quand les grosses erreurs coûtent cher |
| **MAPE** | % | non | erreur relative, pour le métier (si y ≠ 0) |
| **R²** | aucune | oui (même calcul que la RMSE) | qualité globale, comparaison avec la moyenne |

## Dans scikit-learn

Les scores sont toujours **maximisés** : les erreurs sont donc renvoyées **en négatif**.

| Métrique | Fonction (`sklearn.metrics`) | Nom de `scoring` (CV, GridSearch) |
|---|---|---|
| MAE | `mean_absolute_error` | `"neg_mean_absolute_error"` |
| RMSE | `root_mean_squared_error` | `"neg_root_mean_squared_error"` |
| MAPE | `mean_absolute_percentage_error` (renvoie une fraction, ×100 pour des %) | `"neg_mean_absolute_percentage_error"` |
| R² | `r2_score` | `"r2"` |

```python
from sklearn.metrics import (
    mean_absolute_error, mean_absolute_percentage_error, r2_score, root_mean_squared_error,
)

print(f"MAE  : {mean_absolute_error(y_test, y_pred):,.0f}")
print(f"RMSE : {root_mean_squared_error(y_test, y_pred):,.0f}")
print(f"MAPE : {mean_absolute_percentage_error(y_test, y_pred) * 100:.1f} %")
print(f"R²   : {r2_score(y_test, y_pred):.3f}")
```

> Choisir la métrique **avec le métier** : le « meilleur » modèle peut changer selon la
> métrique (cf. notebook : passer en `log(prix)` améliore la MAPE mais dégrade la RMSE).

---

## Bonus — Métriques de classification

Tout part de la **matrice de confusion** (classe positive = ce qu'on cherche à détecter, ex. la fraude) :

|  | prédit positif | prédit négatif |
|---|---|---|
| **réel positif** | VP (vrai positif) | FN (faux négatif, raté) |
| **réel négatif** | FP (faux positif, fausse alerte) | VN (vrai négatif) |

| Métrique | Formule | Question posée | Quand l'utiliser |
|---|---|---|---|
| **Accuracy** | $\frac{VP + VN}{\text{total}}$ | quelle part de bonnes réponses ? | classes équilibrées seulement ⚠️ |
| **Précision** | $\frac{VP}{VP + FP}$ | parmi les alertes, combien sont justes ? | fausses alertes coûteuses |
| **Rappel** (recall, sensibilité) | $\frac{VP}{VP + FN}$ | parmi les vrais positifs, combien sont détectés ? | cas ratés coûteux (fraude, maladie) |
| **F1-score** | $2 \cdot \frac{P \cdot R}{P + R}$ | compromis précision / rappel | classes déséquilibrées, un seul chiffre |
| **ROC-AUC** | aire sous la courbe ROC (taux VP vs taux FP) | le modèle classe-t-il les positifs au-dessus des négatifs ? | comparer des modèles, indépendamment du seuil |
| **PR-AUC** (average precision) | aire sous la courbe précision-rappel | idem, centré sur la classe positive | **classes très déséquilibrées** (cf. `train.py`, fraude) |

À retenir :
- **Piège de l'accuracy** : avec 2 % de fraudes, prédire « jamais fraude » donne 98 % d'accuracy
  pour un modèle inutile → regarder rappel, précision, F1, PR-AUC.
- **Précision et rappel s'opposent** : baisser le seuil de décision (par défaut 0,5) détecte plus
  de positifs (rappel ↑) mais crée plus de fausses alertes (précision ↓). Le seuil se choisit
  avec le métier selon le coût d'un FN vs d'un FP.
- La ROC-AUC (0,5 = hasard, 1 = parfait) reste optimiste quand les positifs sont rares ;
  la PR-AUC est alors plus parlante (sa valeur « hasard » = proportion de positifs).

```python
from sklearn.metrics import (
    average_precision_score, classification_report, confusion_matrix, f1_score, roc_auc_score,
)

print(confusion_matrix(y_test, y_pred))
print(classification_report(y_test, y_pred))           # précision, rappel, F1 par classe
y_proba = model.predict_proba(X_test)[:, 1]             # probabilité de la classe positive
print(f"ROC-AUC : {roc_auc_score(y_test, y_proba):.3f}")
print(f"PR-AUC  : {average_precision_score(y_test, y_proba):.3f}")
```

Noms de `scoring` : `"accuracy"`, `"precision"`, `"recall"`, `"f1"`, `"roc_auc"`, `"average_precision"`
(et `"f1_macro"`, `"f1_weighted"` en multi-classe).
