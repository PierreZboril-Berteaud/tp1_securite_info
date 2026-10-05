# Scénario : détection d'injections SQL

Ce scénario montre comment détecter en temps réel des tentatives d'injection SQL contre un serveur web, avec Snort, syslog-ng, Elasticsearch et Kibana.

```
Kali (attaquant) → Apache (VM1) → Snort (détecte) → syslog-ng (collecte) → Elasticsearch → Kibana
```

## 1. Le scénario

### C'est quoi une injection SQL ?

Un site web construit souvent ses requêtes SQL en collant ce que l'utilisateur envoie. Par exemple :

```sql
SELECT * FROM produits WHERE id = <valeur de l'URL>
```

Si l'attaquant envoie `1 OR 1=1`, la requête devient `WHERE id = 1 OR 1=1`, qui est toujours vraie et renvoie toute la table. Il a injecté du code SQL là où le site attendait une simple valeur. Selon le cas, cela permet de voler des données, de contourner une authentification ou de modifier la base (OWASP Top 10, A03 : Injection).

### Pourquoi ce scénario ?

C'est l'une des attaques web les plus courantes et l'une des plus graves. Elle laisse des traces claires à deux endroits : la requête dans les logs Apache, et un motif reconnaissable sur le réseau pour Snort. C'est idéal pour montrer l'intérêt de croiser plusieurs sources de logs.

### Ce que nous avons mis en place

- Une page cible `produits.php` qui affiche le paramètre `id` reçu.
- 6 règles Snort, une par technique d'injection.
- 6 attaques lancées depuis Kali.
- Les alertes remontent jusqu'à Kibana via syslog-ng et Elasticsearch.

> **Remarque.** La page cible n'a pas de base de données derrière. Les attaques n'aboutissent donc pas (sqlmap conclut « not injectable »). Ce n'est pas gênant : le projet évalue la **détection de la tentative**, et Snort analyse le trafic, pas le résultat de l'attaque.

## 2. Les règles Snort

Fichier : [`CONF/snort/sql_injection.rules`](../../CONF/snort/sql_injection.rules)

| SID | Technique | Ce que la règle cherche | Exemple d'attaque |
|---|---|---|---|
| 1000011 | UNION SELECT | `union` suivi de `select` dans l'URI | `1 UNION SELECT null,null--` |
| 1000012 | Tautologie | une quote suivie de `OR`/`AND` et d'une égalité numérique | `1' OR 1=1--` |
| 1000013 | Commentaire SQL | une quote suivie de `--` ou `#` | `admin'--` |
| 1000014 | Time-based (blind) | `sleep(`, `benchmark(`, `waitfor delay` | `1 AND SLEEP(5)--` |
| 1000015 | Reconnaissance du schéma | `information_schema` dans l'URI | `... FROM information_schema.tables` |
| 1000016 | Outil automatisé | `sqlmap` dans le User-Agent | `sqlmap -u ...` |

Les règles 1000011 à 1000013 utilisent une expression régulière qui accepte aussi la forme encodée de l'URL (`%27` pour `'`, `%23` pour `#`).

## 3. Reproduire le scénario

Prérequis : l'infrastructure décrite dans `INSTALLATION.md` (Snort, syslog-ng, Elasticsearch, Kibana sur la VM Ubuntu `192.168.56.101`, Kali en `192.168.56.102`).

### Sur la VM Ubuntu

**1. Créer la page cible** (fichier : [`script/produits.php`](script/produits.php))

```bash
sudo cp script/produits.php /var/www/html/produits.php
curl "http://127.0.0.1/produits.php?id=1"      # doit afficher : Produit : 1
```

**2. Ajouter les règles Snort**

```bash
sudo cp /etc/snort/rules/local.rules /etc/snort/rules/local.rules.bak
cat CONF/snort/sql_injection.rules | sudo tee -a /etc/snort/rules/local.rules
sudo snort -T -c /etc/snort/snort.conf -i enp0s8 2>&1 | tail -3
```

Il faut voir `Snort successfully validated the configuration!`.

**3. Appliquer l'option `-k none` au service Snort**

C'est le piège principal de ce scénario. Sur VirtualBox, les checksums TCP sont souvent invalides à cause de l'offloading de la carte virtuelle, et Snort ignore alors les paquets. Les règles semblent correctes, mais aucune alerte n'apparaît.

```bash
sudo nano /etc/snort/snort.debian.conf
# remplacer par :
DEBIAN_SNORT_OPTIONS="-k none"

sudo systemctl restart snort
ps aux | grep [s]nort        # vérifier que "-k none" apparaît
```

**4. Suivre les alertes en direct**

```bash
sudo tail -f /var/log/snort/snort.alert.fast
```

### Sur Kali

Lancer le script (6 attaques, 2 secondes entre chaque) :

```bash
chmod +x script/attaques_sqli.sh
./script/attaques_sqli.sh 192.168.56.101
```

### Vérifier la chaîne complète

```bash
# Combien d'alertes Snort ?
sudo grep -a -c "SQLI" /var/log/snort/snort.alert.fast

# Combien par règle ?
sudo grep -a -o "SQLI[^[]*" /var/log/snort/snort.alert.fast | sort | uniq -c | sort -rn

# Arrivent-elles dans Elasticsearch ?
curl -s "http://127.0.0.1:9200/logs-securite-*/_count?q=message:SQLI&pretty"
```

## 4. Résultats et lecture des captures

### Résultats

| Étape | Résultat |
|---|---|
| Alertes dans `snort.alert.fast` | 583 |
| Lignes dans `syslog-ng-central.log` | 586 |
| Documents dans Kibana (`message : *SQLI*`) | 588 |

Les 6 règles ont déclenché au moins une alerte. sqlmap seul a généré environ 500 alertes en 6 secondes.

### Comment prouver que c'est bien une injection SQL

Une seule source ne suffit pas, c'est le croisement de trois éléments qui fait la preuve :

1. **La requête dans le log Apache** : du SQL dans un paramètre HTTP (`/produits.php?id=1%20UNION%20SELECT...`). Dans l'URL, `%20` est un espace, `%27` une quote et `%3D` un signe égal.
2. **L'alerte Snort** : par exemple `[1:1000010:1] SQLI UNION SELECT detecte [Classification: Web Application Attack] [Priority: 1]`.
3. **La corrélation dans Kibana** : même IP source (`192.168.56.104`), mêmes horaires, deux sources différentes (champ `program`).

### Captures

**Mise en place**

| Capture | Ce qu'elle montre |
|---|---|
| ![](images/01_page_cible_produits_php.png) | La page cible répond `Produit : 1`. |
| ![](images/02_regles_snort_local_rules.png) | Les 6 règles dans `local.rules`. |
| ![](images/03_validation_snort.png) | Snort valide la configuration. |

**Les attaques depuis Kali**

| Capture | Ce qu'elle montre |
|---|---|
| ![](images/04_attaques_kali.png) | simulations d'injections depuis kali |

**Les preuves côté serveur**

| Capture | Comment la lire |
|---|---|
| ![](images/05_alertes_snort.png) | Une ligne par alerte : horodatage, SID, message, classification, priorité, puis IP source → IP destination:port. |
| ![](images/06_logs_apache.png) | La requête brute telle que le serveur l'a reçue, avec l'IP de l'attaquant et le User-Agent. |

**Kibana**

| Capture | Comment la lire |
|---|---|
| ![](images/07_kibana_discover_SQLI.png) | Recherche `message : *SQLI* and not program : "sudo"`. L'histogramme montre le pic au moment de l'attaque. Les colonnes `host`, `program` et `message` identifient la source de chaque ligne. |
| ![](images/08_kibana_apache_snort.png) | Recherche `message : *produits.php* or message : *SQLI*`. On voit la requête Apache et l'alerte Snort correspondante côte à côte. |
| ![](images/09_kibana_visualisation.png) | Nombre d'alertes par technique. Les barres montrent quelles règles se déclenchent le plus. sqlmap domine parce qu'il teste des centaines de variantes. |

### Comment prouver que ça marche

Trois temps :

1. **Avant** : on note le nombre d'alertes `SQLI` existantes.
2. **Pendant** : on lance une attaque depuis Kali, commande visible.
3. **Après** : l'alerte apparaît dans `snort.alert.fast`, puis dans Kibana quelques secondes plus tard.

**Test de contrôle.** Une requête légitime (`curl "http://192.168.56.101/produits.php?id=1"`) ne doit déclencher aucune alerte. Cela montre que les règles ne se déclenchent pas sur n'importe quel trafic.

![](images/10_test_requete_sans_alerte.png)

## 5. Limites et améliorations

### Limites

- **Contournement par obfuscation** : casse mixte, commentaires `/**/` à la place des espaces, double encodage. Nos règles peuvent les rater.
- **HTTPS** : en trafic chiffré, Snort ne voit pas l'URL et ne détecte rien. Il faudrait placer la détection derrière la terminaison TLS.
- **Faux positifs** : un texte qui contiendrait « union » puis « select » dans une URL légitime déclencherait la règle 1000010.
- **Volume** : sqlmap produit environ 500 alertes en quelques secondes. Sans regroupement, un administrateur est noyé sous les doublons.
- **Pas de base de données** : on valide la détection, pas l'exploitation réelle.

### Améliorations possibles

- Regrouper les alertes avec `detection_filter` ou `event_filter` dans Snort.
- Placer ModSecurity ou un autre WAF devant Apache pour bloquer, pas seulement détecter.
- Ajouter Suricata en complément pour comparer la détection.
- Remplacer la page cible par DVWA ou une vraie base MySQL pour une démonstration de bout en bout.

### Perspectives

- Passer de Snort à Snort 3 ou Suricata, dont les règles HTTP sont plus riches.
- Corréler avec Wazuh pour enrichir la collecte (logs applicatifs, intégrité des fichiers).
- Explorer la détection d'anomalies par apprentissage automatique pour repérer les variantes non couvertes par les signatures.
