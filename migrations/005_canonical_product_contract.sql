-- migrations/005_canonical_product_contract.sql
-- Contrato canonico do produto — spec "Brazil-Aware Product Normalization".
--
-- Objetivo: product, diagrama, DDL do coletor e Product.java passam a
-- concordar em CAMPOS E SIGNIFICADOS (secoes 1 e 7 da spec).
--
-- O que muda:
--   1. product.subcategory: adicionada em bancos criados antes dela
--      (coluna exige-se presente — Product.java possui o campo).
--   2. product_source_observation ganha proveniencia de fonte:
--      is_generic, tensao declarada (voltage_raw/kind/min/max) e o
--      valor/periodo brutos de energia (raw_energy_value/unit).
--      E e aqui que vivem standby_power_w e is_generic — NAO em product.
--   3. product.standby_power_w e product.is_generic sao DEPRECADOS:
--      mantidos existentes por compatibilidade (nenhum dado e apagado),
--      mas a escrita canonica deixou de usa-los (contrato de 8 colunas).
--
-- Idempotente (IF NOT EXISTS): seguro de aplicar mais de uma vez.
-- Nao apaga registros; nao altera identificadores deterministicos.
--
-- Rollback (reversivel, se necessario):
--   ALTER TABLE product DROP COLUMN IF EXISTS subcategory;
--   ALTER TABLE product_source_observation DROP COLUMN IF EXISTS is_generic;
--   ALTER TABLE product_source_observation DROP COLUMN IF EXISTS voltage_raw;
--   ALTER TABLE product_source_observation DROP COLUMN IF EXISTS voltage_kind;
--   ALTER TABLE product_source_observation DROP COLUMN IF EXISTS voltage_min_v;
--   ALTER TABLE product_source_observation DROP COLUMN IF EXISTS voltage_max_v;
--   ALTER TABLE product_source_observation DROP COLUMN IF EXISTS raw_energy_value;
--   ALTER TABLE product_source_observation DROP COLUMN IF EXISTS raw_energy_unit;
--   (as colunas depreciadas de product NAO devem ser dropadas sem plano
--    de dados: bancos antigos podem ainda consulta-las.)

-- 1. Contrato Product.java em bancos legados -----------------------------
ALTER TABLE product ADD COLUMN IF NOT EXISTS subcategory VARCHAR(255);

-- 2. Proveniencia na observacao de origem --------------------------------
ALTER TABLE product_source_observation
    ADD COLUMN IF NOT EXISTS is_generic BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE product_source_observation
    ADD COLUMN IF NOT EXISTS voltage_raw VARCHAR(50);

-- unknown|monovolt|bivolt|range — o valor fisico nunca e convertido;
-- tensao ausente permanece 'unknown' (nunca inferida por pais/estado).
ALTER TABLE product_source_observation
    ADD COLUMN IF NOT EXISTS voltage_kind VARCHAR(16) NOT NULL DEFAULT 'unknown'
    CHECK (voltage_kind IN ('unknown','monovolt','bivolt','range'));

ALTER TABLE product_source_observation
    ADD COLUMN IF NOT EXISTS voltage_min_v NUMERIC
    CHECK (voltage_min_v IS NULL OR voltage_min_v > 0);

ALTER TABLE product_source_observation
    ADD COLUMN IF NOT EXISTS voltage_max_v NUMERIC
    CHECK (voltage_max_v IS NULL OR voltage_max_v > 0);

-- Energia ANTES de qualquer conversao + unidade/periodo originais
-- (ex.: 30 + 'kWh/mes'; a coluna annual_energy_kwh guarda o valor ja
--  convertido — x12 aplicado exatamente uma vez na ingestao).
ALTER TABLE product_source_observation
    ADD COLUMN IF NOT EXISTS raw_energy_value NUMERIC
    CHECK (raw_energy_value IS NULL OR raw_energy_value >= 0);

ALTER TABLE product_source_observation
    ADD COLUMN IF NOT EXISTS raw_energy_unit VARCHAR(30);

-- 3. Indices (paridade com 004; IF NOT EXISTS = no-op se ja existem) ----
CREATE INDEX IF NOT EXISTS idx_product_source_observation_canonical
    ON product_source_observation (canonical_product_id);

CREATE INDEX IF NOT EXISTS idx_product_source_observation_source
    ON product_source_observation (source);
