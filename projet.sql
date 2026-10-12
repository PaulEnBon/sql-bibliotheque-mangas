-- =====================================================================
-- Projet SQL avancé B2 : la bibliothèque de mangas
-- Ordre du script : tables, données, fonction et procédure, trigger,
-- vues, rôles, index.
-- =====================================================================


-- =====================================================================
-- 1. Les tables
-- Une série contient des tomes ; un lecteur emprunte des tomes.
-- =====================================================================

CREATE TABLE series (
    id      serial PRIMARY KEY,
    titre   text NOT NULL UNIQUE,
    auteur  text NOT NULL,
    genre   text NOT NULL CHECK (genre IN ('shonen', 'seinen', 'shojo', 'josei'))
);

CREATE TABLE tomes (
    id        serial PRIMARY KEY,
    serie_id  integer NOT NULL REFERENCES series (id),
    numero    integer NOT NULL CHECK (numero > 0),
    UNIQUE (serie_id, numero)                       -- un seul tome 3 par série
);

CREATE TABLE lecteurs (
    id          serial PRIMARY KEY,
    prenom      text NOT NULL,
    nom         text NOT NULL,
    email       text NOT NULL UNIQUE,
    telephone   text,
    ville       text,
    inscrit_le  date NOT NULL DEFAULT current_date
);

CREATE TABLE emprunts (
    id           serial PRIMARY KEY,
    lecteur_id   integer NOT NULL REFERENCES lecteurs (id),
    tome_id      integer NOT NULL REFERENCES tomes (id),
    emprunte_le  timestamp NOT NULL DEFAULT now(),
    rendu_le     timestamp,                         -- vide tant que le tome n'est pas rendu
    CHECK (rendu_le IS NULL OR rendu_le >= emprunte_le)
);


-- =====================================================================
-- 2. Les données
-- On remplit d'abord les tables référencées, puis celles qui pointent
-- vers elles. Seule la table emprunts a du volume (200 000 lignes).
-- =====================================================================

INSERT INTO series (titre, auteur, genre) VALUES
    ('One Piece',             'Eiichiro Oda',      'shonen'),
    ('Naruto',                'Masashi Kishimoto', 'shonen'),
    ('L''Attaque des Titans', 'Hajime Isayama',    'shonen'),
    ('Death Note',            'Tsugumi Ohba',      'shonen'),
    ('Fullmetal Alchemist',   'Hiromu Arakawa',    'shonen'),
    ('Jujutsu Kaisen',        'Gege Akutami',      'shonen'),
    ('Berserk',               'Kentaro Miura',     'seinen'),
    ('Vinland Saga',          'Makoto Yukimura',   'seinen'),
    ('Monster',               'Naoki Urasawa',     'seinen'),
    ('Fruits Basket',         'Natsuki Takaya',    'shojo'),
    ('Nana',                  'Ai Yazawa',         'shojo'),
    ('Chihayafuru',           'Yuki Suetsugu',     'josei');

-- 20 tomes par série : 240 tomes.
-- i % 12 choisit la série, (i - 1) / 12 donne le numéro (division entière).
INSERT INTO tomes (serie_id, numero)
SELECT 1 + (i % 12),
       1 + (i - 1) / 12
FROM generate_series(1, 240) AS i;

-- Quelques lecteurs tapés à la main, pour la démo...
INSERT INTO lecteurs (prenom, nom, email, telephone, ville) VALUES
    ('Inès',   'Lambert', 'ines.lambert@proton.me', '06 12 34 56 78', 'Strasbourg'),
    ('Yanis',  'Moreau',  'yanis.moreau@gmail.com', '06 98 76 54 32', 'Lyon'),
    ('Chloé',  'Garnier', 'chloe.garnier@free.fr',  '07 11 22 33 44', 'Paris'),
    ('Mehdi',  'Benali',  'mehdi.benali@orange.fr', '06 55 44 33 22', 'Marseille'),
    ('Sarah',  'Petit',   'sarah.petit@yahoo.fr',   '07 66 77 88 99', 'Nantes');

-- ... puis 1 995 de plus, générés : 2 000 lecteurs au total.
INSERT INTO lecteurs (prenom, nom, email, telephone, ville)
SELECT 'Lecteur ' || i,
       'Nom' || i,
       'lecteur' || i || '@mail.fr',
       '06 00 ' || i,
       'Ville ' || (1 + i % 30)
FROM generate_series(6, 2000) AS i;

-- L'historique : 200 000 emprunts, tous rendus, répartis sur 600 jours.
INSERT INTO emprunts (lecteur_id, tome_id, emprunte_le, rendu_le)
SELECT 1 + (i % 2000),                                   -- un lecteur parmi les 2 000
       1 + (i % 240),                                    -- un tome parmi les 240
       date '2025-01-01' + (i % 600),                    -- emprunté un jour parmi 600
       date '2025-01-01' + (i % 600) + (1 + i % 21)      -- rendu 1 à 21 jours plus tard
FROM generate_series(1, 200000) AS i;

-- Les emprunts en cours (pas encore rendus).
-- Inès (lecteur 1) en a déjà trois : elle est au maximum.
INSERT INTO emprunts (lecteur_id, tome_id, emprunte_le) VALUES
    (1, 1,  '2026-10-01'),
    (1, 13, '2026-10-03'),
    (1, 25, '2026-10-05'),
    (2, 7,  '2026-10-02'),
    (3, 50, '2026-09-10');     -- emprunté depuis plus de 21 jours : en retard


-- =====================================================================
-- 3. La fonction et la procédure
-- =====================================================================

-- Fonction : le nombre d'emprunts en cours d'un lecteur.
-- Elle calcule et renvoie une valeur ; le trigger s'en sert.
CREATE FUNCTION emprunts_en_cours(p_lecteur_id int)
RETURNS bigint
LANGUAGE sql
AS $$
    SELECT count(*)
    FROM emprunts
    WHERE lecteur_id = p_lecteur_id
      AND rendu_le IS NULL;
$$;

-- Procédure : rendre un tome. Elle agit, et refuse quand il le faut.
CREATE PROCEDURE rendre(p_emprunt_id int)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM emprunts WHERE id = p_emprunt_id) THEN
        RAISE EXCEPTION 'Emprunt % inconnu', p_emprunt_id;
    END IF;

    IF EXISTS (SELECT 1 FROM emprunts WHERE id = p_emprunt_id AND rendu_le IS NOT NULL) THEN
        RAISE EXCEPTION 'Emprunt % déjà rendu', p_emprunt_id;
    END IF;

    UPDATE emprunts SET rendu_le = now() WHERE id = p_emprunt_id;
END;
$$;


-- =====================================================================
-- 4. Le trigger
-- Avant chaque nouvel emprunt, la base vérifie deux règles :
--   - un lecteur a au plus trois emprunts en cours ;
--   - un tome déjà emprunté (pas encore rendu) ne s'emprunte pas.
-- =====================================================================

CREATE FUNCTION refuser_emprunt()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF emprunts_en_cours(NEW.lecteur_id) >= 3 THEN
        RAISE EXCEPTION 'Lecteur % : déjà 3 emprunts en cours, il doit rendre un tome avant d''en emprunter un autre',
            NEW.lecteur_id;
    END IF;

    IF EXISTS (SELECT 1 FROM emprunts WHERE tome_id = NEW.tome_id AND rendu_le IS NULL) THEN
        RAISE EXCEPTION 'Tome % déjà emprunté : il n''a pas encore été rendu', NEW.tome_id;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER emprunts_refuser_emprunt
BEFORE INSERT ON emprunts
FOR EACH ROW
EXECUTE FUNCTION refuser_emprunt();


-- =====================================================================
-- 5. Les vues : une par rôle
-- =====================================================================

-- Vue du bibliothécaire : les emprunts en cours, au comptoir.
-- Elle cache la complexité (trois jointures) et masque le lecteur :
-- prénom et initiale du nom, ni e-mail ni téléphone.
CREATE VIEW emprunts_comptoir AS
SELECT e.id                                  AS emprunt_id,
       e.lecteur_id,
       l.prenom || ' ' || left(l.nom, 1) || '.' AS lecteur,
       s.titre                               AS serie,
       t.numero                              AS tome,
       e.tome_id,
       e.emprunte_le,
       current_date - e.emprunte_le::date    AS jours,
       current_date - e.emprunte_le::date > 21 AS en_retard
FROM emprunts e
JOIN lecteurs l ON l.id = e.lecteur_id
JOIN tomes t    ON t.id = e.tome_id
JOIN series s   ON s.id = t.serie_id
WHERE e.rendu_le IS NULL;

-- Vue du gérant : la popularité de chaque série, sans aucune donnée
-- personnelle. Une CTE et une fonction de fenêtre (séance 3).
CREATE VIEW stats_series AS
WITH par_serie AS (
    SELECT s.titre,
           s.genre,
           count(*)                                         AS emprunts,
           count(*) - count(e.rendu_le)                     AS en_cours,     -- count(colonne) ignore les vides
           round(avg(e.rendu_le::date - e.emprunte_le::date), 1) AS duree_moyenne_jours
    FROM emprunts e
    JOIN tomes t  ON t.id = e.tome_id
    JOIN series s ON s.id = t.serie_id
    GROUP BY s.titre, s.genre
)
SELECT titre,
       genre,
       emprunts,
       round(100.0 * emprunts / sum(emprunts) OVER (), 1) AS part_pct,
       en_cours,
       duree_moyenne_jours
FROM par_serie;


-- =====================================================================
-- 6. Les rôles
-- Les droits vont aux rôles-métiers ; les personnes en héritent.
-- Au deuxième passage du script, CREATE ROLE affiche « already exists » :
-- les rôles existent pour tout le serveur. C'est sans gravité.
-- =====================================================================

-- Le bibliothécaire : le travail courant (prêter, reprendre un tome).
CREATE ROLE bibliothecaire NOLOGIN;
CREATE ROLE lea LOGIN PASSWORD 'lea' IN ROLE bibliothecaire;

-- Le gérant : il contrôle, sans rien modifier.
CREATE ROLE gerant NOLOGIN;
CREATE ROLE marc LOGIN PASSWORD 'marc' IN ROLE gerant;

-- Bibliothécaire : il lit sa vue, pas la table lecteurs.
GRANT SELECT ON emprunts_comptoir TO bibliothecaire;
-- Il enregistre un emprunt (INSERT) et un retour (CALL rendre).
GRANT INSERT ON emprunts TO bibliothecaire;
GRANT USAGE ON SEQUENCE emprunts_id_seq TO bibliothecaire;   -- pour le numéro automatique (serial)
GRANT UPDATE (rendu_le) ON emprunts TO bibliothecaire;       -- seulement la date de retour
-- Le trigger et la procédure lisent ces colonnes avec ses droits :
-- aucune n'est une donnée personnelle.
GRANT SELECT (id, lecteur_id, tome_id, rendu_le) ON emprunts TO bibliothecaire;

-- Gérant : uniquement la lecture de sa vue.
GRANT SELECT ON stats_series TO gerant;


-- =====================================================================
-- 7. Les index
-- Mesurés avant et après avec EXPLAIN ANALYZE (voir le README).
-- PostgreSQL n'indexe pas les clés étrangères tout seul.
-- =====================================================================

-- Les emprunts d'un lecteur (et le comptage du trigger).
CREATE INDEX emprunts_lecteur_idx ON emprunts (lecteur_id);

-- Les emprunts d'une journée.
CREATE INDEX emprunts_emprunte_le_idx ON emprunts (emprunte_le);
