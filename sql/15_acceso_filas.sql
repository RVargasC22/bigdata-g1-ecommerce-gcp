-- Row-level security on fact_pedidos (Olist orders). Once a table has a row access policy, a principal sees
-- only the rows of the policies that name it, and NO rows if none does, so the full-access principals
-- (owner, team, the transform service account) need an explicit TRUE filter.
-- CREATE OR REPLACE in sql/04_facts.sql drops the policies: run this script after every rebuild.
-- The ${...} placeholders are filled from config.env by sql/run.sh (run it through run.sh, not bq directly).

CREATE OR REPLACE ROW ACCESS POLICY acceso_total
ON ecommerce.fact_pedidos
GRANT TO ('user:${OWNER_ACCOUNT}', 'user:${TEAM_FULL_ACCESS}', 'serviceAccount:${SA_TRANSFORM}')
FILTER USING (TRUE);

-- Example analyst: category manager for furniture, sees only that category
CREATE OR REPLACE ROW ACCESS POLICY analista_muebles
ON ecommerce.fact_pedidos
GRANT TO ('user:${ANALYST_ACCOUNT}')
FILTER USING (categoria_comun = 'muebles');
