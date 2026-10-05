# Installation pas à pas

Système de détection d'intrusions (Snort) couplé à une centralisation de logs (syslog-ng → Elasticsearch → Kibana), déployé sur une VM Ubuntu Server et testé depuis une VM Kali Linux.

## Sommaire

- [Architecture](#architecture)
- [Prérequis](#prérequis)
- [1. Configuration réseau](#1-configuration-réseau)
- [2. Services de base](#2-services-de-base)
- [3. Snort (IDS)](#3-snort-ids)
- [4. syslog-ng](#4-syslog-ng)
- [5. Elasticsearch](#5-elasticsearch)
- [6. Kibana](#6-kibana)
- [7. Liaison syslog-ng → Elasticsearch](#7-liaison-syslog-ng--elasticsearch)
- [8. Afficher les logs dans Kibana](#8-afficher-les-logs-dans-kibana)
- [9. Vérification de bout en bout](#9-vérification-de-bout-en-bout)
- [Dépannage](#dépannage)

## Architecture

Pour limiter les ressources, les rôles « serveur » et « ELK » sont regroupés sur une seule VM. En production, on les séparerait.

| VM | Rôle | OS |
|---|---|---|
| VM1 : Serveur + ELK | Apache, SSH, Snort, syslog-ng, Elasticsearch, Kibana | Ubuntu Server 22.04 / 24.04 LTS |
| VM2 : Attaquant | nmap, hydra, nikto, hping3, sqlmap | Kali Linux |

```
Apache / SSH / Snort  →  syslog-ng  →  Elasticsearch (9200)  →  Kibana (5601)
     (génération)         (collecte)        (stockage)           (visualisation)
```

## Prérequis

- VirtualBox avec deux VM : Ubuntu Server et Kali Linux.
- Deux cartes réseau par VM :
  - **Adaptateur 1, NAT** : accès Internet (`apt`).
  - **Adaptateur 2, réseau privé hôte (vboxnet0)** : communication entre les VM sur `192.168.56.0/24`.
- Pour Elasticsearch : au moins 4 Go de RAM pour la VM Ubuntu.

## 1. Configuration réseau

| Machine | Interface | Adresse IP |
|---|---|---|
| VM1 Ubuntu | `enp0s3` (NAT) | DHCP |
| VM1 Ubuntu | `enp0s8` (host-only) | 192.168.56.101/24 |
| VM2 Kali | host-only | 192.168.56.102/24 (via `nmcli`) |

> Les adresses réelles peuvent varier. Dans nos tests, Kali apparaissait en `192.168.56.104` (attribuée par DHCP). Vérifier avec `ip a` et adapter.

Fichier `/etc/netplan/50-cloud-init.yaml` sur la VM Ubuntu (indentation en espaces, jamais de tabulation) :

```yaml
network:
  ethernets:
    enp0s3:
      dhcp4: true
    enp0s8:
      dhcp4: false
      addresses:
        - 192.168.56.101/24
  version: 2
```

```bash
sudo netplan apply
ip a                         # enp0s8 doit être UP avec 192.168.56.101
```

Test depuis Kali :

```bash
ping -c 4 192.168.56.101
```

## 2. Services de base

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y apache2 php libapache2-mod-php openssh-server
sudo systemctl status apache2 ssh      # les deux doivent être « active »
```

## 3. Snort (IDS)

### 3.1 Installation

```bash
sudo apt install -y snort
```

Pendant l'installation, indiquer l'interface `enp0s8` et le réseau `192.168.56.0/24`. Pour corriger après coup, éditer `/etc/snort/snort.debian.conf` :

```
DEBIAN_SNORT_INTERFACE="enp0s8"
DEBIAN_SNORT_HOME_NET="192.168.56.0/24"
DEBIAN_SNORT_OPTIONS="-k none"
```

> **Important : l'option `-k none`.** Sur VirtualBox, les checksums TCP sont souvent invalides à cause de l'offloading de la carte virtuelle. Sans cette option, Snort ignore ces paquets : les règles sont correctes, mais le service n'émet aucune alerte (alors qu'un lancement manuel avec `-k none` fonctionne).

### 3.2 Règle de test ICMP

Dans `/etc/snort/rules/local.rules` :

```
alert icmp any any -> $HOME_NET any (msg:"TEST ICMP Ping detecte"; sid:1000001; rev:1;)
```

Vérifier que `snort.conf` charge bien ce fichier :

```bash
grep -n "local.rules" /etc/snort/snort.conf     # include $RULE_PATH/local.rules non commenté
```

### 3.3 Validation et démarrage

```bash
sudo snort -T -c /etc/snort/snort.conf -i enp0s8 2>&1 | tail -3
# attendu : Snort successfully validated the configuration!

sudo systemctl restart snort
ps aux | grep [s]nort                           # "-k none" doit apparaître
sudo tail -f /var/log/snort/snort.alert.fast
```

Snort écrit ses alertes dans `/var/log/snort/snort.alert.fast` (et non `alert`).

Depuis Kali, `ping -c 4 192.168.56.101` doit faire apparaître « TEST ICMP Ping detecte » (sid 1000001).

### 3.4 Règles des scénarios

Les règles de chaque scénario sont dans le dossier `CONF/snort/`. Pour les ajouter :

```bash
sudo cp /etc/snort/rules/local.rules /etc/snort/rules/local.rules.bak
cat CONF/snort/sql_injection.rules | sudo tee -a /etc/snort/rules/local.rules
sudo snort -T -c /etc/snort/snort.conf -i enp0s8 2>&1 | tail -3
sudo systemctl restart snort
```

Chaque règle doit tenir sur une seule ligne, sinon Snort refuse de démarrer.

## 4. syslog-ng

### 4.1 Installation

```bash
sudo apt install -y syslog-ng
```

### 4.2 Structure du fichier

`/etc/syslog-ng/syslog-ng.conf` se compose de quatre types de blocs :

- **source** : d'où viennent les logs (fichiers, réseau).
- **filter** (facultatif) : trie ou isole certains événements.
- **destination** : où envoyer les logs.
- **log** : relie sources, filtres et destinations.

### 4.3 Configuration Apache, Snort, SSH

`s_src` est la source système par défaut d'Ubuntu : elle inclut déjà `/var/log/auth.log` (donc SSH). Ajouter à la fin du fichier :

```
# --- Sources ---
source s_apache {
    file("/var/log/apache2/access.log" program-override("apache2"));
    file("/var/log/apache2/error.log"  program-override("apache2"));
};

source s_snort {
    file("/var/log/snort/snort.alert.fast" flags(no-parse) program-override("snort"));
};

# --- Destination locale (test / débogage) ---
destination d_local_central {
    file("/var/log/syslog-ng-central.log");
};

# --- Liaison ---
log {
    source(s_apache);
    source(s_snort);
    source(s_src);
    destination(d_local_central);
};
```

L'option `program-override` renseigne le champ `program`, ce qui permet ensuite de distinguer Apache de Snort dans Kibana.

### 4.4 Vérification

```bash
sudo syslog-ng -s                       # vérifie la syntaxe
sudo systemctl restart syslog-ng
sudo systemctl status syslog-ng
sudo tail -f /var/log/syslog-ng-central.log
```

## 5. Elasticsearch

### 5.1 Dépôt officiel

```bash
sudo apt install -y apt-transport-https curl gnupg

curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --yes --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

sudo apt update
```

### 5.2 Installation

```bash
sudo apt install -y elasticsearch
```

### 5.3 Désactiver la sécurité (laboratoire uniquement)

Dans `/etc/elasticsearch/elasticsearch.yml`, mettre :

```yaml
xpack.security.enabled: false
```

> À ne jamais faire en production : l'API est alors accessible sans authentification ni chiffrement.

### 5.4 Démarrage et test

```bash
sudo systemctl enable --now elasticsearch
sudo systemctl status elasticsearch
curl -X GET "http://127.0.0.1:9200"     # doit renvoyer un JSON
```

Le démarrage peut prendre une à deux minutes.

## 6. Kibana

```bash
sudo apt install -y kibana
sudo nano /etc/kibana/kibana.yml
```

Décommenter ou modifier :

```yaml
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://127.0.0.1:9200"]
```

```bash
sudo systemctl enable --now kibana
sudo systemctl status kibana
sudo ss -tulpn | grep 5601
```

La VM Ubuntu n'a pas d'interface graphique : ouvrir Kibana depuis Kali ou la machine hôte (le premier démarrage est lent) :

```
http://192.168.56.101:5601
```

## 7. Liaison syslog-ng → Elasticsearch

Ajouter à `/etc/syslog-ng/syslog-ng.conf` :

```
destination d_elastic {
    http(
        url("http://127.0.0.1:9200/_bulk")
        method("POST")
        headers("Content-Type: application/x-ndjson")
        body("{\"create\": {\"_index\": \"logs-securite-${YEAR}.${MONTH}.${DAY}\"} }\n{\"@timestamp\": \"${ISODATE}\", \"host\": \"${HOST}\", \"program\": \"${PROGRAM}\", \"message\": \"$(escape-double-quotes \"${MSG}\")\"}\n")
    );
};
```

Puis remplacer le bloc `log` de la section 4.3 par :

```
log {
    source(s_apache);
    source(s_snort);
    source(s_src);
    destination(d_local_central);
    destination(d_elastic);
};
```

Deux détails importants dans le corps JSON :

- `@timestamp` est nécessaire, car la data view de Kibana s'en sert pour le champ de temps.
- `escape-double-quotes` protège le JSON : les logs Apache contiennent des guillemets (`"GET ..."`) qui sinon cassent la requête.

```bash
sudo syslog-ng -s
sudo systemctl restart syslog-ng
sudo systemctl status syslog-ng
```

Contrôle côté Elasticsearch :

```bash
curl -s "http://127.0.0.1:9200/_cat/indices/*logs-securite*?v"
```

## 8. Afficher les logs dans Kibana

1. Ouvrir `http://192.168.56.101:5601`.
2. Menu principal → **Stack Management** → **Data Views** → **Create data view**.
3. Motif : `logs-securite-*`.
4. Champ de temps : `@timestamp`, puis **Save data view to Kibana**.
5. **Analytics → Discover**, période sur « Last 15 minutes » ou « Today ».

Dans la barre de recherche, quelques filtres utiles :

| Recherche | Résultat |
|---|---|
| `program : "snort"` | uniquement les alertes Snort |
| `program : "apache2"` | uniquement les accès Apache |
| `message : *SQLI*` | alertes d'injection SQL |
| `message : *ICMP*` | alertes de ping |

Astuce : ajouter les colonnes `host`, `program` et `message` avec le bouton « + » du panneau gauche pour une lecture claire.

## 9. Vérification de bout en bout

| Étape | Commande | Attendu |
|---|---|---|
| Snort alerte | `sudo tail -f /var/log/snort/snort.alert.fast` | une ligne par alerte |
| syslog-ng collecte | `sudo grep -c "SQLI" /var/log/syslog-ng-central.log` | nombre proche de celui de Snort |
| Elasticsearch stocke | `curl -s "http://127.0.0.1:9200/logs-securite-*/_count?pretty"` | `count` qui augmente |
| Kibana affiche | Discover, `logs-securite-*` | les alertes apparaissent en quelques secondes |

## Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| Snort tourne mais aucune alerte | checksums invalides (VirtualBox) | `DEBIAN_SNORT_OPTIONS="-k none"` puis redémarrer |
| Snort refuse de démarrer | règle sur plusieurs lignes ou erreur de syntaxe | `sudo snort -T -c /etc/snort/snort.conf` indique la ligne fautive |
| `grep` répond « binary file matches » | le fichier d'alertes contient des octets nuls | ajouter l'option `-a` à `grep` |
| `netplan apply` échoue | tabulations dans le YAML | n'utiliser que des espaces |
| Rien dans Elasticsearch | JSON cassé par les guillemets | vérifier `escape-double-quotes` dans `d_elastic` |
| Data view vide dans Kibana | période trop courte ou `@timestamp` absent | élargir la période, contrôler le corps JSON |
| Kibana inaccessible | démarrage lent ou `server.host` mal réglé | `sudo ss -tulpn \| grep 5601`, patienter |
| Alertes en double dans Kibana | un même événement vu par Apache et par Snort | normal : filtrer avec `program` |
