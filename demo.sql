-- =====================================================================
-- Démo du jeudi 15 : les requêtes à lancer, dans l'ordre de la trame.
-- À lancer juste après projet.sql, sur une base fraîche :
--   docker compose exec db psql -U festival -d projet
--   puis copier-coller chaque bloc (ou \i /tmp/demo.sql).
-- Les lignes marquées « refusé » doivent afficher une erreur.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Un rôle : SET ROLE, une action autorisée, une action refusée
-- ---------------------------------------------------------------------

SET ROLE lea;                                             -- on devient Léa, bibliothécaire
SELECT * FROM emprunts_comptoir ORDER BY emprunt_id;     -- autorisé : sa vue
SELECT email, telephone FROM lecteurs WHERE id = 1;      -- refusé : permission denied for table lecteurs
RESET ROLE;

SET ROLE marc;                                            -- on devient Marc, gérant
SELECT * FROM stats_series ORDER BY emprunts DESC;       -- autorisé : sa vue
INSERT INTO emprunts (lecteur_id, tome_id) VALUES (5, 100);  -- refusé : il ne modifie rien
SELECT * FROM emprunts_comptoir;                         -- refusé : ce n'est pas sa vue
RESET ROLE;


-- ---------------------------------------------------------------------
-- 2. Une vue : ce qu'elle montre, et ce qu'elle cache
-- ---------------------------------------------------------------------

-- Ce que contient la table (en tant que festival, qui a tous les droits) :
SELECT * FROM lecteurs WHERE id = 1;
-- Ce que Léa voit du même lecteur : prénom et initiale, ni e-mail ni téléphone.
SET ROLE lea;
SELECT lecteur, serie, tome, jours, en_retard FROM emprunts_comptoir WHERE lecteur_id = 1;
RESET ROLE;


-- ---------------------------------------------------------------------
-- 3. Un index : la requête, le temps avant, le temps après
-- Lancer chaque EXPLAIN ANALYZE deux fois et garder la seconde mesure.
-- ---------------------------------------------------------------------

-- Index a : les emprunts d'un lecteur
DROP INDEX emprunts_lecteur_idx;
EXPLAIN ANALYZE SELECT * FROM emprunts WHERE lecteur_id = 1234;     -- Seq Scan
CREATE INDEX emprunts_lecteur_idx ON emprunts (lecteur_id);
EXPLAIN ANALYZE SELECT * FROM emprunts WHERE lecteur_id = 1234;     -- Bitmap Index Scan

-- Index b : les emprunts d'une journée
DROP INDEX emprunts_emprunte_le_idx;
EXPLAIN ANALYZE SELECT * FROM emprunts
WHERE emprunte_le >= '2026-03-03' AND emprunte_le < '2026-03-04';   -- Seq Scan
CREATE INDEX emprunts_emprunte_le_idx ON emprunts (emprunte_le);
EXPLAIN ANALYZE SELECT * FROM emprunts
WHERE emprunte_le >= '2026-03-03' AND emprunte_le < '2026-03-04';   -- Index Scan


-- ---------------------------------------------------------------------
-- 4. Un trigger : l'action qui le déclenche, et ce qu'on observe
-- On le déclenche en tant que Léa : la règle tient aussi pour elle.
-- ---------------------------------------------------------------------

SET ROLE lea;
SELECT lecteur_id, count(*) FROM emprunts_comptoir GROUP BY lecteur_id;   -- Inès (1) a 3 emprunts en cours

INSERT INTO emprunts (lecteur_id, tome_id) VALUES (1, 100);  -- refusé : Lecteur 1 : déjà 3 emprunts en cours...
INSERT INTO emprunts (lecteur_id, tome_id) VALUES (5, 1);    -- refusé : Tome 1 déjà emprunté...
INSERT INTO emprunts (lecteur_id, tome_id) VALUES (5, 100);  -- passe

-- La procédure : Inès rend un tome, puis peut en emprunter un autre.
CALL rendre(200001);                                          -- passe
INSERT INTO emprunts (lecteur_id, tome_id) VALUES (1, 101);  -- passe maintenant
CALL rendre(200001);                                          -- refusé : Emprunt 200001 déjà rendu
CALL rendre(999999);                                          -- refusé : Emprunt 999999 inconnu
RESET ROLE;
