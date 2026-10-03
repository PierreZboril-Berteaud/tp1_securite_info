# Guide d'exécution : Simulation de Force Brute SSH

Ce document explique comment préparer l'environnement et simuler une attaque brute force afin de tester le déclenchement de la règle Snort.

## 1. Prérequis et Installation des dictionnaires
* La machine cible (Ubuntu) possède un service SSH actif sur l'IP `192.168.56.101`.
* La machine de test (Kali Linux) utilise l'outil d'authentification automatisée `hydra`.

Pour réaliser l'attaque, nous avons besoin de dictionnaires. Sur Kali Linux, exécutez les commandes suivantes pour installer les listes (SecLists et Wordlists) et les placer dans le bon dossier de notre projet :


### 1.1 Mettre à jour la liste des paquets et installer les dictionnaires

```sudo apt update```

```sudo apt install -y seclists wordlists```

### 1.2 Décompresser le fichier de mots de passe rockyou

```sudo gzip -d /usr/share/wordlists/rockyou.txt.gz```

### 1.3 Créer le dossier txt dans notre arborescence

```mkdir -p BRUTEFORCE_SSH/script/txt```

### 1.4 Copier rockyou.txt et une liste d'utilisateurs vers notre dossier de travail
```cp /usr/share/wordlists/rockyou.txt BRUTEFORCE_SSH/script/txt/```

```cp /usr/share/seclists/Usernames/top-usernames-shortlist.txt BRUTEFORCE_SSH/script/txt/users.txt```

### 1.5 Tests avec une plus petite base de données username/mot de passes

Pour effectuer un test avec peu de combinaisons username/mot de passe il faut utiliser les fichiers 

```small_password.txt```

```small_username.txt```


## 2. Déclenchement de l'alerte
1. Sur la VM Ubuntu (cible), assurez-vous que l'IDS est actif avec la dernière configuration :

   ```sudo systemctl restart snort```

2. Sur la VM Kali, placez-vous dans le dossier `BRUTEFORCE_SSH/script/` et exécutez le script d'automatisation :

   ```chmod +x bruteforce_ssh.sh```

   ```./bruteforce_ssh.sh```
3. Laissez l'outil tourner pendant une dizaine de secondes pour générer au moins 3 connexions (le seuil de notre règle), puis arrêtez-le avec `Ctrl+C`.

## 3. Vérification des résultats
1. Rendez-vous sur l'interface Kibana (`http://192.168.56.101:5601`).
2. Ouvrez l'onglet **Discover**.
3. Sélectionnez votre Data View (`logs-securite-*`).
4. Dans la barre de recherche, filtrez avec le message exact `SSH Brute-Force attaque` ou le numéro de règle `1000281`.
5. Vous devriez observer l'apparition des alertes correspondantes aux tentatives de connexion massives interceptées par Snort.