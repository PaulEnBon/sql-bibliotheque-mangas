# Bibliothèque de mangas

Une bibliothèque prête des tomes de mangas à ses lecteurs. La base gère les séries, les tomes, les lecteurs et les emprunts, et fait respecter une règle : **trois emprunts en cours au maximum par lecteur** (et un tome déjà emprunté ne s'emprunte pas).

**Groupe** : Elif Yakut, Antoine Masouh, Paul Bourdareau Launay, Ersanios

## Le modèle

| Table | Une ligne, c'est | Lignes |
|---|---|---|
| `series` | une série (titre, auteur, genre) | 12 |
| `tomes` | un tome d'une série | 240 |
| `lecteurs` | un lecteur inscrit (avec e-mail et téléphone) | 2 000 |
| `emprunts` | un emprunt d'un tome par un lecteur ; `rendu_le` est vide tant qu'il n'est pas rendu | 200 005 |

`tomes` pointe vers `series`, `emprunts` pointe vers `lecteurs` et vers `tomes`.

Les deux profils d'utilisateurs :
- **le bibliothécaire** (utilisatrice `lea`) fait le travail courant : il prête et reprend les tomes au comptoir ;
- **le gérant** (utilisateur `marc`) suit la popularité des séries, sans rien modifier.

## Lancer le script sur une base vide

Depuis le dossier `base-festival` du cours :

```bash
docker compose exec db psql -U festival -c "DROP DATABASE IF EXISTS projet WITH (FORCE)" -c "CREATE DATABASE projet"
docker compose cp chemin/vers/projet.sql db:/tmp/projet.sql
docker compose exec db psql -U festival -d projet -f /tmp/projet.sql
```

Au deuxième passage, `CREATE ROLE` affiche `already exists` : les rôles existent pour tout le serveur, c'est sans gravité. Les requêtes de la démo sont dans [demo.sql](demo.sql).

Le support de l'oral est dans [presentation.html](presentation.html) : ouvrez-le dans un navigateur (flèches pour changer de diapo, N pour les notes, F pour le plein écran).

---

## La fonction : `emprunts_en_cours(lecteur)`

**Ce qu'elle fait** : elle renvoie le nombre d'emprunts pas encore rendus d'un lecteur.
**Pourquoi elle est là** : c'est le calcul dont dépend la règle des trois emprunts. Écrit une fois dans la base, il donne le même résultat pour tout le monde, et le trigger s'en sert.
**La preuve** : `SELECT id, prenom, emprunts_en_cours(id) FROM lecteurs WHERE id <= 5;` affiche 3 pour Inès, 1 pour Yanis et Chloé, 0 pour Mehdi et Sarah.

## La procédure : `rendre(emprunt)`

**Ce qu'elle fait** : elle enregistre le retour d'un tome (remplit `rendu_le` avec l'heure actuelle). Elle refuse un emprunt inconnu et un emprunt déjà rendu, avec un message qui dit pourquoi.
**Pourquoi elle est là** : rendre un tome, c'est une action avec des refus ; si elle échoue, rien n'est écrit.
**La preuve** : `CALL rendre(200001);` passe. Le relancer affiche `ERROR: Emprunt 200001 déjà rendu`, et `CALL rendre(999999);` affiche `ERROR: Emprunt 999999 inconnu`.

## Le trigger : `emprunts_refuser_emprunt`

**Ce qu'il fait** : avant chaque nouvel emprunt (`BEFORE INSERT ON emprunts`), il refuse la ligne si le lecteur a déjà trois emprunts en cours, ou si le tome est déjà emprunté et pas encore rendu.
**Pourquoi dans la base plutôt que dans l'application** : c'est une règle qui doit tenir quel que soit le chemin (le comptoir, un futur site de réservation, une requête tapée à la main). Dans la base, personne ne peut l'oublier ni la contourner, même un utilisateur qui écrit directement dans la table.
**La preuve** : en tant que `lea`, `INSERT INTO emprunts (lecteur_id, tome_id) VALUES (1, 100);` affiche `ERROR: Lecteur 1 : déjà 3 emprunts en cours, il doit rendre un tome avant d'en emprunter un autre`. `VALUES (5, 1)` affiche `ERROR: Tome 1 déjà emprunté : il n'a pas encore été rendu`. `VALUES (5, 100)` passe. Après `CALL rendre(200001);`, Inès peut de nouveau emprunter.

## Les vues

### `emprunts_comptoir` (bibliothécaire)

**Ce qu'elle fait** : elle liste les emprunts en cours avec le lecteur (prénom et initiale du nom), la série, le numéro du tome, le nombre de jours et si l'emprunt est en retard (plus de 21 jours).
**Pourquoi elle est là** : elle cache la complexité (trois jointures et le filtre sur `rendu_le`) et protège les données : l'e-mail, le téléphone et le nom complet des lecteurs n'y sont pas.
**La preuve** : en tant que `lea`, `SELECT * FROM emprunts_comptoir;` affiche 5 lignes, dont `Inès L.`. `SELECT email FROM lecteurs;` affiche `permission denied for table lecteurs`.

### `stats_series` (gérant)

**Ce qu'elle fait** : pour chaque série, le nombre d'emprunts, sa part du total en %, les emprunts en cours et la durée moyenne d'un emprunt.
**Pourquoi elle est là** : le gérant suit la popularité des séries sans voir aucune donnée personnelle ni aucun emprunt individuel.
**La preuve** : en tant que `marc`, `SELECT * FROM stats_series ORDER BY emprunts DESC;` affiche les 12 séries. `SELECT * FROM emprunts_comptoir;` affiche `permission denied for view emprunts_comptoir`.

## Les rôles

**Ce qu'ils font** : deux rôles-métiers `NOLOGIN` reçoivent les droits ; chaque personne se connecte avec son propre compte et hérite d'un rôle (`lea` → `bibliothecaire`, `marc` → `gerant`).
- `bibliothecaire` : lecture de sa vue ; `INSERT` dans `emprunts` ; `UPDATE` de la seule colonne `rendu_le` ; lecture des colonnes `id, lecteur_id, tome_id, rendu_le` de `emprunts`, dont le trigger et la procédure ont besoin (aucune n'est une donnée personnelle). Aucun droit sur `lecteurs`, `series`, `tomes`.
- `gerant` : lecture de sa vue, rien d'autre.

**Pourquoi ils sont là** : principe du moindre privilège. Chaque compte a le strict nécessaire, et quand Léa quitte la bibliothèque on supprime `lea` sans toucher aux droits du bibliothécaire.
**La preuve** :
- `SET ROLE lea;` puis `INSERT INTO emprunts (lecteur_id, tome_id) VALUES (5, 100);` est **autorisé**, `SELECT email FROM lecteurs WHERE id = 1;` est **refusé** (`permission denied for table lecteurs`).
- `SET ROLE marc;` puis `SELECT * FROM stats_series;` est **autorisé**, `INSERT INTO emprunts (lecteur_id, tome_id) VALUES (5, 100);` est **refusé** (`permission denied for table emprunts`).
- `RESET ROLE;` après chaque test.

## Les index

Mesures faites avec `EXPLAIN ANALYZE`, sur 200 005 emprunts, chaque mesure lancée deux fois (on garde la seconde).

### `emprunts_lecteur_idx` sur `emprunts (lecteur_id)`

**Requête** : `SELECT * FROM emprunts WHERE lecteur_id = 1234;` (l'historique d'un lecteur)
**Avant** : `Seq Scan`, 3,7 ms (199 905 lignes lues pour rien).
**Index** : sur la clé étrangère `lecteur_id`, que PostgreSQL n'indexe pas tout seul. Il sert aussi au trigger, qui compte les emprunts en cours du lecteur à chaque nouvel emprunt.
**Après** : `Bitmap Index Scan`, 0,09 ms, environ 40 fois plus rapide.

### `emprunts_emprunte_le_idx` sur `emprunts (emprunte_le)`

**Requête** : `SELECT * FROM emprunts WHERE emprunte_le >= '2026-03-03' AND emprunte_le < '2026-03-04';` (les emprunts d'une journée)
**Avant** : `Parallel Seq Scan`, 3,4 ms.
**Index** : sur la date d'emprunt ; une journée ne représente que 333 lignes sur 200 000.
**Après** : `Bitmap Index Scan`, 0,18 ms, environ 19 fois plus rapide.

Les temps varient d'une machine à l'autre ; ce qui compte, c'est le passage du `Seq Scan` à l'index et l'écart entre les deux. Pour refaire la mesure : `DROP INDEX` l'index, `EXPLAIN ANALYZE` la requête, `CREATE INDEX`, puis `EXPLAIN ANALYZE` à nouveau (voir la partie 3 de [demo.sql](demo.sql)).

## Les données

`emprunts` contient 200 005 lignes générées avec `generate_series` (200 000 emprunts rendus, répartis sur 600 jours, plus 5 emprunts en cours tapés à la main pour la démo). Les autres tables sont remplies à la main (séries, 5 lecteurs) ou générées (tomes, 1 995 lecteurs).
