# Guide : se connecter à une machine distante en SSH (terminal + VS Code)

## 1. Prérequis

| Côté | Ce qu'il faut |
|------|---------------|
| **Machine locale** (Windows) | Client OpenSSH (inclus dans Windows 10/11) → tester avec `ssh -V` |
| **Machine distante** (Linux) | Serveur OpenSSH installé et démarré, port 22 ouvert |
| **Infos à connaître** | IP ou nom d'hôte, nom d'utilisateur, (mot de passe ou clé) |

Sur la machine distante (Debian/Ubuntu), si le serveur SSH n'est pas installé :

```bash
sudo apt update && sudo apt install -y openssh-server
sudo systemctl enable --now ssh
sudo systemctl status ssh
```

Si un pare-feu est actif :

```bash
sudo ufw allow ssh
```

---

## 2. Première connexion (mot de passe)

```bash
ssh utilisateur@192.168.1.50
```

- Port différent de 22 : `ssh -p 2222 utilisateur@192.168.1.50`
- À la première connexion, taper `yes` pour accepter l'empreinte du serveur (stockée dans `~/.ssh/known_hosts`).
- Quitter : `exit` ou `Ctrl+D`.

---

## 3. Authentification par clé (recommandé)

### 3.1 Générer une paire de clés (en local)

```bash
ssh-keygen -t ed25519 -C "mon_pc"
```

Cela crée :
- `~/.ssh/id_ed25519` → **clé privée** (ne jamais la partager)
- `~/.ssh/id_ed25519.pub` → **clé publique** (à copier sur le serveur)

> Sous Windows, `~` = `C:\Users\<toi>\`

### 3.2 Copier la clé publique sur le serveur

**Linux / macOS / Git Bash :**

```bash
ssh-copy-id utilisateur@192.168.1.50
```

**PowerShell (pas de `ssh-copy-id`) :**

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh utilisateur@192.168.1.50 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

### 3.3 Tester

```bash
ssh utilisateur@192.168.1.50
```

→ Plus de mot de passe demandé (sauf la passphrase de la clé si tu en as mis une).

---

## 4. Fichier de config SSH (alias)

Créer / éditer `~/.ssh/config` (Windows : `C:\Users\<toi>\.ssh\config`, **sans extension**) :

```
Host monserveur
    HostName 192.168.1.50
    User utilisateur
    Port 22
    IdentityFile ~/.ssh/id_ed25519
```

Ensuite il suffit de :

```bash
ssh monserveur
```

Ce même fichier est utilisé par VS Code 👇

---

## 5. VS Code en SSH (Remote - SSH)

### 5.1 Installer l'extension

1. Ouvrir VS Code → onglet **Extensions** (`Ctrl+Shift+X`)
2. Installer **Remote - SSH** (éditeur : Microsoft, id `ms-vscode-remote.remote-ssh`)

### 5.2 Se connecter

1. `F1` (ou `Ctrl+Shift+P`) → **Remote-SSH: Connect to Host...**
2. Choisir `monserveur` (lu depuis `~/.ssh/config`) ou taper `utilisateur@192.168.1.50`
3. Choisir la plateforme distante : **Linux**
4. VS Code installe automatiquement son serveur (`~/.vscode-server`) sur la machine distante
5. **File > Open Folder** → ouvrir un dossier de la machine distante

Le coin inférieur gauche affiche `SSH: monserveur` quand on est connecté.

> Raccourci : cliquer sur l'icône verte `><` en bas à gauche → *Connect to Host...*

### 5.3 Bon à savoir

- Le **terminal intégré** (`Ctrl+ù`) s'ouvre directement sur la machine distante.
- Les **extensions** (Python, Jupyter...) doivent être installées *côté distant* : bouton **Install in SSH: monserveur** dans l'onglet Extensions.
- **Port forwarding** : onglet **Ports** (à côté du terminal) → *Forward a Port* (ex. 8888 pour Jupyter, 8000 pour une API) → accessible en local sur `http://localhost:8888`.
- Se déconnecter : icône `><` en bas à gauche → **Close Remote Connection**.

---

## 6. Commandes utiles

```bash
# Copier un fichier local -> distant
scp fichier.txt monserveur:/home/utilisateur/

# Copier un dossier distant -> local
scp -r monserveur:/home/utilisateur/projet ./

# Exécuter une commande sans ouvrir de session
ssh monserveur "df -h"

# Tunnel : port distant 8888 accessible en local sur 8888
ssh -L 8888:localhost:8888 monserveur
```

---

## 7. Dépannage rapide

| Problème | Piste |
|----------|-------|
| `Connection refused` | Serveur SSH pas démarré (`sudo systemctl status ssh`) ou mauvais port |
| `Connection timed out` | IP incorrecte, machine éteinte, pare-feu / réseau |
| `Permission denied (publickey)` | Clé pas dans `authorized_keys`, mauvais `User`, droits trop ouverts (`chmod 700 ~/.ssh`, `chmod 600 ~/.ssh/authorized_keys`) |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | Serveur réinstallé → `ssh-keygen -R 192.168.1.50` puis se reconnecter |
| Windows : `Bad permissions` sur la clé privée | Le fichier `id_ed25519` ne doit être lisible que par ton utilisateur (Propriétés > Sécurité) |
| VS Code bloqué sur « Setting up SSH host » | `F1` → **Remote-SSH: Kill VS Code Server on Host...** puis reconnecter ; voir les logs : **Remote-SSH: Show Log** |
| Debug détaillé | `ssh -v monserveur` (ou `-vvv`) |

---

## 8. Sécurisation (optionnel, une fois la clé fonctionnelle)

Dans `/etc/ssh/sshd_config` sur le serveur :

```
PasswordAuthentication no
PermitRootLogin no
```

Puis :

```bash
sudo systemctl restart ssh
```

> ⚠️ Vérifier que la connexion par clé fonctionne **avant** de désactiver les mots de passe, en gardant une session ouverte pendant le test.
