# Scénario : Détection d'une attaque Brute Force SSH

Ce scénario illustre la capacité de notre infrastructure de sécurité à détecter des tentatives répétées et massives d'authentification sur le service SSH (port 22), caractéristiques d'une attaque brute force utilisant des dictionnaires de mots de passe (seclists wordlists).

## 1. Théorie : L'attaque brute force
Une attaque brute force consiste à tester de manière automatisée une grande quantité de combinaisons de noms d'utilisateurs et de mots de passe jusqu'à trouver la bonne. Au niveau réseau, cela se traduit par un nombre anormalement élevé de nouvelles connexions TCP vers le port du service ciblé en un laps de temps très court.

## 2. Règle de détection (Snort)
Pour détecter ce comportement, nous surveillons la fréquence d'ouverture de session vers le port 22 à l'aide de l'option `threshold`.

**Fichier modifié :** `/etc/snort/rules/local.rules`
**Règle ajoutée :**

```
alert tcp any any -> $HOME_NET 22 (msg:"SSH Brute-Force attaque"; threshold: type both, track by_src, count 3, seconds 60; classtype:misc-attack; sid:1000281; rev:2;)
```

*Explication de la règle : L'alerte est déclenchée si une même adresse IP source initie 3 connexions vers le port 22 de notre réseau interne en l'espace de 60 secondes. Le paramètre `threshold: type both` permet de limiter le nombre d'alertes générées par Snort pour éviter de saturer les logs (1 alerte toutes les 60 secondes par IP).*

## 3. Visualisation et Analyse dans Kibana

![Capture d'écran Kibana des alertes Snort](./images/brute_force.png)
![Capture d'écran Kibana des alertes Snort](./images/brute_force2.png)

### Comment lire cette capture ?
* **Timestamp :** L'horodatage montre l'apparition de l'alerte `SSH Brute-Force attaque` suite au lancement de notre outil automatisé.

* **Confirmation de l'attaque :** L'alerte de Snort nous prévient qu'il y a un trafic réseau anormal. L'avantage de notre projet, c'est qu'on peut croiser cette information avec les journaux du serveur cible. En regardant le fichier **/var/log/auth.log**, on verrait un grand nombre d'erreurs Failed password, ce qui prouve bien que quelqu'un essaie de brute force nos mots de passe.

## 4. Limites et Améliorations (Analyse)
* **Limite actuelle :** Cette règle réseau se base uniquement sur le volume de connexions (3 en 60 secondes). Elle peut générer de faux positifs si un administrateur légitime se trompe plusieurs fois de mot de passe rapidement, ou à l'inverse, manquer une attaque très lente (une tentative toutes les 5 minutes). De plus, l'IDS ne sait pas si l'attaque a finalement réussi ou échoué.
* **Amélioration possible (Veille) :** Pour sécuriser efficacement le service SSH, la détection réseau doit être complétée par une détection système. L'utilisation d'outils comme **Fail2Ban** permet d'analyser les logs d'authentification réels et de bannir l'IP source au niveau du pare-feu après X échecs consécutifs. La désactivation de l'authentification par mot de passe au profit des clés SSH est également la norme en production.