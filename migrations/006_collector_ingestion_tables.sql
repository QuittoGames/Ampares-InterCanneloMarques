-- migrations/006_collector_ingestion_tables.sql
-- Tabelas auxiliares de ingestao do coletor (spec "Especificacao do Banco
-- de Dados", secoes 4 e 8): criadas EXCLUSIVAMENTE por migracao versionada
-- — o coletor Python NUNCA executa DDL (politica INSERT-ONLY, DO NOTHING).
--
-- * energy_label_class: classe de eficiencia ENCE declarada pela fonte
--   (INMETRO/PBE). FK para product; id = uuid5 deterministico do produto.
-- * aggregate_reference: referencia ESTATISTICA anonima por fonte/pais/ano
--   (IEA). Nao tem FK para product: nao e produto individual.
--
-- Idempotente (IF NOT EXISTS). Nao apaga registros.
--
-- Rollback (se necessario):
--   DROP TABLE IF EXISTS aggregate_reference;
--   DROP TABLE IF EXISTS energy_label_class;

-- 1. Classe ENCE por produto canônico -----------------------------------
-- 'A+++' existe na tabela PBE real (Padrão 2022, verificado no XLSX
-- oficial) e por isso integra o vocabulário.
CREATE TABLE IF NOT EXISTS energy_label_class (
    id          UUID PRIMARY KEY REFERENCES product(id) ON DELETE CASCADE,
    label_class VARCHAR(10) NOT NULL
                 CHECK (label_class IN ('A+++','A++','A+','A','B','C','D','E','F','G')),
    updated_at  TIMESTAMPTZ DEFAULT now()
);

-- Upgrade idempotente para bancos onde a tabela já existia com o CHECK
-- antigo (sem 'A+++'): recria a constraint apenas se o vocabulário novo
-- ainda não estiver presente.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'energy_label_class')
       AND NOT EXISTS (
           SELECT 1 FROM pg_constraint
           WHERE conrelid = 'energy_label_class'::regclass
             AND contype = 'c'
             AND pg_get_constraintdef(oid) LIKE '%A+++%'
       )
    THEN
        ALTER TABLE energy_label_class
            DROP CONSTRAINT IF EXISTS energy_label_class_label_class_check;
        ALTER TABLE energy_label_class
            ADD CONSTRAINT energy_label_class_label_class_check
            CHECK (label_class IN ('A+++','A++','A+','A','B','C','D','E','F','G'));
    END IF;
END $$;

-- 2. Referencia estatistica agregada (nunca produto individual) ---------
CREATE TABLE IF NOT EXISTS aggregate_reference (
    id        UUID PRIMARY KEY,
    source    VARCHAR(50) NOT NULL,
    country   VARCHAR(100) NOT NULL,
    ref_year  SMALLINT NOT NULL CHECK (ref_year >= 1900),
    metric    VARCHAR(100) NOT NULL,
    appliance VARCHAR(100),
    value     NUMERIC NOT NULL,
    unit      VARCHAR(30) NOT NULL,
    UNIQUE (source, country, ref_year, metric, appliance)
);
