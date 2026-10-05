# Scénario : Détection d'un scan de vulnérabilités Web

Ce scénario montre comment détecter, avec Snort, le passage de **Nikto** lors d'un audit autorisé du serveur Web Apache. Les alertes sont ensuite consultables dans Kibana.

> **Portée de la détection :** la règle proposée repère la chaîne `Nikto` dans le trafic TCP à destination du port 80. Elle signale les requêtes qui contiennent cette chaîne ; elle ne prouve pas à elle seule qu'une vulnérabilité existe et peut être contournée si l'outil masque son nom.

## 1. Principe du scan

Nikto envoie des requêtes HTTP pour rechercher notamment des fichiers, des chemins et des configurations Web potentiellement risqués. Dans ce laboratoire, la VM Kali est la machine de test et le serveur Apache de la VM Ubuntu est la cible (`192.168.56.101`).

Le trafic HTTP du scan peut également apparaître dans les journaux d'accès Apache. Snort observe les paquets et génère une alerte lorsque le contenu inspecté contient la chaîne `Nikto`.

## 2. Règle de détection (Snort)

Sur la VM Ubuntu, ajoutez la règle suivante à `/etc/snort/rules/local.rules` :

```text
alert tcp any any -> any 80 (msg:"SCAN WEB Nikto"; content:"Nikto"; nocase; sid:1000005; rev:1;)
```

### Explication de la règle

- **`alert tcp`** : demande à Snort de générer une alerte pour le trafic TCP correspondant.
- **`any any -> any 80`** : surveille les paquets TCP à destination du port HTTP 80.
- **`content:"Nikto"; nocase`** : recherche le texte `Nikto`, sans distinction de casse, dans le contenu inspecté par Snort.
- **`sid:1000005`** : identifiant unique de cette règle locale dans la configuration du laboratoire.
- **`rev:1`** : première révision de la règle.

Après avoir enregistré le fichier, vérifiez sa syntaxe puis redémarrez Snort sur Ubuntu :

```bash
sudo snort -T -c /etc/snort/snort.conf
sudo systemctl restart snort
sudo systemctl status snort
```

La validation de configuration doit se terminer sans erreur avant de poursuivre.

## 3. Reproduire le scan depuis Kali

Effectuez ce test uniquement sur les machines du laboratoire ou sur un serveur pour lequel vous avez une autorisation explicite.

### 3.1 Lancer Nikto

Vérifiez d'abord que le serveur Web est disponible depuis Kali :

```bash
curl -I http://192.168.56.101
```

Lancez ensuite le scan Nikto contre le serveur Ubuntu :

```bash
nikto -h http://192.168.56.101
```

La capture montre la commande exécutée depuis Kali et les résultats obtenus par Nikto.

![Exécution du scan Nikto et résultats dans Kali](./Image/Attaque_Nikto.png)

Nikto peut signaler des configurations ou des en-têtes à vérifier. Ses résultats doivent être examinés ; ils ne prouvent pas à eux seuls qu'une faille est exploitable.

### 3.2 Vérifier les alertes Snort sur Ubuntu

Pendant le test, suivez les alertes Snort sur Ubuntu dans un autre terminal :

```bash
sudo tail -f /var/log/snort/snort.alert.fast
```

La capture ci-dessous montre les alertes Snort associées au trafic HTTP de Nikto.

![Alertes Snort dans le terminal Ubuntu](./Image/Alerte_Snort.png)

## 4. Visualiser les alertes dans Kibana

1. Ouvrez Kibana à l'adresse `http://192.168.56.101:5601`.
2. Dans **Analytics → Discover**, sélectionnez la Data View `logs-securite-*`.
3. Choisissez une période qui couvre l'exécution du scan, par exemple **Last 15 minutes**, puis actualisez les résultats.
4. Recherchez `SCAN WEB Nikto` ou `Nikto`.

La capture illustre les alertes reçues dans Kibana.

![Alertes du scan Web dans Kibana](./Image/Kibana_allert_VulnerabiliteWeb.png)

Le champ `message` doit contenir le texte `SCAN WEB Nikto`. L'horodatage permet de rapprocher les alertes de l'exécution du scan.

## 5. Limites et améliorations

- **Détection dépendante de la signature :** la règle dépend de la présence de `Nikto` dans le trafic inspecté. Si l'outil masque ou modifie cette chaîne, Snort peut ne pas déclencher cette règle ; d'autres scanners ne seront pas nécessairement reconnus.
- **Faux positifs possibles :** toute requête vers le port 80 contenant le texte `Nikto` peut déclencher une alerte.
- **Alerte distincte d'une vulnérabilité :** la signature indique un trafic correspondant à la règle, pas la présence ni l'exploitation réussie d'une faille.
- **Amélioration possible :** corréler les alertes Snort avec les journaux d'accès et d'erreur Apache, puis vérifier séparément les constats de Nikto et les configurations concernées.