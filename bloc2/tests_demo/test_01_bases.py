import pytest

from boutique import prix_ttc


def test_prix_ttc_taux_par_defaut():
    # Arrange : préparer les données
    prix_ht = 100
    # Act : appeler le code testé
    resultat = prix_ttc(prix_ht)
    # Assert : vérifier
    assert resultat == 120


def test_prix_ttc_taux_reduit():
    assert prix_ttc(100, taux=0.055) == 105.5


def test_flottants_avec_approx():
    # 0.1 + 0.2 == 0.30000000000000004 : on compare avec une tolérance
    assert 0.1 + 0.2 == pytest.approx(0.3)


def test_prix_negatif_leve_une_erreur():
    # On vérifie qu'une exception EST levée (et son message, via une regex)
    with pytest.raises(ValueError, match="positif"):
        prix_ttc(-5)
