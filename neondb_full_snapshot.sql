-- ============================================================================
-- neondb_full_snapshot.sql
-- Snapshot COMPLETO, idempotente e validado do PostgreSQL real do projeto.
--
-- CONTEDO: schema (10 tabelas + sequence users_id_seq + funo show_db_tree())
--          + todos os dados reais, com IDs originares preservados.
-- ORIGEM : container Docker `neondb-local` (postgres:18.6), db `neondb`,
--          user `neondb_owner` (extraido via pg_dump --schema-only + psycopg).
--
-- COMO EXECUTAR (psql, NAO e SQL puro universal - usa meta-comandos psql):
--   Defina as variaveis de conexao do SERVIDOR (nao do banco) e rode:
--     PGHOST=localhost PGPORT=5432 PGUSER=<user_com_permissao> PGPASSWORD=<senha> \
--     psql -v ON_ERROR_STOP=1 -d postgres -f neondb_full_snapshot.sql
--   Para criar/carregar num banco de validacao isolado (NUNCA no fonte):
--     psql -v ON_ERROR_STOP=1 -v snap_db=neondb_snapshot_val -d postgres -f neondb_full_snapshot.sql
--
-- PERMISSOES NECESSARIAS no papel que executa:
--   - CONNECT no servidor (para conectar ao banco maintenance `postgres`);
--   - CREATE no database maintenance (para criar o banco alvo se nao existir);
--   - MEMBRO do role alvo (`neondb_owner`) ou owner do banco, para criar
--     schema/tables e inserir dados.
--
-- CONEXAO INICIAL ESPERADA: conecte a um banco maintenance (ex.: `postgres`).
-- O script cria o banco alvo se nao existir (sem destruir existente) e
-- reconecta a ele. Nenhuma credencial fica hardcoded neste arquivo.
--
-- SEGURANCA: NAO execute contra o banco fonte `neondb` se voce apenas quer
-- validar - use -v snap_db=<outro_nome>. O arquivo contem DADOS REAIS; nao
-- commite sem decisao explicita do DEV.
-- ============================================================================

\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

-- Nome do banco alvo (configuravel p/ validacao isolada; default = neondb).
\if :{?snap_db} \else \set snap_db neondb \endif

-- Cria o banco somente se nao existir (nao destrui nada) e reconecta.
SELECT format('CREATE DATABASE %I', :'snap_db')
  WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'snap_db') \gexec

\connect :"snap_db"

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

-- ============================================================================
-- SECAO DDL (idempotente - nenhum DROP/TRUNCATE/CASCADE)
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS public;

-- ---------------------------------------------------------------- tabelas --
CREATE TABLE IF NOT EXISTS public.aggregate_reference (
    id uuid NOT NULL,
    source character varying(50) NOT NULL,
    country character varying(100) NOT NULL,
    ref_year smallint NOT NULL,
    metric character varying(100) NOT NULL,
    appliance character varying(100),
    value numeric NOT NULL,
    unit character varying(30) NOT NULL,
    CONSTRAINT aggregate_reference_ref_year_check CHECK ((ref_year >= 1900))
);

CREATE TABLE IF NOT EXISTS public.energy_label_class (
    id uuid NOT NULL,
    label_class character varying(10) NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT energy_label_class_label_class_check CHECK (((label_class)::text = ANY ((ARRAY['A+++'::character varying, 'A++'::character varying, 'A+'::character varying, 'A'::character varying, 'B'::character varying, 'C'::character varying, 'D'::character varying, 'E'::character varying, 'F'::character varying, 'G'::character varying])::text[])))
);

CREATE TABLE IF NOT EXISTS public.energy_raw_measurement (
    id uuid NOT NULL,
    raw_power_w numeric,
    raw_annual_kwh numeric,
    raw_standby_w numeric,
    measurement_date timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.energy_specification (
    product_id uuid NOT NULL,
    source character varying(50) NOT NULL,
    source_product_id character varying(255),
    power_w numeric,
    efficiency_class character varying(10),
    declared_year smallint
);

CREATE TABLE IF NOT EXISTS public.product (
    id uuid NOT NULL,
    name character varying(150),
    brand character varying(255),
    model character varying(255),
    category character varying(255),
    avg_power_w numeric(38,2),
    annual_energy_kwh numeric(38,2),
    subcategory character varying(255),
    standby_power_w numeric,
    is_generic boolean DEFAULT false,
    avg_idle_energy_for_hour numeric(38,2)
);

CREATE TABLE IF NOT EXISTS public.product_source_observation (
    id uuid NOT NULL,
    canonical_product_id uuid NOT NULL,
    source character varying(50) NOT NULL,
    external_id character varying(255) NOT NULL,
    brand character varying(255),
    model character varying(255),
    dataset_id character varying(255),
    power_w numeric,
    annual_energy_kwh numeric,
    standby_power_w numeric,
    observed_at timestamp with time zone DEFAULT now() NOT NULL,
    is_generic boolean DEFAULT false NOT NULL,
    voltage_raw character varying(50),
    voltage_kind character varying(16) DEFAULT 'unknown'::character varying NOT NULL,
    voltage_min_v numeric,
    voltage_max_v numeric,
    raw_energy_value numeric,
    raw_energy_unit character varying(30),
    CONSTRAINT product_source_observation_annual_energy_kwh_check CHECK (((annual_energy_kwh IS NULL) OR (annual_energy_kwh >= (0)::numeric))),
    CONSTRAINT product_source_observation_power_w_check CHECK (((power_w IS NULL) OR (power_w >= (0)::numeric))),
    CONSTRAINT product_source_observation_raw_energy_value_check CHECK (((raw_energy_value IS NULL) OR (raw_energy_value >= (0)::numeric))),
    CONSTRAINT product_source_observation_standby_power_w_check CHECK (((standby_power_w IS NULL) OR (standby_power_w >= (0)::numeric))),
    CONSTRAINT product_source_observation_voltage_kind_check CHECK (((voltage_kind)::text = ANY ((ARRAY['unknown'::character varying, 'monovolt'::character varying, 'bivolt'::character varying, 'range'::character varying])::text[]))),
    CONSTRAINT product_source_observation_voltage_max_v_check CHECK (((voltage_max_v IS NULL) OR (voltage_max_v > (0)::numeric))),
    CONSTRAINT product_source_observation_voltage_min_v_check CHECK (((voltage_min_v IS NULL) OR (voltage_min_v > (0)::numeric)))
);

CREATE TABLE IF NOT EXISTS public.registry_user_product (
    id uuid CONSTRAINT userproduct_id_not_null NOT NULL,
    avg_active_hours numeric(38,2),
    hours_standby numeric(38,2),
    quantity integer CONSTRAINT userproduct_quantity_not_null NOT NULL,
    product_id uuid CONSTRAINT userproduct_product_id_not_null NOT NULL,
    user_id integer CONSTRAINT userproduct_user_id_not_null NOT NULL
);

CREATE TABLE IF NOT EXISTS public.source_metadata (
    id uuid NOT NULL,
    source character varying(50) NOT NULL,
    metadata_key character varying(100) NOT NULL,
    metadata_value text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.source_product (
    id uuid NOT NULL,
    source character varying(50) NOT NULL,
    source_product_id character varying(255) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.users (
    id integer NOT NULL,
    name character varying(50)
);

-- --------------------------------------------------------------- sequence --
CREATE SEQUENCE IF NOT EXISTS public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;

ALTER TABLE public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


-- ============================================================================
-- CONSTRAINTS (PK / UNIQUE / FK) - ADD CONSTRAINT nao e idempotente, entao cada
-- bloco e guardado por existencia em pg_constraint.
-- ============================================================================

-- PK
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='aggregate_reference_pkey' AND conrelid='public.aggregate_reference'::regclass) THEN ALTER TABLE ONLY public.aggregate_reference ADD CONSTRAINT aggregate_reference_pkey PRIMARY KEY (id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='energy_label_class_pkey' AND conrelid='public.energy_label_class'::regclass) THEN ALTER TABLE ONLY public.energy_label_class ADD CONSTRAINT energy_label_class_pkey PRIMARY KEY (id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='energy_raw_measurement_pkey' AND conrelid='public.energy_raw_measurement'::regclass) THEN ALTER TABLE ONLY public.energy_raw_measurement ADD CONSTRAINT energy_raw_measurement_pkey PRIMARY KEY (id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='energy_specification_pkey' AND conrelid='public.energy_specification'::regclass) THEN ALTER TABLE ONLY public.energy_specification ADD CONSTRAINT energy_specification_pkey PRIMARY KEY (product_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='product_pkey' AND conrelid='public.product'::regclass) THEN ALTER TABLE ONLY public.product ADD CONSTRAINT product_pkey PRIMARY KEY (id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='product_source_observation_pkey' AND conrelid='public.product_source_observation'::regclass) THEN ALTER TABLE ONLY public.product_source_observation ADD CONSTRAINT product_source_observation_pkey PRIMARY KEY (id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='source_metadata_pkey' AND conrelid='public.source_metadata'::regclass) THEN ALTER TABLE ONLY public.source_metadata ADD CONSTRAINT source_metadata_pkey PRIMARY KEY (id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='source_product_pkey' AND conrelid='public.source_product'::regclass) THEN ALTER TABLE ONLY public.source_product ADD CONSTRAINT source_product_pkey PRIMARY KEY (id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='userproduct_pkey' AND conrelid='public.registry_user_product'::regclass) THEN ALTER TABLE ONLY public.registry_user_product ADD CONSTRAINT userproduct_pkey PRIMARY KEY (id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='users_pkey' AND conrelid='public.users'::regclass) THEN ALTER TABLE ONLY public.users ADD CONSTRAINT users_pkey PRIMARY KEY (id); END IF; END $$;

-- UNIQUE
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='aggregate_reference_source_country_ref_year_metric_applianc_key' AND conrelid='public.aggregate_reference'::regclass) THEN ALTER TABLE ONLY public.aggregate_reference ADD CONSTRAINT aggregate_reference_source_country_ref_year_metric_applianc_key UNIQUE (source, country, ref_year, metric, appliance); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='energy_specification_source_source_product_id_key' AND conrelid='public.energy_specification'::regclass) THEN ALTER TABLE ONLY public.energy_specification ADD CONSTRAINT energy_specification_source_source_product_id_key UNIQUE (source, source_product_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='product_source_observation_source_external_id_key' AND conrelid='public.product_source_observation'::regclass) THEN ALTER TABLE ONLY public.product_source_observation ADD CONSTRAINT product_source_observation_source_external_id_key UNIQUE (source, external_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='source_metadata_id_source_metadata_key_key' AND conrelid='public.source_metadata'::regclass) THEN ALTER TABLE ONLY public.source_metadata ADD CONSTRAINT source_metadata_id_source_metadata_key_key UNIQUE (id, source, metadata_key); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='source_product_source_source_product_id_key' AND conrelid='public.source_product'::regclass) THEN ALTER TABLE ONLY public.source_product ADD CONSTRAINT source_product_source_source_product_id_key UNIQUE (source, source_product_id); END IF; END $$;

-- FK
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='energy_label_class_id_fkey' AND conrelid='public.energy_label_class'::regclass) THEN ALTER TABLE ONLY public.energy_label_class ADD CONSTRAINT energy_label_class_id_fkey FOREIGN KEY (id) REFERENCES public.product(id) ON DELETE CASCADE; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='energy_raw_measurement_id_fkey' AND conrelid='public.energy_raw_measurement'::regclass) THEN ALTER TABLE ONLY public.energy_raw_measurement ADD CONSTRAINT energy_raw_measurement_id_fkey FOREIGN KEY (id) REFERENCES public.product(id) ON DELETE CASCADE; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='energy_specification_product_id_fkey' AND conrelid='public.energy_specification'::regclass) THEN ALTER TABLE ONLY public.energy_specification ADD CONSTRAINT energy_specification_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.product(id) ON DELETE CASCADE; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='fk3etfihtbju2j994iwrlh6wvme' AND conrelid='public.registry_user_product'::regclass) THEN ALTER TABLE ONLY public.registry_user_product ADD CONSTRAINT fk3etfihtbju2j994iwrlh6wvme FOREIGN KEY (product_id) REFERENCES public.product(id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='fkj4ebrocbxucugfqvdt1w2cnim' AND conrelid='public.registry_user_product'::regclass) THEN ALTER TABLE ONLY public.registry_user_product ADD CONSTRAINT fkj4ebrocbxucugfqvdt1w2cnim FOREIGN KEY (user_id) REFERENCES public.users(id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='product_source_observation_canonical_product_id_fkey' AND conrelid='public.product_source_observation'::regclass) THEN ALTER TABLE ONLY public.product_source_observation ADD CONSTRAINT product_source_observation_canonical_product_id_fkey FOREIGN KEY (canonical_product_id) REFERENCES public.product(id) ON DELETE CASCADE; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='source_metadata_id_fkey' AND conrelid='public.source_metadata'::regclass) THEN ALTER TABLE ONLY public.source_metadata ADD CONSTRAINT source_metadata_id_fkey FOREIGN KEY (id) REFERENCES public.product(id) ON DELETE CASCADE; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='source_product_id_fkey' AND conrelid='public.source_product'::regclass) THEN ALTER TABLE ONLY public.source_product ADD CONSTRAINT source_product_id_fkey FOREIGN KEY (id) REFERENCES public.product(id) ON DELETE CASCADE; END IF; END $$;

-- ---------------------------------------------------------------- indices --
CREATE INDEX IF NOT EXISTS idx_product_source_observation_canonical ON public.product_source_observation USING btree (canonical_product_id);
CREATE INDEX IF NOT EXISTS idx_product_source_observation_source ON public.product_source_observation USING btree (source);
CREATE UNIQUE INDEX IF NOT EXISTS uk_userproduct_user_product ON public.registry_user_product USING btree (user_id, product_id);

-- ------------------------------------------------------------------ funcao --
CREATE OR REPLACE FUNCTION public.show_db_tree() RETURNS TABLE(tree_structure text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- First show all databases
    RETURN QUERY
    SELECT ':file_folder: ' || datname || ' (DATABASE)'
    FROM pg_database
    WHERE datistemplate = false;

    -- Then show current database structure
    RETURN QUERY
    WITH RECURSIVE
    -- Get schemas
    schemas AS (
        SELECT
            n.nspname AS object_name,
            1 AS level,
            n.nspname AS path,
            'SCHEMA' AS object_type
        FROM pg_namespace n
        WHERE n.nspname NOT LIKE 'pg_%'
        AND n.nspname != 'information_schema'
    ),

    -- Get all objects (tables, views, functions, etc.)
    objects AS (
        SELECT
            c.relname AS object_name,
            2 AS level,
            s.path || ' → ' || c.relname AS path,
            CASE c.relkind
                WHEN 'r' THEN 'TABLE'
                WHEN 'v' THEN 'VIEW'
                WHEN 'm' THEN 'MATERIALIZED VIEW'
                WHEN 'i' THEN 'INDEX'
                WHEN 'S' THEN 'SEQUENCE'
                WHEN 'f' THEN 'FOREIGN TABLE'
            END AS object_type
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN schemas s ON n.nspname = s.object_name
        WHERE c.relkind IN ('r','v','m','i','S','f')

        UNION ALL

        SELECT
            p.proname AS object_name,
            2 AS level,
            s.path || ' → ' || p.proname AS path,
            'FUNCTION' AS object_type
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        JOIN schemas s ON n.nspname = s.object_name
    ),

    -- Combine schemas and objects
    combined AS (
        SELECT * FROM schemas
        UNION ALL
        SELECT * FROM objects
    )

    -- Final output with tree-like formatting
    SELECT
        REPEAT('    ', level) ||
        CASE
            WHEN level = 1 THEN '└── :open_file_folder: '
            ELSE '    └── ' ||
                CASE object_type
                    WHEN 'TABLE' THEN ':bar_chart: '
                    WHEN 'VIEW' THEN ':eye: '
                    WHEN 'MATERIALIZED VIEW' THEN ':newspaper: '
                    WHEN 'FUNCTION' THEN ':zap: '
                    WHEN 'INDEX' THEN ':mag: '
                    WHEN 'SEQUENCE' THEN ':1234: '
                    WHEN 'FOREIGN TABLE' THEN ':globe_with_meridians: '
                    ELSE ''
                END
        END || object_name || ' (' || object_type || ')'
    FROM combined
    ORDER BY path;
END;
$$;

-- ============================================================================
-- SECAO DE DADOS (IDs originares preservados; upsert idempotente por PK)
-- ============================================================================

INSERT INTO public.users (id, name) VALUES
(1, 'Usuário Teste'),
(2, 'test 7366c83e-016e-4234-8d33-600050cfa1e2'),
(3, 'test 30e948ee-7d9e-49c8-8b3c-e7ea5985296e'),
(4, 'test a7c9ba5d-724b-4215-896b-e372779084fe'),
(5, 'test 6f1b981f-48c0-4c44-985a-9dcf1c5fa843'),
(3214964, 'user 3214964'),
(4588452, 'user 4588452'),
(7465833, 'user 7465833')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
INSERT INTO public.product (id, name, brand, model, category, avg_power_w, annual_energy_kwh, subcategory, standby_power_w, is_generic, avg_idle_energy_for_hour) VALUES
('00507739daa35b3eb0aaabcb8d37fabc'::uuid, 'Samsung QN48S90FAE', 'Samsung', 'QN48S90FAE', 'Eletrônicos', 84.90, 161.18, 'Televisão', NULL, false, NULL),
('0089f14381f55a62a72bd24a769040d8'::uuid, 'SKS SKSIT3601GE', 'SKS', 'SKSIT3601GE', 'Eletrodomésticos', 3.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('022b6365d7ce58d0b3cebe205f8a0151'::uuid, 'LG LSIS6338*E', 'LG', 'LSIS6338*E', 'Eletrodomésticos', 5.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('026c3fd5d313569482c018f77cc18eb6'::uuid, 'Ricoh N7100EA', 'Ricoh', 'N7100EA', 'Eletrônicos', 0.55, 0.60, 'Equipamento de imagem', NULL, false, NULL),
('040c45bfe2b756828fca1328a4a10a59'::uuid, 'SANSUI, AMZFAST LE-32V1', 'SANSUI, AMZFAST', 'LE-32V1', 'Eletrônicos', 34.76, 65.59, 'Televisão', NULL, false, NULL),
('0432290b55435ba29774eeff6f6361f9'::uuid, 'Sansui LE-32KA1', 'Sansui', 'LE-32KA1', 'Eletrônicos', 27.24, 51.59, 'Televisão', NULL, false, NULL),
('0495e15b09e95888a8dc53d3260fe7bc'::uuid, 'LG CBIH3613*E', 'LG', 'CBIH3613*E', 'Eletrodomésticos', 4.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('057e1aef5c075d898f378ed071c95edd'::uuid, 'Ricoh Pro C7210SX', 'Ricoh', 'Pro C7210SX', 'Eletrônicos', 151.50, 12.50, 'Equipamento de imagem', NULL, false, NULL),
('0590883427c8597faea3a3918717b3d8'::uuid, 'LG LTEL7337*E', 'LG', 'LTEL7337*E', 'Eletrodomésticos', 1.69, 195.00, 'Fogão/Forno', NULL, false, NULL),
('05ec492212135346bd057278b273d687'::uuid, 'HP Inc. HP DesignJet T1700 Printer Series', 'HP Inc.', 'HP DesignJet T1700 Printer Series', 'Eletrônicos', 0.27, 1.50, 'Equipamento de imagem', NULL, false, NULL),
('05ef8d9209e751a7a31f0a70383d54e5'::uuid, 'Sansui LE-43KA1', 'Sansui', 'LE-43KA1', 'Eletrônicos', 45.14, 82.16, 'Televisão', NULL, false, NULL),
('06542ca561a350fcafc6247ec40fa922'::uuid, 'ROWE ROWE ColorPress i10L', 'ROWE', 'ROWE ColorPress i10L', 'Eletrônicos', 1.81, 1.00, 'Equipamento de imagem', NULL, false, NULL),
('08ccda8194a45681ab6e89fdf067fa23'::uuid, 'Midea MC-8F72A2H333UL', 'Midea', 'MC-8F72A2H333UL', 'Eletrodomésticos', 2.51, 188.00, 'Fogão/Forno', NULL, false, NULL),
('0a07f9ce342f5692b8f111fb67f76bb9'::uuid, 'Samsung QN43QN90DAF', 'Samsung', 'QN43QN90DAF', 'Eletrônicos', 63.40, 143.60, 'Televisão', NULL, false, NULL),
('0c2d413d7ea457f6bd96da0dffdffdca'::uuid, 'KIP KIP 970', 'KIP', 'KIP 970', 'Eletrônicos', 3.38, 1.20, 'Equipamento de imagem', NULL, false, NULL),
('0ca0559b440258b2b3f4b585f221ea44'::uuid, 'Bosch HIS5657C', 'Bosch', 'HIS5657C', 'Eletrodomésticos', 4.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('0f11d15f0f7a59659123a465abfcc20a'::uuid, 'Servidor', NULL, NULL, 'Informática', 60.00, NULL, 'Servidor', NULL, false, NULL),
('0f86c22bd12257fea3b1481af0067470'::uuid, 'Oce ColorWave 3500', 'Oce', 'ColorWave 3500', 'Eletrônicos', 1.88, 5.80, 'Equipamento de imagem', NULL, false, NULL),
('112c12fb3b185c82b5ba82066cf8e5d1'::uuid, 'Samsung QN65S90FAF', 'Samsung', 'QN65S90FAF', 'Eletrônicos', 131.59, 246.40, 'Televisão', NULL, false, NULL),
('12c0aaecb61a500886b4d2e6175438de'::uuid, 'Oce ColorWave 700', 'Oce', 'ColorWave 700', 'Eletrônicos', 1.88, 5.80, 'Equipamento de imagem', NULL, false, NULL),
('12f975bdf4d75edc8df1251d45aacbaa'::uuid, 'Oce PlotWave 450 Printer', 'Oce', 'PlotWave 450 Printer', 'Eletrônicos', 1.03, 5.30, 'Equipamento de imagem', NULL, false, NULL),
('1466a541e9f850b3b1f920ec55f40446'::uuid, 'Samsung NSE80H63S*', 'Samsung', 'NSE80H63S*', 'Eletrodomésticos', 2.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('15fccfa9c9bc50a892aeaf0b991f3cc5'::uuid, 'Samsung QN55S84FAF', 'Samsung', 'QN55S84FAF', 'Eletrônicos', 86.03, 180.84, 'Televisão', NULL, false, NULL),
('165598ecf91a5e839694ba99032d16fc'::uuid, 'Konica Minolta AccurioPress C7100 + PF-712 [Printer System]', 'Konica Minolta', 'AccurioPress C7100 + PF-712 [Printer System]', 'Eletrônicos', 121.80, 21.41, 'Equipamento de imagem', NULL, false, NULL),
('17ec20331274587c9c0803f16e660662'::uuid, 'Frigobar', NULL, NULL, 'Eletrodomésticos', NULL, 185.34, 'Frigobar', NULL, false, NULL),
('1964ff9f600650eb9a744fbf0f8dc898'::uuid, 'LG CBIH3017*E', 'LG', 'CBIH3017*E', 'Eletrodomésticos', 6.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('1a699d1227d95a61978ad9c899b64095'::uuid, 'KIP KIP 7170', 'KIP', 'KIP 7170', 'Eletrônicos', 6.35, 1.10, 'Equipamento de imagem', NULL, false, NULL),
('1a9e5335c74b5fb2b1eb1aca99088c96'::uuid, 'HP Inc. HP DesignJet Z9 Printer Series', 'HP Inc.', 'HP DesignJet Z9 Printer Series', 'Eletrônicos', 0.34, 1.40, 'Equipamento de imagem', NULL, false, NULL),
('1b64b0209ffe5e97898a822b8a843fbe'::uuid, 'Sansui LE-50V1', 'Sansui', 'LE-50V1', 'Eletrônicos', 61.72, 134.85, 'Televisão', NULL, false, NULL),
('1cc7555c26465eb38c386101b2258f7c'::uuid, 'Konica Minolta AccurioPress C12000 + PF-712 [Printer System]', 'Konica Minolta', 'AccurioPress C12000 + PF-712 [Printer System]', 'Eletrônicos', 123.00, 35.52, 'Equipamento de imagem', NULL, false, NULL),
('1d1a7a942e875703a96e6b09d4dec65f'::uuid, 'Samsung CC70*36***', 'Samsung', 'CC70*36***', 'Eletrodomésticos', 7.81, 195.00, 'Fogão/Forno', NULL, false, NULL),
('1d5d77b8141856b6b60e73f694f6796d'::uuid, 'Loewe stellar 42', 'Loewe', 'stellar 42', 'Eletrônicos', 57.23, 106.67, 'Televisão', NULL, false, NULL),
('1da6006b968e577b9a6d1f3bf5809ef3'::uuid, 'LG LREN6323*E', 'LG', 'LREN6323*E', 'Eletrodomésticos', 1.42, 195.00, 'Fogão/Forno', NULL, false, NULL),
('1ed7bc7b27b45f6a8a6d3a2276f6f81e'::uuid, 'SCEPTRE X322BV-SRDD', 'SCEPTRE', 'X322BV-SRDD', 'Eletrônicos', 31.07, 59.76, 'Televisão', NULL, false, NULL),
('232c5fdc5d6554f895ce978575e63a23'::uuid, 'Bosch HIS8057C', 'Bosch', 'HIS8057C', 'Eletrodomésticos', 5.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('23542654676958e69a8ec8708d8238ff'::uuid, 'Chapa comercial', NULL, NULL, 'Cozinha', 1200.00, NULL, 'Chapa comercial', NULL, false, NULL),
('24103558b2ba5346a0a01f19c5925186'::uuid, 'Samsung QN55S95FAF', 'Samsung', 'QN55S95FAF', 'Eletrônicos', 113.60, 211.48, 'Televisão', NULL, false, NULL),
('2584720914065164a0adaf6131f7d864'::uuid, 'Samsung QN65QN90FAF', 'Samsung', 'QN65QN90FAF', 'Eletrônicos', 125.93, 234.67, 'Televisão', NULL, false, NULL),
('25954c683254581494fa4ddfd88b7ec1'::uuid, 'Oce PlotWave 550 Printer', 'Oce', 'PlotWave 550 Printer', 'Eletrônicos', 1.03, 5.30, 'Equipamento de imagem', NULL, false, NULL),
('25b30afae9875c61a808021efa553d51'::uuid, 'Canon plotWave T55', 'Canon', 'plotWave T55', 'Eletrônicos', 1.10, 0.00, 'Equipamento de imagem', NULL, false, NULL),
('25d7cd3a2c315f238d81d08fcaf73a21'::uuid, 'Samsung QN65QN90DAF', 'Samsung', 'QN65QN90DAF', 'Eletrônicos', 121.96, 265.90, 'Televisão', NULL, false, NULL),
('286b781640b6541686027e473314c4ee'::uuid, 'LG CBEW3013*E', 'LG', 'CBEW3013*E', 'Eletrodomésticos', 4.01, 195.00, 'Fogão/Forno', NULL, false, NULL),
('28d014e23ec65398941c773ad56d3f1d'::uuid, 'Fotile Electric Ranges', 'Fotile', 'Electric Ranges', 'Eletrodomésticos', 3.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('2acf7531e9ad5b7793986984f2bbd90a'::uuid, 'Samsung QN77S90FAF', 'Samsung', 'QN77S90FAF', 'Eletrônicos', 154.71, 286.50, 'Televisão', NULL, false, NULL),
('2b274b96205b5920bc5587e0957feb03'::uuid, 'LG LSIU6339*E', 'LG', 'LSIU6339*E', 'Eletrodomésticos', 6.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('2b89f6a8f6f0518a8a59455ae21d5d4a'::uuid, 'HP Inc. HP DesignJet T940 Printer Series', 'HP Inc.', 'HP DesignJet T940 Printer Series', 'Eletrônicos', 0.00, 1.50, 'Equipamento de imagem', NULL, false, NULL),
('2be495e8e08b53388d08f0533b33222d'::uuid, 'KIP KIP 7970', 'KIP', 'KIP 7970', 'Eletrônicos', 2.70, 1.60, 'Equipamento de imagem', NULL, false, NULL),
('2c70761295245bab9c7dc0b39d3dcc5f'::uuid, 'Samsung QN75QN95DAF', 'Samsung', 'QN75QN95DAF', 'Eletrônicos', 148.20, 320.70, 'Televisão', NULL, false, NULL),
('32bc03267d0a5a009753fd6f5f31723e'::uuid, 'Lâmpada', NULL, NULL, 'Iluminação', 123.90, NULL, 'Lâmpada', NULL, false, NULL),
('3480f3c0dbaf5f8cb0b7ad3c32c34232'::uuid, 'Canon colorWave T65', 'Canon', 'colorWave T65', 'Eletrônicos', 2.16, 0.00, 'Equipamento de imagem', NULL, false, NULL),
('34c4bdf532415d63b1b0d0ffc697d353'::uuid, 'LG CBEW3617*E', 'LG', 'CBEW3617*E', 'Eletrodomésticos', 4.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('37d947f088cc55f1be5bd59977d45976'::uuid, 'Freezer', NULL, NULL, 'Eletrodomésticos', 125.00, NULL, 'Freezer', NULL, false, NULL),
('397e87ba16585f568ecc620cc58f4ec8'::uuid, 'LG CBEW3613*E', 'LG', 'CBEW3613*E', 'Eletrodomésticos', 3.98, 195.00, 'Fogão/Forno', NULL, false, NULL),
('398a43af1a445a79b33652dcb433c510'::uuid, 'KIP KIP 7570P', 'KIP', 'KIP 7570P', 'Eletrônicos', 5.45, 1.30, 'Equipamento de imagem', NULL, false, NULL),
('3ac866d8035c5e2d86894a337aa291b9'::uuid, 'Bertazzoni PE304INDXV', 'Bertazzoni', 'PE304INDXV', 'Eletrodomésticos', 3.93, 192.00, 'Fogão/Forno', NULL, false, NULL),
('3b43cfec401a510697da5839ed3c341a'::uuid, 'Samsung QN55S90FAF', 'Samsung', 'QN55S90FAF', 'Eletrônicos', 98.73, 186.41, 'Televisão', NULL, false, NULL),
('3be42e9b38c65f68a91ad083695b3561'::uuid, 'Samsung QN65S95DAF', 'Samsung', 'QN65S95DAF', 'Eletrônicos', 127.39, 276.90, 'Televisão', NULL, false, NULL),
('3c00c3cfd99d5541a36a32da1ed90050'::uuid, 'HP Inc. HP HD Pro 2 42-in Scanner', 'HP Inc.', 'HP HD Pro 2 42-in Scanner', 'Eletrônicos', 0.43, 0.90, 'Equipamento de imagem', NULL, false, NULL),
('3c56d7551b375487a95a1882b9a6df57'::uuid, 'Fogão/Forno', NULL, NULL, 'Eletrodomésticos', 1290.00, NULL, 'Fogão/Forno', NULL, false, NULL),
('3d79140809055c39854e367cd899daac'::uuid, 'Sansui LE-50TA1', 'Sansui', 'LE-50TA1', 'Eletrônicos', 70.02, 129.24, 'Televisão', NULL, false, NULL),
('3f2e8ae81afd54ae81026a6106c6ec14'::uuid, 'Samsung NSE80H63X*', 'Samsung', 'NSE80H63X*', 'Eletrodomésticos', 2.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('3fee40b9326d5c85aaab0d9e11895077'::uuid, 'Samsung NZ30*G5332**', 'Samsung', 'NZ30*G5332**', 'Eletrodomésticos', 0.28, 195.00, 'Fogão/Forno', NULL, false, NULL),
('41aa9537e1595fd183c82bb33f1ae533'::uuid, 'LG LREN6325*E', 'LG', 'LREN6325*E', 'Eletrodomésticos', 2.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('41f74d3095965f8eaff8bb1edf261e33'::uuid, 'Konica Minolta AccurioPress C14000 + PF-713 [MFP System]', 'Konica Minolta', 'AccurioPress C14000 + PF-713 [MFP System]', 'Eletrônicos', 122.50, 40.06, 'Equipamento de imagem', NULL, false, NULL),
('4295a56557055c26b654a52617655612'::uuid, 'Sansui S40KAFT', 'Sansui', 'S40KAFT', 'Eletrônicos', 46.63, 85.55, 'Televisão', NULL, false, NULL),
('44b152237bec5d678facdb985e3e01c5'::uuid, 'Computador', NULL, NULL, 'Informática', 96.67, NULL, 'Computador', NULL, false, NULL),
('469854468ef95dcd9e46e170342d5263'::uuid, 'XITRIX XPN-DSA6560', 'XITRIX', 'XPN-DSA6560', 'Eletrônicos', 87.12, 161.35, 'Televisão', NULL, false, NULL),
('46e1d899655e5986b6081a52b5a6f729'::uuid, 'Sansui LE-40TA1', 'Sansui', 'LE-40TA1', 'Eletrônicos', 54.85, 103.50, 'Televisão', NULL, false, NULL),
('478ecea782795f62935131bedae16010'::uuid, 'Bertazzoni PE365INDXV', 'Bertazzoni', 'PE365INDXV', 'Eletrodomésticos', 2.90, 190.00, 'Fogão/Forno', NULL, false, NULL),
('491b713cf42e5bfb94f7fbd2cda30cfe'::uuid, 'Sansui LE-55VO', 'Sansui', 'LE-55VO', 'Eletrônicos', 86.67, 160.50, 'Televisão', NULL, false, NULL),
('4a820434fece56bfa9a82db7b9bec86b'::uuid, 'Bertazzoni MAS365INMBG', 'Bertazzoni', 'MAS365INMBG', 'Eletrodomésticos', 1.00, 187.00, 'Fogão/Forno', NULL, false, NULL),
('4b5d4d7fb5d758e5b92d7c44824c9417'::uuid, 'Midea MC-9V96E0H378UL', 'Midea', 'MC-9V96E0H378UL', 'Eletrodomésticos', 3.37, 188.00, 'Fogão/Forno', NULL, false, NULL),
('4c6b41a0920e59db88a8b404ba418996'::uuid, 'Canon colorWave T60', 'Canon', 'colorWave T60', 'Eletrônicos', 2.09, 0.00, 'Equipamento de imagem', NULL, false, NULL),
('51f9ec7d2ab35245a7ef31b47c6e478c'::uuid, 'LG CBIU3639*E', 'LG', 'CBIU3639*E', 'Eletrodomésticos', 5.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('52e886c51b4750fca53c75bac5b14c4f'::uuid, 'LG LSIL6336*E', 'LG', 'LSIL6336*E', 'Eletrodomésticos', 5.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('52fe589531e65c2e87009450ca4c927b'::uuid, 'Oce PlotWave 345  Printer', 'Oce', 'PlotWave 345  Printer', 'Eletrônicos', 1.21, 5.30, 'Equipamento de imagem', NULL, false, NULL),
('535a0ca1288d52bbab402869cf9ad54f'::uuid, 'Ricoh N7100E', 'Ricoh', 'N7100E', 'Eletrônicos', 0.55, 0.60, 'Equipamento de imagem', NULL, false, NULL),
('550739cb684653e3a581f67ddc647000'::uuid, 'Samsung NE63F6711**', 'Samsung', 'NE63F6711**', 'Eletrodomésticos', 1.89, 195.00, 'Fogão/Forno', NULL, false, NULL),
('56c48e6385c656f2bfb557041e6c6444'::uuid, 'Fujitsu N7100E', 'Fujitsu', 'N7100E', 'Eletrônicos', 0.55, 0.60, 'Equipamento de imagem', NULL, false, NULL),
('58824b0f912754cf93e596fb7469b4b5'::uuid, 'Samsung QN115QN90FF', 'Samsung', 'QN115QN90FF', 'Eletrônicos', 343.50, 631.05, 'Televisão', NULL, false, NULL),
('58989716d4895bea80538dad85e3b622'::uuid, 'Bertazzoni MAS304INMBG', 'Bertazzoni', 'MAS304INMBG', 'Eletrodomésticos', 1.00, 188.00, 'Fogão/Forno', NULL, false, NULL),
('5eeb836dc46f5df5b715b47775685e7a'::uuid, 'LG LCE3010SBE', 'LG', 'LCE3010SBE', 'Eletrodomésticos', 4.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('5f2b90a7df455ef8833650086d82775b'::uuid, 'Sansui LE-43V1', 'Sansui', 'LE-43V1', 'Eletrônicos', 64.06, 118.81, 'Televisão', NULL, false, NULL),
('60c5a0f3492e5178aa66911ba39b8d87'::uuid, 'Samsung QN65S95HAF', 'Samsung', 'QN65S95HAF', 'Eletrônicos', 125.24, 234.00, 'Televisão', NULL, false, NULL),
('61743f68ebae54afaf78aaac61aed732'::uuid, 'KIP KIP 7570M', 'KIP', 'KIP 7570M', 'Eletrônicos', 5.45, 1.30, 'Equipamento de imagem', NULL, false, NULL),
('623d6ab8c54350eba2187cb5dafbe2f3'::uuid, 'Konica Minolta AccurioPress C14000 + PF-712 [Printer System]', 'Konica Minolta', 'AccurioPress C14000 + PF-712 [Printer System]', 'Eletrônicos', 122.50, 39.52, 'Equipamento de imagem', NULL, false, NULL),
('644347d68f2f5d5faabc7243a34c5de2'::uuid, 'Samsung QN77S95DAF', 'Samsung', 'QN77S95DAF', 'Eletrônicos', 167.33, 360.80, 'Televisão', NULL, false, NULL),
('65efac4e536d528690c3279e3231f2b5'::uuid, 'Canon colorWave T65', 'Canon', 'colorWave T65', 'Eletrônicos', 2.09, 4.40, 'Equipamento de imagem', NULL, false, NULL),
('66669dff67e35b0091166fcff51d66e5'::uuid, 'LG LSIL633T*E', 'LG', 'LSIL633T*E', 'Eletrodomésticos', 3.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('69bbfce4ea945a48b8f369e670ca7c71'::uuid, 'LG LSIL633C*E', 'LG', 'LSIL633C*E', 'Eletrodomésticos', 3.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('69df89ed56f657c6b2d1c4eaac40daaa'::uuid, 'LG LSEL633C*E', 'LG', 'LSEL633C*E', 'Eletrodomésticos', 1.42, 195.00, 'Fogão/Forno', NULL, false, NULL),
('6b439300324c5b9ea85c4721801dc739'::uuid, 'Sansui LE-55V4', 'Sansui', 'LE-55V4', 'Eletrônicos', 72.52, 134.85, 'Televisão', NULL, false, NULL),
('6f38cde7069c510b8689c119e57cb470'::uuid, 'Samsung NZ30*G6332**', 'Samsung', 'NZ30*G6332**', 'Eletrodomésticos', 2.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('6f44b7227cc051a682040ed72691b38b'::uuid, 'Fornalha', NULL, NULL, 'Eletrodomésticos', 5400.00, NULL, 'Fornalha', NULL, false, NULL),
('6fbdf19d1d36573ca046f78fad2dac0e'::uuid, 'XITRIX XPN-DSA3250', 'XITRIX', 'XPN-DSA3250', 'Eletrônicos', 34.40, 64.37, 'Televisão', NULL, false, NULL),
('716745a9712e5f8c9d3ee809fe240b42'::uuid, 'Não categorizado', NULL, NULL, 'Outros', 913.03, NULL, 'Não categorizado', NULL, false, NULL),
('72484c389ebf546ebc9b15dc84a0e941'::uuid, 'LG LTIS7338*E', 'LG', 'LTIS7338*E', 'Eletrodomésticos', 6.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('72caa0db5134510a9e05ab67f90a2a5c'::uuid, 'SANSUI. LE-85TE1', 'SANSUI.', 'LE-85TE1', 'Eletrônicos', 188.80, 347.06, 'Televisão', NULL, false, NULL),
('72d13f8c0e395dcd9ef604576319057d'::uuid, 'Bertazzoni MAS365INMXG', 'Bertazzoni', 'MAS365INMXG', 'Eletrodomésticos', 1.00, 187.00, 'Fogão/Forno', NULL, false, NULL),
('72ed47db2c0853fbb1b52d2e740c0b91'::uuid, 'ROWE ROWE ColorPress i8L with ROWE Scan 450i 36', 'ROWE', 'ROWE ColorPress i8L with ROWE Scan 450i 36', 'Eletrônicos', 1.84, 1.00, 'Equipamento de imagem', NULL, false, NULL),
('73ac782c22925654a064a469f1f67573'::uuid, 'HP Inc. HP SD Pro 2 44-in Scanner', 'HP Inc.', 'HP SD Pro 2 44-in Scanner', 'Eletrônicos', 0.62, 0.90, 'Equipamento de imagem', NULL, false, NULL),
('754ac400de96524eab122e20d9a0ad3d'::uuid, 'Oce PlotWave 345  Multifunction Express', 'Oce', 'PlotWave 345  Multifunction Express', 'Eletrônicos', 1.21, 5.30, 'Equipamento de imagem', NULL, false, NULL),
('75be5107a58d58578274e387fec09027'::uuid, 'LG LREL6325*H', 'LG', 'LREL6325*H', 'Eletrodomésticos', 2.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('75cb751c51605c509221e2997c8dbef2'::uuid, 'Midea MC-8F72E1H333UL-F', 'Midea', 'MC-8F72E1H333UL-F', 'Eletrodomésticos', 3.44, 188.00, 'Fogão/Forno', NULL, false, NULL),
('7648a4b230415526beb577fb9b2e214a'::uuid, 'Oce PlotWave 550 Multifunction Express', 'Oce', 'PlotWave 550 Multifunction Express', 'Eletrônicos', 1.03, 5.30, 'Equipamento de imagem', NULL, false, NULL),
('7699227a18055e96884163cc787c009d'::uuid, 'Samsung QN50QN90DAF', 'Samsung', 'QN50QN90DAF', 'Eletrônicos', 74.27, 165.50, 'Televisão', NULL, false, NULL),
('76fd410d708a50649815e604be27d817'::uuid, 'SANSUI, AMZFAST LE-24TA1', 'SANSUI, AMZFAST', 'LE-24TA1', 'Eletrônicos', 24.32, 46.73, 'Televisão', NULL, false, NULL),
('780845d2b0975576812c7e4f3a667900'::uuid, 'Purificador de ar', NULL, NULL, 'Climatização', 50.00, NULL, 'Purificador de ar', NULL, false, NULL),
('792deb9b9879546c92f0e9fdc728d271'::uuid, 'Canon plotWave T35', 'Canon', 'plotWave T35', 'Eletrônicos', 1.30, 0.00, 'Equipamento de imagem', NULL, false, NULL),
('7a5c1b731b5b5d0791903164847cc1bc'::uuid, 'LG LSEL6335*E', 'LG', 'LSEL6335*E', 'Eletrodomésticos', 2.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('7b6951159a285a71b4f95b308b3232ed'::uuid, 'LG CBIU3039*E', 'LG', 'CBIU3039*E', 'Eletrodomésticos', 6.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('7ba6e680add05492a260653baa7819af'::uuid, 'Oce PlotWave 365  Multifunction Express', 'Oce', 'PlotWave 365  Multifunction Express', 'Eletrônicos', 1.21, 5.30, 'Equipamento de imagem', NULL, false, NULL),
('7dfae4efbc425529a7d3c4caf47f8b7e'::uuid, 'Konica Minolta AccurioPress C12000 + PF-713 [MFP System]', 'Konica Minolta', 'AccurioPress C12000 + PF-713 [MFP System]', 'Eletrônicos', 123.00, 35.27, 'Equipamento de imagem', NULL, false, NULL),
('7ec1c024e3da5ab9aea38f6c7ae75b2d'::uuid, 'Konica Minolta AccurioPress C4080', 'Konica Minolta', 'AccurioPress C4080', 'Eletrônicos', 33.10, 8.60, 'Equipamento de imagem', NULL, false, NULL),
('80a78bc489dc543eb26d846042a89eaa'::uuid, 'Konica Minolta AccurioPress C4070', 'Konica Minolta', 'AccurioPress C4070', 'Eletrônicos', 33.10, 8.60, 'Equipamento de imagem', NULL, false, NULL),
('8158deed5e4c55db9f8fcfbedbe6c2eb'::uuid, 'Bomba de calor', NULL, NULL, 'Climatização', 2387.50, NULL, 'Bomba de calor', NULL, false, NULL),
('8268f81f8f845d7f86897ab06a834cf2'::uuid, 'Sansui S32KAHT', 'Sansui', 'S32KAHT', 'Eletrônicos', 30.15, 60.92, 'Televisão', NULL, false, NULL),
('84332e17d11658259b7fba67abc8795d'::uuid, 'LG LSEL6333*H', 'LG', 'LSEL6333*H', 'Eletrodomésticos', 1.42, 195.00, 'Fogão/Forno', NULL, false, NULL),
('850975ad188e5b9ebec28268d0638e4f'::uuid, 'Canon plotWave T75', 'Canon', 'plotWave T75', 'Eletrônicos', 1.40, 0.00, 'Equipamento de imagem', NULL, false, NULL),
('85331b117dc054339a28a48494b5b4d4'::uuid, 'KIP KIP 660', 'KIP', 'KIP 660', 'Eletrônicos', 3.20, 0.80, 'Equipamento de imagem', NULL, false, NULL),
('8655051e51ac5401a349e74e54829456'::uuid, 'LG LCE3610SBE', 'LG', 'LCE3610SBE', 'Eletrodomésticos', 4.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('86bf58cd2ae65ac9ac30c98328a3ce70'::uuid, 'Samsung QN65S85FAF', 'Samsung', 'QN65S85FAF', 'Eletrônicos', 114.17, 213.90, 'Televisão', NULL, false, NULL),
('86e66be03fef5d62981a94ba2dffca35'::uuid, 'LG CBIH3013*E', 'LG', 'CBIH3013*E', 'Eletrodomésticos', 4.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('8959217fb116566ba5cf28ce63fffcb5'::uuid, 'Oce ColorWave 3700', 'Oce', 'ColorWave 3700', 'Eletrônicos', 1.88, 5.80, 'Equipamento de imagem', NULL, false, NULL),
('8a7dd62c15085e26a4dbbc52e290b922'::uuid, 'Samsung QN55S95DAF', 'Samsung', 'QN55S95DAF', 'Eletrônicos', 112.43, 245.80, 'Televisão', NULL, false, NULL),
('8b918d8aefd6580abf218bee9c60c59d'::uuid, 'LG LSIL6332*E', 'LG', 'LSIL6332*E', 'Eletrodomésticos', 3.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('90cac3ad6e545fd2aa84c8ec92dc05be'::uuid, 'Bertazzoni MAS304INMXG', 'Bertazzoni', 'MAS304INMXG', 'Eletrodomésticos', 1.00, 188.00, 'Fogão/Forno', NULL, false, NULL),
('92c35c63b9f85dceac476cf6530377d6'::uuid, 'LG LSIL6334*E', 'LG', 'LSIL6334*E', 'Eletrodomésticos', 4.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('942ea48ab8425f86971149d04907437f'::uuid, 'Samsung QN98QN90FAF', 'Samsung', 'QN98QN90FAF', 'Eletrônicos', 193.08, 357.22, 'Televisão', NULL, false, NULL),
('98327b1f0cf251129041fc0c80371de2'::uuid, 'Samsung QN55QN90FAF', 'Samsung', 'QN55QN90FAF', 'Eletrônicos', 102.38, 193.09, 'Televisão', NULL, false, NULL),
('99a4363d9c785109b31c25b52599a14c'::uuid, 'Samsung QN43QN90FAF', 'Samsung', 'QN43QN90FAF', 'Eletrônicos', 62.80, 118.79, 'Televisão', NULL, false, NULL),
('9ad3b9436d275658b4e8d6222419157d'::uuid, 'Canon colorWave T60', 'Canon', 'colorWave T60', 'Eletrônicos', 2.16, 0.00, 'Equipamento de imagem', NULL, false, NULL),
('9b4546ceefb1501a87604b246e1161a1'::uuid, 'Canon plotWave T50', 'Canon', 'plotWave T50', 'Eletrônicos', 1.10, 0.00, 'Equipamento de imagem', NULL, false, NULL),
('9c018830f21859ceb553d52f21cd9e5f'::uuid, 'Oce ColorWave 3500', 'Oce', 'ColorWave 3500', 'Eletrônicos', 1.88, 5.80, 'Equipamento de imagem', NULL, false, NULL),
('9ca1dc12e02d5a8b96945d50e748c705'::uuid, 'LG CBIS3018*E', 'LG', 'CBIS3018*E', 'Eletrodomésticos', 6.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('9d31cc9bd9455e7db35ff2c98a44e8f0'::uuid, 'Samsung NE63D6511**', 'Samsung', 'NE63D6511**', 'Eletrodomésticos', 1.90, 195.00, 'Fogão/Forno', NULL, false, NULL),
('9d505e5c924852b8b0c30a9e0f375214'::uuid, 'Samsung QN77S90DAF', 'Samsung', 'QN77S90DAF', 'Eletrônicos', 160.93, 297.90, 'Televisão', NULL, false, NULL),
('9db3cac31ea154f497adcc32e66146b9'::uuid, 'Canon plotWave T30', 'Canon', 'plotWave T30', 'Eletrônicos', 1.14, 0.00, 'Equipamento de imagem', NULL, false, NULL),
('9e1bfda340815a0a8d0bcb371273dbf7'::uuid, 'Samsung NSE90H63S*', 'Samsung', 'NSE90H63S*', 'Eletrodomésticos', 1.80, 195.00, 'Fogão/Forno', NULL, false, NULL),
('a0b349921045570097b6983b831cdebe'::uuid, 'LG LRIN6323*E', 'LG', 'LRIN6323*E', 'Eletrodomésticos', 4.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('a0f8db11e41b50dd9ecaffba4b470834'::uuid, 'Sansui LE-50VA1', 'Sansui', 'LE-50VA1', 'Eletrônicos', 68.37, 126.94, 'Televisão', NULL, false, NULL),
('a22c887ac89b5833bb2f3fa8b4249f28'::uuid, 'LG LSIU6338*E', 'LG', 'LSIU6338*E', 'Eletrodomésticos', 6.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('a5d18fa70f00510088a40443a19993df'::uuid, 'Ricoh IM C300F', 'Ricoh', 'IM C300F', 'Eletrônicos', 0.00, 0.37, 'Equipamento de imagem', NULL, false, NULL),
('a7dbed2ca1225472a05fb7a327f0d554'::uuid, 'LG CBIS3618*E', 'LG', 'CBIS3618*E', 'Eletrodomésticos', 5.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('a82bf63bf7f6544b8e7ad3409dd90600'::uuid, 'Konica Minolta AccurioPress C7100 + PF-713 [MFP System]', 'Konica Minolta', 'AccurioPress C7100 + PF-713 [MFP System]', 'Eletrônicos', 121.80, 21.58, 'Equipamento de imagem', NULL, false, NULL),
('a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'Congelador', NULL, NULL, 'Eletrodomésticos', NULL, 476.61, 'Congelador', NULL, false, NULL),
('a8c76087a83358afb0b9d5edc22fa793'::uuid, 'Samsung QN55S95HAF', 'Samsung', 'QN55S95HAF', 'Eletrônicos', 107.58, 202.00, 'Televisão', NULL, false, NULL),
('a9ff9dd4285b5fa4bd5be8da217cfe06'::uuid, 'Sansui LE-75VH5', 'Sansui', 'LE-75VH5', 'Eletrônicos', 119.51, 220.19, 'Televisão', NULL, false, NULL),
('aa9f849988a25bdfbee89da48f44f448'::uuid, 'Ikea MC-8F72A2H333UL', 'Ikea', 'MC-8F72A2H333UL', 'Eletrodomésticos', 2.75, 188.00, 'Fogão/Forno', NULL, false, NULL),
('ad2b852ac97d575696c8a74f48fcd962'::uuid, 'Samsung NSE70H63S*', 'Samsung', 'NSE70H63S*', 'Eletrodomésticos', 1.97, 195.00, 'Fogão/Forno', NULL, false, NULL),
('ae0fb2e7972c5cb493fe92956b953dcb'::uuid, 'Samsung QN85QN90DAF', 'Samsung', 'QN85QN90DAF', 'Eletrônicos', 181.05, 390.00, 'Televisão', NULL, false, NULL),
('ae19a0cb1ceb518681e315b70b292c89'::uuid, 'Konica Minolta AccurioPress C7090 + PF-713 [MFP System]', 'Konica Minolta', 'AccurioPress C7090 + PF-713 [MFP System]', 'Eletrônicos', 121.80, 21.58, 'Equipamento de imagem', NULL, false, NULL),
('af2b9cf5beb45c49a89aef32be61c93d'::uuid, 'LOEWE. stellar 65', 'LOEWE.', 'stellar 65', 'Eletrônicos', 84.55, 157.08, 'Televisão', NULL, false, NULL),
('b015d6f583ba5c76907d8467b0523fc8'::uuid, 'ROWE ROWE ColorPress i10L with ROWE Scan 450i 36', 'ROWE', 'ROWE ColorPress i10L with ROWE Scan 450i 36', 'Eletrônicos', 1.84, 1.00, 'Equipamento de imagem', NULL, false, NULL),
('b03224d6390e55a59ea893d8f62bc65c'::uuid, 'Geladeira', NULL, NULL, 'Eletrodomésticos', 150.00, NULL, 'Geladeira', NULL, false, NULL),
('b045993691e0500a88e2e1b89ff04b60'::uuid, 'LG LSEL6333*E', 'LG', 'LSEL6333*E', 'Eletrodomésticos', 1.42, 195.00, 'Fogão/Forno', NULL, false, NULL),
('b04ab1927d35522ea8fe0b7413e719d9'::uuid, 'Equipamento de imagem', NULL, NULL, 'Eletrônicos', 325.00, NULL, 'Equipamento de imagem', NULL, false, NULL),
('b070f9d74dc75c9b8dbef4ce75969832'::uuid, 'Oce PlotWave 450 Multifunction Express', 'Oce', 'PlotWave 450 Multifunction Express', 'Eletrônicos', 1.03, 5.30, 'Equipamento de imagem', NULL, false, NULL),
('b0a058f4cfe75882a3550c0298f5ec68'::uuid, 'Fritadeira comercial', NULL, NULL, 'Cozinha', 1600.00, NULL, 'Fritadeira comercial', NULL, false, NULL),
('b2e1745891eb5288bcfd1f57bbd66fe9'::uuid, 'Ikea MC-8F72A2H385UL', 'Ikea', 'MC-8F72A2H385UL', 'Eletrodomésticos', 2.65, 175.00, 'Fogão/Forno', NULL, false, NULL),
('b338bc06038256449bd873886bdeab17'::uuid, 'Samsung NZ36*G6432**', 'Samsung', 'NZ36*G6432**', 'Eletrodomésticos', 3.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('b44d4b8a0c4d509bb3fb7a7799901f66'::uuid, 'Sansui LE-65KA1', 'Sansui', 'LE-65KA1', 'Eletrônicos', 102.25, 189.00, 'Televisão', NULL, false, NULL),
('b46885737e265b4584366705198bd844'::uuid, 'Sansui LE-24T1', 'Sansui', 'LE-24T1', 'Eletrônicos', 23.65, 45.20, 'Televisão', NULL, false, NULL),
('b474827c81b256d88508786ca0b7c60a'::uuid, 'Cafeteira comercial', NULL, NULL, 'Cozinha', 900.00, NULL, 'Cafeteira comercial', NULL, false, NULL),
('b47ad1ec56985ebc860da10293c8b9a2'::uuid, 'Samsung QN85QN90FAF', 'Samsung', 'QN85QN90FAF', 'Eletrônicos', 186.31, 344.87, 'Televisão', NULL, false, NULL),
('b4a8463f850c568a8f012406ce6adfbe'::uuid, 'LG LSEL6330*E', 'LG', 'LSEL6330*E', 'Eletrodomésticos', 0.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('b5986bfa1c155ce7a5dac1cbbe5055d3'::uuid, 'ROWE ROWE ColorPress i8L', 'ROWE', 'ROWE ColorPress i8L', 'Eletrônicos', 1.81, 1.00, 'Equipamento de imagem', NULL, false, NULL),
('b5b62285b42458bb94f472fb166ccd76'::uuid, 'Ricoh Pro C7210X', 'Ricoh', 'Pro C7210X', 'Eletrônicos', 151.50, 12.20, 'Equipamento de imagem', NULL, false, NULL),
('b6d71548d5535c22bb06acaae1ee29f3'::uuid, 'Samsung NSE6D*8702**', 'Samsung', 'NSE6D*8702**', 'Eletrodomésticos', 1.37, 195.00, 'Fogão/Forno', NULL, false, NULL),
('b8163f45172a582ca2e51df55797d07c'::uuid, 'Oce Oce VarioPrint 6330', 'Oce', 'Oce VarioPrint 6330', 'Eletrônicos', 44.20, 120.90, 'Equipamento de imagem', NULL, false, NULL),
('b833c7d7cc495b119be3f541aa8ec840'::uuid, 'Ventilador/Exaustor', NULL, NULL, 'Climatização', 154.17, NULL, 'Ventilador/Exaustor', NULL, false, NULL),
('b869eeb23e7951a384d69c1764e31cba'::uuid, 'RCA 65D1', 'RCA', '65D1', 'Eletrônicos', 117.69, 216.87, 'Televisão', NULL, false, NULL),
('b95fc09a9d7d58eeb28b57badd772f8a'::uuid, 'Samsung QN83S85FAE', 'Samsung', 'QN83S85FAE', 'Eletrônicos', 167.65, 312.20, 'Televisão', NULL, false, NULL),
('b9d0e8a295d95ec9916ba71cc0771ea8'::uuid, 'Bomba de piscina', NULL, NULL, 'Eletrodomésticos', 1100.00, NULL, 'Bomba de piscina', NULL, false, NULL),
('bc17233277cf56debd4e61ad0cfd7f06'::uuid, 'LOEWE. stellar 55', 'LOEWE.', 'stellar 55', 'Eletrônicos', 64.42, 120.34, 'Televisão', NULL, false, NULL),
('bc738d2bc4f651c1a25c534c526c2709'::uuid, 'Samsung NZ36*G5332**', 'Samsung', 'NZ36*G5332**', 'Eletrodomésticos', 0.28, 195.00, 'Fogão/Forno', NULL, false, NULL),
('bc82b8c1d3d355c080993d7a9b7b5b4c'::uuid, 'Sansui LE-32VA1', 'Sansui', 'LE-32VA1', 'Eletrônicos', 35.64, 67.19, 'Televisão', NULL, false, NULL),
('bcb6dcd6173854bba6d9068c6e0a3684'::uuid, 'ROWE ROWE ColorPress i6', 'ROWE', 'ROWE ColorPress i6', 'Eletrônicos', 1.81, 1.00, 'Equipamento de imagem', NULL, false, NULL),
('bde6956a885c51a7a72c79792e119c56'::uuid, 'Konica Minolta AccurioPrint C4065', 'Konica Minolta', 'AccurioPrint C4065', 'Eletrônicos', 33.10, 8.60, 'Equipamento de imagem', NULL, false, NULL),
('be389ae923875726a7dffeeda9b2e4c4'::uuid, 'Aquecedor de água', NULL, NULL, 'Eletrodomésticos', 11000.00, NULL, 'Aquecedor de água', NULL, false, NULL),
('bf51a0f3e53259f5a02537e7312c6919'::uuid, 'Sansui LE-75VA1', 'Sansui', 'LE-75VA1', 'Eletrônicos', 148.56, 273.48, 'Televisão', NULL, false, NULL),
('c0370d524de75c549a84f38230f1ef98'::uuid, 'Lava-louças', NULL, NULL, 'Eletrodomésticos', 1800.00, NULL, 'Lava-louças', NULL, false, NULL),
('c1636d2e371a5381ad30794bbb4e46d5'::uuid, 'Samsung QN77S95FAF', 'Samsung', 'QN77S95FAF', 'Eletrônicos', 169.04, 314.05, 'Televisão', NULL, false, NULL),
('c24aa614edf3539e8f99bfc2b0a8a315'::uuid, 'Sansui LE-55TA1', 'Sansui', 'LE-55TA1', 'Eletrônicos', 79.50, 147.00, 'Televisão', NULL, false, NULL),
('c3f532c228195761b7fb8daa4c93ff2f'::uuid, 'Canon plotWave T30', 'Canon', 'plotWave T30', 'Eletrônicos', 1.30, 0.00, 'Equipamento de imagem', NULL, false, NULL),
('c523d0b0bf765e64b6006e8c5195d7b0'::uuid, 'SKS SKSIR360IS', 'SKS', 'SKSIR360IS', 'Eletrodomésticos', 4.39, 189.00, 'Fogão/Forno', NULL, false, NULL),
('c7cb9f2992aa5e679a52f35750f83c39'::uuid, 'XITRIX XPN-DSA5850', 'XITRIX', 'XPN-DSA5850', 'Eletrônicos', 100.90, 186.15, 'Televisão', NULL, false, NULL),
('c7d673cca0e85beaa751ffe376ea9a58'::uuid, 'Sansui LE-24VA1', 'Sansui', 'LE-24VA1', 'Eletrônicos', 23.84, 45.59, 'Televisão', NULL, false, NULL),
('c8714ebab068559e80c1d957e3407fc6'::uuid, 'Samsung NE63F6511**', 'Samsung', 'NE63F6511**', 'Eletrodomésticos', 1.90, 195.00, 'Fogão/Forno', NULL, false, NULL),
('c878b4c9063c5247ba6c542a4399077e'::uuid, 'LG LREN6321*E', 'LG', 'LREN6321*E', 'Eletrodomésticos', 1.42, 195.00, 'Fogão/Forno', NULL, false, NULL),
('c87d07f8f3445dac8be66a3740043284'::uuid, 'Samsung NSE6D*8502**', 'Samsung', 'NSE6D*8502**', 'Eletrodomésticos', 1.37, 195.00, 'Fogão/Forno', NULL, false, NULL),
('cbb00d686406538d80c1ad7607813745'::uuid, 'Oce Oce VarioPrint 6270', 'Oce', 'Oce VarioPrint 6270', 'Eletrônicos', 44.20, 106.30, 'Equipamento de imagem', NULL, false, NULL),
('cc3d781e541f565da95eacea61e5803a'::uuid, 'Fujitsu N7100EA', 'Fujitsu', 'N7100EA', 'Eletrônicos', 0.55, 0.60, 'Equipamento de imagem', NULL, false, NULL),
('cd2f3de5234457029b72febbf0386017'::uuid, 'Samsung QN83S95FAE', 'Samsung', 'QN83S95FAE', 'Eletrônicos', 215.22, 399.01, 'Televisão', NULL, false, NULL),
('cd2f57c4936755ecbebe0240ed495f0d'::uuid, 'LG LSEL6335LE', 'LG', 'LSEL6335LE', 'Eletrodomésticos', 2.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('cd999336731d59d8938138a29832df31'::uuid, 'Canon plotWave T75', 'Canon', 'plotWave T75', 'Eletrônicos', 1.10, 0.00, 'Equipamento de imagem', NULL, false, NULL),
('ce7d295c53985881843403d1a7b27c89'::uuid, 'Oce ColorWave 700', 'Oce', 'ColorWave 700', 'Eletrônicos', 1.88, 5.80, 'Equipamento de imagem', NULL, false, NULL),
('d0459dccfddc58018583afa7c762a93b'::uuid, 'Samsung QN75QN90DAF', 'Samsung', 'QN75QN90DAF', 'Eletrônicos', 141.39, 307.88, 'Televisão', NULL, false, NULL),
('d0726a6411b75a6694e6634de0697ae8'::uuid, 'Ricoh Pro C7200X', 'Ricoh', 'Pro C7200X', 'Eletrônicos', 151.50, 11.20, 'Equipamento de imagem', NULL, false, NULL),
('d115650ec12d53cf934bb0e61e63d7fe'::uuid, 'XITRIX XPN-DSA8650', 'XITRIX', 'XPN-DSA8650', 'Eletrônicos', 166.52, 306.05, 'Televisão', NULL, false, NULL),
('d5628503f4165c9b9c3b5504261145d1'::uuid, 'Canon plotWave T50', 'Canon', 'plotWave T50', 'Eletrônicos', 1.40, 0.00, 'Equipamento de imagem', NULL, false, NULL),
('d6e5d34f636257aeabb286ba6fa34429'::uuid, 'Canon plotWave T35', 'Canon', 'plotWave T35', 'Eletrônicos', 1.14, 0.00, 'Equipamento de imagem', NULL, false, NULL),
('d7c7e78f92cd5f77ae3f35d69ceebffe'::uuid, 'LG LDEL7324*E', 'LG', 'LDEL7324*E', 'Eletrodomésticos', 2.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('d7cae181c1115587ab368405f3a63a9d'::uuid, 'Oce ColorWave 500', 'Oce', 'ColorWave 500', 'Eletrônicos', 1.88, 5.80, 'Equipamento de imagem', NULL, false, NULL),
('d8ca8c3931f25c429f716765892d24ac'::uuid, 'Secadora', NULL, NULL, 'Eletrodomésticos', 1600.00, NULL, 'Secadora', NULL, false, NULL),
('d9b753a67bd355f191941e47c1d6c9f8'::uuid, 'Dacor DOP30*940I*', 'Dacor', 'DOP30*940I*', 'Eletrodomésticos', 3.12, 195.00, 'Fogão/Forno', NULL, false, NULL),
('d9cbfd1f2cc75d0a9d295bd3d2a64eb4'::uuid, 'Konica Minolta AccurioPress C7090 + PF-712 [Printer System]', 'Konica Minolta', 'AccurioPress C7090 + PF-712 [Printer System]', 'Eletrônicos', 121.80, 21.41, 'Equipamento de imagem', NULL, false, NULL),
('dde4c3b75f5b509aa9c57db053f53eb1'::uuid, 'HP Inc. HP DesignJet Z6 Printer Series', 'HP Inc.', 'HP DesignJet Z6 Printer Series', 'Eletrônicos', 0.34, 1.40, 'Equipamento de imagem', NULL, false, NULL),
('dfefd20607fc5770a27e052d83bab7a1'::uuid, 'Samsung QN50QN90FAF', 'Samsung', 'QN50QN90FAF', 'Eletrônicos', 75.76, 143.81, 'Televisão', NULL, false, NULL),
('e1b404de8be45a9aa0fedb911c733f6a'::uuid, 'Samsung QN75QN90CAF', 'Samsung', 'QN75QN90CAF', 'Eletrônicos', 138.97, 183.80, 'Televisão', NULL, false, NULL),
('e242492b872e5980be9fb751015964ff'::uuid, 'Samsung QN65S90DAF', 'Samsung', 'QN65S90DAF', 'Eletrônicos', 134.53, 251.10, 'Televisão', NULL, false, NULL),
('e28256e14ab5580b857382a50be52c05'::uuid, 'Samsung QN65QN95DAF', 'Samsung', 'QN65QN95DAF', 'Eletrônicos', 125.73, 275.00, 'Televisão', NULL, false, NULL),
('e2ce2a47497353edabc3a494cdb96397'::uuid, 'Samsung NSE6D*8550**', 'Samsung', 'NSE6D*8550**', 'Eletrodomésticos', 1.37, 195.00, 'Fogão/Forno', NULL, false, NULL),
('e2cf6c9b1a175c879d63e92295a51b3b'::uuid, 'LG LSEL6337*E', 'LG', 'LSEL6337*E', 'Eletrodomésticos', 1.69, 195.00, 'Fogão/Forno', NULL, false, NULL),
('e30e84bfb86257288ad3c6c70a5e50d4'::uuid, 'Desumidificador', NULL, NULL, 'Eletrodomésticos', 500.00, NULL, 'Desumidificador', NULL, false, NULL),
('e4a95e61b8d7557cb8e22c6509d9f23d'::uuid, 'Loewe stellar 48', 'Loewe', 'stellar 48', 'Eletrônicos', 73.81, 136.92, 'Televisão', NULL, false, NULL),
('e4bf7c937db058b5972df7882fc7b082'::uuid, 'KIP KIP 650', 'KIP', 'KIP 650', 'Eletrônicos', 3.20, 0.80, 'Equipamento de imagem', NULL, false, NULL),
('e504dba66b845660827d7743c9e018ca'::uuid, 'Samsung NE63D6711**', 'Samsung', 'NE63D6711**', 'Eletrodomésticos', 1.89, 195.00, 'Fogão/Forno', NULL, false, NULL),
('e5f917552cf05b168c3cb33927dcdac3'::uuid, 'Sansui LE-32T1', 'Sansui', 'LE-32T1', 'Eletrônicos', 28.40, 54.00, 'Televisão', NULL, false, NULL),
('e687647ecee55f6a89c211c908b7be31'::uuid, 'Bertazzoni MAS365INMNG', 'Bertazzoni', 'MAS365INMNG', 'Eletrodomésticos', 1.00, 187.00, 'Fogão/Forno', NULL, false, NULL),
('e74a7007897950bda4e16579a46567f7'::uuid, 'ROWE ROWE ColorPress i10 with ROWE Scan 450i 36', 'ROWE', 'ROWE ColorPress i10 with ROWE Scan 450i 36', 'Eletrônicos', 1.84, 1.00, 'Equipamento de imagem', NULL, false, NULL),
('e9626633437357709c15f746611398ee'::uuid, 'ROWE ROWE ColorPress i8 with ROWE Scan 450i 36', 'ROWE', 'ROWE ColorPress i8 with ROWE Scan 450i 36', 'Eletrônicos', 1.84, 1.00, 'Equipamento de imagem', NULL, false, NULL),
('e9754864aebc5385aaec8548bdb73e82'::uuid, 'Sansui LE-40VA1', 'Sansui', 'LE-40VA1', 'Eletrônicos', 68.37, 126.94, 'Televisão', NULL, false, NULL),
('ea19ea8840a356ae93e642c410783aaa'::uuid, 'Sansui LE-43VA1', 'Sansui', 'LE-43VA1', 'Eletrônicos', 53.32, 99.24, 'Televisão', NULL, false, NULL),
('ea681c3b9b695b98b0c10c364a4639c1'::uuid, 'LG CBIH3617*E', 'LG', 'CBIH3617*E', 'Eletrodomésticos', 5.00, 190.00, 'Fogão/Forno', NULL, false, NULL),
('eac0a2b196b252418af1f7f7fc9e6b1b'::uuid, 'Oce ColorWave 700', 'Oce', 'ColorWave 700', 'Eletrônicos', 1.88, 5.80, 'Equipamento de imagem', NULL, false, NULL),
('eb15601a7a6d5493bc113cbd94f0e96b'::uuid, 'Ikea MC-9V96E0H378UL', 'Ikea', 'MC-9V96E0H378UL', 'Eletrodomésticos', 3.41, 188.00, 'Fogão/Forno', NULL, false, NULL),
('eb531bbe8f725e339c34d3ccdaa8d2de'::uuid, 'Bertazzoni MAS304INMNG', 'Bertazzoni', 'MAS304INMNG', 'Eletrodomésticos', 1.00, 188.00, 'Fogão/Forno', NULL, false, NULL),
('ebecd64986735ff5813cb93a39d8481e'::uuid, 'HP Inc. HP DesignJet T1600 Printer Series; HP DesignJet T2600 MFP Series', 'HP Inc.', 'HP DesignJet T1600 Printer Series; HP DesignJet T2600 MFP Series', 'Eletrônicos', 0.00, 1.50, 'Equipamento de imagem', NULL, false, NULL),
('ec676326b182560399f4a9e4d6ed0520'::uuid, 'Sansui LE-50KA1', 'Sansui', 'LE-50KA1', 'Eletrônicos', 67.97, 126.82, 'Televisão', NULL, false, NULL),
('ed2e0ee647e959bd90ecfd5cb56d449d'::uuid, 'Samsung QN65S95FAF', 'Samsung', 'QN65S95FAF', 'Eletrônicos', 126.78, 236.91, 'Televisão', NULL, false, NULL),
('eda067771ca85d14993780e5926d341f'::uuid, 'Midea MC-9V96E1H378UL', 'Midea', 'MC-9V96E1H378UL', 'Eletrodomésticos', 3.70, 188.00, 'Fogão/Forno', NULL, false, NULL),
('ef7b6029df375b47820d33fefd5e5375'::uuid, 'Samsung CC70*30***', 'Samsung', 'CC70*30***', 'Eletrodomésticos', 8.35, 195.00, 'Fogão/Forno', NULL, false, NULL),
('eff7d6d77d365304bc9e9a6bb8720875'::uuid, 'Bertazzoni PE244INDXV', 'Bertazzoni', 'PE244INDXV', 'Eletrodomésticos', 4.78, 190.00, 'Fogão/Forno', NULL, false, NULL),
('f0386c94e6fa57d790c17c1123ede95a'::uuid, 'Samsung QN42S90FAE', 'Samsung', 'QN42S90FAE', 'Eletrônicos', 71.93, 137.50, 'Televisão', NULL, false, NULL),
('f06d6d1bce77593ea5dc497992c4e383'::uuid, 'XITRIX XPN-DSA6550', 'XITRIX', 'XPN-DSA6550', 'Eletrônicos', 102.78, 189.72, 'Televisão', NULL, false, NULL),
('f16a85861dc15b11b00db202660af080'::uuid, 'Samsung QN75QN90FAF', 'Samsung', 'QN75QN90FAF', 'Eletrônicos', 144.02, 267.69, 'Televisão', NULL, false, NULL),
('f17d4b40d9c35a0c9179cb0040b6218d'::uuid, 'SKS SKSIT3001GE', 'SKS', 'SKSIT3001GE', 'Eletrodomésticos', 5.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('f22c18afb6845bcca74befecb98b2844'::uuid, 'Samsung NSE90H63D*', 'Samsung', 'NSE90H63D*', 'Eletrodomésticos', 1.80, 195.00, 'Fogão/Forno', NULL, false, NULL),
('f26895e639325e95b74a833b91a5e6a3'::uuid, 'Samsung QN85QN95DAF', 'Samsung', 'QN85QN95DAF', 'Eletrônicos', 192.53, 413.70, 'Televisão', NULL, false, NULL),
('f2b8a878e7c050f8ae8c0ee36848b19f'::uuid, 'Samsung QN55S85FAF', 'Samsung', 'QN55S85FAF', 'Eletrônicos', 96.48, 180.24, 'Televisão', NULL, false, NULL),
('f4687b39a4545d5bb5b8630368bc66f3'::uuid, 'ROWE ROWE ColorPress i10', 'ROWE', 'ROWE ColorPress i10', 'Eletrônicos', 1.81, 1.00, 'Equipamento de imagem', NULL, false, NULL),
('f4cdca43fd065e0bb159c85d6600b222'::uuid, 'Signature Kitchen Suite or SKS SKSIT3611GE', 'Signature Kitchen Suite or SKS', 'SKSIT3611GE', 'Eletrodomésticos', 3.00, 189.00, 'Fogão/Forno', NULL, false, NULL),
('f7f76da8d1d0513d9448610d0d0c34d8'::uuid, 'HP Inc. HP DesignJet XL 3600 MFP Series', 'HP Inc.', 'HP DesignJet XL 3600 MFP Series', 'Eletrônicos', 0.00, 2.00, 'Equipamento de imagem', NULL, false, NULL),
('f8646dc0f58c5b6baab3562c5197382c'::uuid, 'KIP KIP 700', 'KIP', 'KIP 700', 'Eletrônicos', 0.92, 0.60, 'Equipamento de imagem', NULL, false, NULL),
('f94935a8399755b1a7ef0fb69441fb21'::uuid, 'XITRIX XPN-DSA5550', 'XITRIX', 'XPN-DSA5550', 'Eletrônicos', 83.92, 155.23, 'Televisão', NULL, false, NULL),
('fb60ce8eef0e516f89bdcd57cc7c0d64'::uuid, 'Samsung QN55QN90DAF', 'Samsung', 'QN55QN90DAF', 'Eletrônicos', 102.15, 223.90, 'Televisão', NULL, false, NULL),
('fb694018ea92552480511d6265615a84'::uuid, 'LG CBEW3017*E', 'LG', 'CBEW3017*E', 'Eletrodomésticos', 4.00, 195.00, 'Fogão/Forno', NULL, false, NULL),
('fb971b43e7475bc2968d662fd9b57c84'::uuid, 'Oce PlotWave 365  Printer', 'Oce', 'PlotWave 365  Printer', 'Eletrônicos', 1.21, 5.30, 'Equipamento de imagem', NULL, false, NULL),
('fc39b502d0a55d53a1710865f45d8c92'::uuid, 'Sansui LE-65V1', 'Sansui', 'LE-65V1', 'Eletrônicos', 127.87, 235.44, 'Televisão', NULL, false, NULL)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, brand = EXCLUDED.brand, model = EXCLUDED.model, category = EXCLUDED.category, avg_power_w = EXCLUDED.avg_power_w, annual_energy_kwh = EXCLUDED.annual_energy_kwh, subcategory = EXCLUDED.subcategory, standby_power_w = EXCLUDED.standby_power_w, is_generic = EXCLUDED.is_generic, avg_idle_energy_for_hour = EXCLUDED.avg_idle_energy_for_hour;
INSERT INTO public.product (id, name, brand, model, category, avg_power_w, annual_energy_kwh, subcategory, standby_power_w, is_generic, avg_idle_energy_for_hour) VALUES
('fd4829026e3c5581a01890be3dd2bf12'::uuid, 'Samsung QN55S90DAF', 'Samsung', 'QN55S90DAF', 'Eletrônicos', 98.58, 184.10, 'Televisão', NULL, false, NULL),
('ff10656484be5333a14fd46e0f16962a'::uuid, 'ROWE ROWE ColorPress i6 with ROWE Scan 450i 36', 'ROWE', 'ROWE ColorPress i6 with ROWE Scan 450i 36', 'Eletrônicos', 1.84, 1.00, 'Equipamento de imagem', NULL, false, NULL),
('ffaec5fa4cef5843a0c6b58781a536ca'::uuid, 'ROWE ROWE ColorPress i8', 'ROWE', 'ROWE ColorPress i8', 'Eletrônicos', 1.81, 1.00, 'Equipamento de imagem', NULL, false, NULL)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, brand = EXCLUDED.brand, model = EXCLUDED.model, category = EXCLUDED.category, avg_power_w = EXCLUDED.avg_power_w, annual_energy_kwh = EXCLUDED.annual_energy_kwh, subcategory = EXCLUDED.subcategory, standby_power_w = EXCLUDED.standby_power_w, is_generic = EXCLUDED.is_generic, avg_idle_energy_for_hour = EXCLUDED.avg_idle_energy_for_hour;
INSERT INTO public.product_source_observation (id, canonical_product_id, source, external_id, brand, model, dataset_id, power_w, annual_energy_kwh, standby_power_w, observed_at, is_generic, voltage_raw, voltage_kind, voltage_min_v, voltage_max_v, raw_energy_value, raw_energy_unit) VALUES
('0041e789ade651bbb78b5a85f450b121'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GC-L228FTLK / GC-L228FTL1|003968/2017|127 V', 'LG', 'GC-L228FTLK / GC-L228FTL1', 'inmetro_refrigerators', NULL, 684.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 57.0, 'kWh/mes'),
('00a50f6b0bbf5ced9df29693510bb283'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|H200L|002580/2017|220 V', 'Philco', 'H200L', 'inmetro_refrigerators', NULL, 414.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 34.5, 'kWh/mes'),
('00ed85f27ed051c481a816fdcf010f52'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RL4353RBASL/BZ|001495/2017|220 V', 'Samsung', 'RL4353RBASL/BZ', 'inmetro_refrigerators', NULL, 462.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 38.5, 'kWh/mes'),
('00f1430b64be5956804d7fc34ed6a17f'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Baseboard heater (6 ft)', NULL, NULL, 'WATTSIMPLE', 1500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('03001cec867f528e903e8ad07801d6c1'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Hot tub', NULL, NULL, 'WATTSIMPLE', 4000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('032758d3179b5bd49547eb9e9137df2f'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Midea|MRC08|001496/2017|127 V', 'Midea', 'MRC08', 'inmetro_refrigerators', NULL, 165.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 13.8, 'kWh/mes'),
('034096699c5c5b0cbba21590dd247445'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Britânia|BRF533BD|002671/2020|220 V', 'Britânia', 'BRF533BD', 'inmetro_refrigerators', NULL, 528.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 44.0, 'kWh/mes'),
('0485a9f791495965a315194ec8c15052'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRO80|005218/2016|220 V', 'BRASTEMP', 'BRO80', 'inmetro_refrigerators', NULL, 872.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 72.7, 'kWh/mes'),
('04dbe577d88953a6b699036df08f128c'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Panasonic|NR-BT51|5576/2017|127 V', 'Panasonic', 'NR-BT51', 'inmetro_refrigerators', NULL, 424.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 35.4, 'kWh/mes'),
('052c51600a955ea0809f3f147499c253'::uuid, 'b0a058f4cfe75882a3550c0298f5ec68'::uuid, 'WATTSIMPLE', 'Deep fryer', NULL, NULL, 'WATTSIMPLE', 1700.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('05d694fc2dc150abb64a46122a5d39dd'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Esmaltec|ROC35|002251/2017|127 V', 'Esmaltec', 'ROC35', 'inmetro_refrigerators', NULL, 270.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 22.5, 'kWh/mes'),
('069bc08c4458542195cc966a0e239e51'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRE59|005218/2016|220 V', 'BRASTEMP', 'BRE59', 'inmetro_refrigerators', NULL, 804.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 67.0, 'kWh/mes'),
('06a0e4de73b15baf9e45f397a7c2b214'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Esmaltec|ROC31|002251/2017|220 V', 'Esmaltec', 'ROC31', 'inmetro_refrigerators', NULL, 286.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 23.9, 'kWh/mes'),
('06f8b1e995ba5a23b0862a24fcd662b2'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF90PIXR|000222/2018|127 V', 'BERTAZZONI', 'REF90PIXR', 'inmetro_refrigerators', NULL, 469.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 39.1, 'kWh/mes'),
('06fae6841766544caaac6bb0158cd4ad'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Midea|MD-RT468MTA042|002748/2020|220 V', 'Midea', 'MD-RT468MTA042', 'inmetro_refrigerators', NULL, 417.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 34.8, 'kWh/mes'),
('072263ce6e6a5d55a9d6c346c806ac4f'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|SH72X_SS72X|005403/2016|127 V', 'Electrolux', 'SH72X_SS72X', 'inmetro_refrigerators', NULL, 768.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 64.0, 'kWh/mes'),
('073db8aaadc05d0a8e861ecae058cacf'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF510IP|004318/2020|127 V', 'Philco', 'PRF510IP', 'inmetro_refrigerators', NULL, 756.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 63.0, 'kWh/mes'),
('0781cbc6b1105432984ec39ac0bc4e6a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GC-X247CSAV / GC-X247CSA1 / GC-X247CQBV / GC-X247CQB1 / GC-X247CSBV / GC-X247CSB1|003968/2017|220 V', 'LG', 'GC-X247CSAV / GC-X247CSA1 / GC-X247CQBV / GC-X247CQB1 / GC-X247CSBV / GC-X247CSB1', 'inmetro_refrigerators', NULL, 690.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 57.5, 'kWh/mes'),
('07b2d60cf2f055d3b1ae633695ce2a91'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Galanz|GFb04C01A-Ix220
GFb04C01A-Pt220
GFb04C01A-Br220
GFb04C01A-Ix127
GFb04C01A-Pt127
GFb04C01A-Br127|004319/2020|127 V', 'Galanz', 'GFb04C01A-Ix220
GFb04C01A-Pt220
GFb04C01A-Br220
GFb04C01A-Ix127
GFb04C01A-Pt127
GFb04C01A-Br127', 'inmetro_refrigerators', NULL, 182.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 15.2, 'kWh/mes'),
('08fd70931f515dc993b5115629167bd5'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Electrolux|RE80|005401/2016|220 V', 'Electrolux', 'RE80', 'inmetro_refrigerators', NULL, 208.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 17.4, 'kWh/mes'),
('08fdb548e87b549195b28f9de9630041'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG111B|003271/2019|220 V', 'Philco', 'PFG111B', 'inmetro_refrigerators', NULL, 198.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 16.5, 'kWh/mes'),
('0986a6421d64508a98565ffffb9bbd3d'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF75PRR|000222/2018|220 V', 'BERTAZZONI', 'REF75PRR', 'inmetro_refrigerators', NULL, 447.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 37.3, 'kWh/mes'),
('09cc0c01b57c567ca2851bc43cedf054'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GM86SDDB / GM86SDDB1|003968/2017|127 V', 'LG', 'GM86SDDB / GM86SDDB1', 'inmetro_refrigerators', NULL, 740.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 61.7, 'kWh/mes'),
('0aa9e1c0c2215024a80a6f579c6519d3'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RS65R5411M9/AZ|004878/2019|127 V', 'Samsung', 'RS65R5411M9/AZ', 'inmetro_refrigerators', NULL, 656.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 54.7, 'kWh/mes'),
('0ac8589859495039b84589265104240e'::uuid, 'b833c7d7cc495b119be3f541aa8ec840'::uuid, 'WATTSIMPLE', 'Bathroom exhaust fan', NULL, NULL, 'WATTSIMPLE', 30.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('0b29718a92235056b78ab3c399a3bdb1'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF510I|004318/2020|220 V', 'Philco', 'PRF510I', 'inmetro_refrigerators', NULL, 660.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 55.0, 'kWh/mes'),
('0c1dd62145bf5dd2b23420124d083f14'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRC12|005222/2016|220 V', 'BRASTEMP', 'BRC12', 'inmetro_refrigerators', NULL, 228.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 19.0, 'kWh/mes'),
('0ce5f89935fe553c93b9a619ee614f40'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Shop vac', NULL, NULL, 'WATTSIMPLE', 1400.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('0dbf3a8e2d185234bee68eb90d3939aa'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF504ID|001056/2020|220 V', 'Philco', 'PRF504ID', 'inmetro_refrigerators', NULL, 612.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 51.0, 'kWh/mes'),
('0ddba78ebc525e08b41e9d4fd2e4af75'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CHA31|005219/2016|220 V', 'CONSUL', 'CHA31', 'inmetro_refrigerators', NULL, 554.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 46.2, 'kWh/mes'),
('0dde50c194a75f4d872d2767fda81e39'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Crissair|RSD 05.2  350 litros 220V|009778/2019|220 V', 'Crissair', 'RSD 05.2  350 litros 220V', 'inmetro_refrigerators', NULL, 225.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 18.8, 'kWh/mes'),
('0e68befbecca5b6f93ffb51123a8d647'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF504I|001056/2020|127 V', 'Philco', 'PRF504I', 'inmetro_refrigerators', NULL, 570.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 47.5, 'kWh/mes'),
('0ea7d3696fbb57ffa1aec5df727d5873'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Midea|RCFA11|003109/2016|127 V', 'Midea', 'RCFA11', 'inmetro_refrigerators', NULL, 308.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 25.7, 'kWh/mes'),
('0efbf55f986552a58f535e1fc475864f'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG50ICE|003271/2019|220 V', 'Philco', 'PFG50ICE', 'inmetro_refrigerators', NULL, 144.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 12.0, 'kWh/mes'),
('0fbc9b12d5fc50b0a4f7ce2bc62a3884'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Clothes iron', NULL, NULL, 'WATTSIMPLE', 1100.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('0fde0dfc23af5663a90bfde31266fff9'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRD49|005217/2016|220 V', 'CONSUL', 'CRD49', 'inmetro_refrigerators', NULL, 696.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 58.0, 'kWh/mes'),
('0fe32ddefffd58ddb975113d270ac70f'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Panasonic|NR-BT40|5576/2017|220 V', 'Panasonic', 'NR-BT40', 'inmetro_refrigerators', NULL, 540.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 45.0, 'kWh/mes'),
('108b848aede753f1a95e5a77105730dc'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Midea|CFA10|003109/2016|220 V', 'Midea', 'CFA10', 'inmetro_refrigerators', NULL, 277.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 23.1, 'kWh/mes'),
('108db4e7e1975f218d3464b8684aeca5'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF504I|001056/2020|220 V', 'Philco', 'PRF504I', 'inmetro_refrigerators', NULL, 510.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 42.5, 'kWh/mes'),
('108f29d83dc558d7917c8352867c2b4b'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Elettromec|REFRI FD 600X2|004429/2016|220 V', 'Elettromec', 'REFRI FD 600X2', 'inmetro_refrigerators', NULL, 693.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 57.8, 'kWh/mes'),
('10d92f06d475582090377425a5e14585'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DC49A|005402/2016|127 V', 'Electrolux', 'DC49A', 'inmetro_refrigerators', NULL, 697.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 58.1, 'kWh/mes'),
('1103108aeb3256a3a3ffe7f271dd8933'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Midea|RCFC41|003109/2016|127 V', 'Midea', 'RCFC41', 'inmetro_refrigerators', NULL, 464.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 38.7, 'kWh/mes'),
('111f796675f85547921042966273132c'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Midea|RCFA12|003109/2016|220 V', 'Midea', 'RCFA12', 'inmetro_refrigerators', NULL, 250.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 20.9, 'kWh/mes'),
('11253ed2142f5dc2be3f77df92f84751'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Britânia|BFG94P|007591/2016|220 V', 'Britânia', 'BFG94P', 'inmetro_refrigerators', NULL, 216.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 18.0, 'kWh/mes'),
('1140c19a0e8c5b0c9ab61fab4dbfe056'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF533I|002671/2020|127 V', 'Philco', 'PRF533I', 'inmetro_refrigerators', NULL, 504.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 42.0, 'kWh/mes'),
('114290d6f4a4588ebd9ecad721855e8f'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RF56K9040SR/BZ|007317/2017|220 V', 'Samsung', 'RF56K9040SR/BZ', 'inmetro_refrigerators', NULL, 960.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 80.0, 'kWh/mes'),
('114b3fc8c60e52369cacfda081d14922'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF406I|008370/2019|220 V', 'Philco', 'PRF406I', 'inmetro_refrigerators', NULL, 516.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 43.0, 'kWh/mes'),
('11fd1418d41c5aa2b7eeab6a38c80d91'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM53|005218/2016|127 V', 'BRASTEMP', 'BRM53', 'inmetro_refrigerators', NULL, 684.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 57.0, 'kWh/mes'),
('120e284639625d76bcdf979d3242a946'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Britânia|BRF533ID|002671/2020|127 V', 'Britânia', 'BRF533ID', 'inmetro_refrigerators', NULL, 528.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 44.0, 'kWh/mes'),
('12d48d7320965792b7863e968e40c0a6'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRE44|005218/2016|220 V', 'CONSUL', 'CRE44', 'inmetro_refrigerators', NULL, 696.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 58.0, 'kWh/mes'),
('132eeca1cb8354b2a8e5f32baef081a0'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM35|005218/2016|127 V', 'CONSUL', 'CRM35', 'inmetro_refrigerators', NULL, 494.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 41.2, 'kWh/mes'),
('133bc96ea3dd54649ecbe00c51827192'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Miele|KF 2801 Vi 220 Volts|003340/2021|220 V', 'Miele', 'KF 2801 Vi 220 Volts', 'inmetro_refrigerators', NULL, 366.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 30.5, 'kWh/mes'),
('13857b56adda5af482162d8df50d5f9b'::uuid, '44b152237bec5d678facdb985e3e01c5'::uuid, 'WATTSIMPLE', 'Desktop computer', NULL, NULL, 'WATTSIMPLE', 200.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('13d3fd655b6e5ed680395b1bee498381'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'TECNO|TR54FXDA|005755/2019|220 V', 'TECNO', 'TR54FXDA', 'inmetro_refrigerators', NULL, 498.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 41.5, 'kWh/mes'),
('143c514ce4e95d738de278fe438f02c6'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RT38K5A0KWW/FZ|001495/2017|220 V', 'Samsung', 'RT38K5A0KWW/FZ', 'inmetro_refrigerators', NULL, 471.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 39.3, 'kWh/mes'),
('14cab2487cf1535a8a546ec0da1db54d'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Pond pump', NULL, NULL, 'WATTSIMPLE', 150.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('1533e3745c3b54cabc4812fb9fd045db'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Esmaltec|RCD38|002252/2017|127 V', 'Esmaltec', 'RCD38', 'inmetro_refrigerators', NULL, 492.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 41.0, 'kWh/mes'),
('15788a28928d59b8aaac2712c811aff8'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFH160B|003272/2019|220 V', 'Philco', 'PFH160B', 'inmetro_refrigerators', NULL, 309.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 25.8, 'kWh/mes'),
('15a1216061de514db84757aa6f13ecc9'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Garage door opener', NULL, NULL, 'WATTSIMPLE', 550.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('15c37afeccca5bec9e525c4ad632b7ba'::uuid, '32bc03267d0a5a009753fd6f5f31723e'::uuid, 'WATTSIMPLE', 'Christmas lights (LED, 500 count)', NULL, NULL, 'WATTSIMPLE', 30.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('15ed1cddf11355ad9c3678e1b41175af'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF90PIXL|000222/2018|220 V', 'BERTAZZONI', 'REF90PIXL', 'inmetro_refrigerators', NULL, 469.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 39.1, 'kWh/mes'),
('15edf523f758542690cf9a322f56bae5'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|TF55_TF55S|005404/2016|220 V', 'Electrolux', 'TF55_TF55S', 'inmetro_refrigerators', NULL, 597.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 49.8, 'kWh/mes'),
('1644dad509305f089e201b8e4689005d'::uuid, '32bc03267d0a5a009753fd6f5f31723e'::uuid, 'WATTSIMPLE', 'LED bulb', NULL, NULL, 'WATTSIMPLE', 10.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('16658e1750c3520da395a163cfb779a7'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RT46K6A4KWW/FZ|001495/2017|220 V', 'Samsung', 'RT46K6A4KWW/FZ', 'inmetro_refrigerators', NULL, 499.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 41.6, 'kWh/mes'),
('16a589c52cdf5b2e80d7609be7e3a076'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RS58T5561B1/BZ|000243/2019|220 V', 'Samsung', 'RS58T5561B1/BZ', 'inmetro_refrigerators', NULL, 576.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 48.0, 'kWh/mes'),
('16b224d3092a543eb71a8b6fdc8b8d1e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Continental|TC41_TC41S|005404/2016|127 V', 'Continental', 'TC41_TC41S', 'inmetro_refrigerators', NULL, 615.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 51.3, 'kWh/mes'),
('16bc65073e8e56879f17bf349bc75bbf'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Midea|MRC06B2|001496/2017|220 V', 'Midea', 'MRC06B2', 'inmetro_refrigerators', NULL, 174.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 14.5, 'kWh/mes'),
('16cbaa660ee15946b12638c30d14a9c4'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Electrolux|H550|004053/2020|220 V', 'Electrolux', 'H550', 'inmetro_refrigerators', NULL, 870.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 72.5, 'kWh/mes'),
('16cc681492cd55acbed78cfa0695f379'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Panasonic|NR-BT40|5576/2017|127 V', 'Panasonic', 'NR-BT40', 'inmetro_refrigerators', NULL, 540.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 45.0, 'kWh/mes'),
('173b03fa63255b0789f423e727199ea2'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM43Z|005218/2016|127 V', 'CONSUL', 'CRM43Z', 'inmetro_refrigerators', NULL, 624.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 52.0, 'kWh/mes'),
('175892eb2bc65bea8779e008ffd91d59'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF520DIP|008370/2019|220 V', 'Philco', 'PRF520DIP', 'inmetro_refrigerators', NULL, 735.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 61.3, 'kWh/mes'),
('1897292229bf59dea33fa89f6c285b56'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PH85PR|007591/2016|220 V', 'Philco', 'PH85PR', 'inmetro_refrigerators', NULL, 210.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 17.5, 'kWh/mes'),
('1915326d69db5fa3a16272ad9983900e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RF49A5202S9/AZ|001495/2017|127 V', 'Samsung', 'RF49A5202S9/AZ', 'inmetro_refrigerators', NULL, 522.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 43.5, 'kWh/mes'),
('1934a6b976e959f08ec38bdef8ec8cfd'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PFG100RP|000963/2021|127 V', 'Philco', 'PFG100RP', 'inmetro_refrigerators', NULL, 266.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 22.2, 'kWh/mes'),
('196e5127e741589b8817aeec81a03a43'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG90I|007591/2016|127 V', 'Philco', 'PFG90I', 'inmetro_refrigerators', NULL, 216.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 18.0, 'kWh/mes'),
('19a4e572b7925e489c0d255af95ca3db'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF533ID|002671/2020|127 V', 'Philco', 'PRF533ID', 'inmetro_refrigerators', NULL, 528.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 44.0, 'kWh/mes'),
('1a805893d1f751c2a11a544660e4c268'::uuid, 'be389ae923875726a7dffeeda9b2e4c4'::uuid, 'WATTSIMPLE', 'Electric water heater', NULL, NULL, 'WATTSIMPLE', 4000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('1a87011e144a599b92c3d8cc7dfda6b5'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Midea|MRC06B1|001496/2017|127 V', 'Midea', 'MRC06B1', 'inmetro_refrigerators', NULL, 144.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 12.0, 'kWh/mes'),
('1a935d66fb0d5abfb29375c45c4ea4ca'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Electrolux|RE120|005401/2016|127 V', 'Electrolux', 'RE120', 'inmetro_refrigerators', NULL, 238.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 19.9, 'kWh/mes'),
('1aaabdf23a96526694ded355f7ef9bf8'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CVU26Z|005220/2016|127 V', 'CONSUL', 'CVU26Z', 'inmetro_refrigerators', NULL, 470.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 39.2, 'kWh/mes'),
('1adaa03a86a459fcaf0add68600a0db7'::uuid, '3c56d7551b375487a95a1882b9a6df57'::uuid, 'WATTSIMPLE', 'Induction cooktop (single burner)', NULL, NULL, 'WATTSIMPLE', 1800.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('1c020dc64d2e5d0f8507e21d025910eb'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Midea|MD-RS587FGA|002669/2020|220 V', 'Midea', 'MD-RS587FGA', 'inmetro_refrigerators', NULL, 602.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 50.2, 'kWh/mes'),
('1ca1d253ab2f5c07bddd3ab561b0274b'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'TECNO|TR65FXDA|005435/2019|127 V', 'TECNO', 'TR65FXDA', 'inmetro_refrigerators', NULL, 518.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 43.2, 'kWh/mes'),
('1cc9c1acc56a5a1ebd268b69b6d2febc'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF533IPD|002671/2020|127 V', 'Philco', 'PRF533IPD', 'inmetro_refrigerators', NULL, 528.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 44.0, 'kWh/mes'),
('1ce0a166387457c98367c211e6b4fac0'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFH260B|002580/2017|220 V', 'Philco', 'PFH260B', 'inmetro_refrigerators', NULL, 456.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 38.0, 'kWh/mes'),
('1d1d86f388095eb9b44ac397d6201e9d'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Space heater', NULL, NULL, 'WATTSIMPLE', 1500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('1d44013bcfb85312b61b5f0ec390275a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GT44BPP / GT44BPP1|003968/2017|220 V', 'LG', 'GT44BPP / GT44BPP1', 'inmetro_refrigerators', NULL, 415.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 34.6, 'kWh/mes'),
('1d7864c386745f3c9f9a13a0446e7b63'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG87B|001955/2017|127 V', 'Philco', 'PFG87B', 'inmetro_refrigerators', NULL, 163.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 13.6, 'kWh/mes'),
('1e7a4c608b9e594ebde71a3c3e5405b7'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM51|005218/2016|127 V', 'CONSUL', 'CRM51', 'inmetro_refrigerators', NULL, 630.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 52.5, 'kWh/mes'),
('1e9e34215f1c5cbd8a6f4161485ffcb8'::uuid, 'b833c7d7cc495b119be3f541aa8ec840'::uuid, 'WATTSIMPLE', 'Ceiling fan', NULL, NULL, 'WATTSIMPLE', 60.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('1f2889f43c345ad2a6202ad2559eeef4'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DM90X_DM91X|000514/2018|127 V', 'Electrolux', 'DM90X_DM91X', 'inmetro_refrigerators', NULL, 675.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 56.3, 'kWh/mes'),
('1fcbfe6fca7c565d8f22957752c7fe34'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'EOS|EFH250X|003659/2020|220 V', 'EOS', 'EFH250X', 'inmetro_refrigerators', NULL, 344.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 28.7, 'kWh/mes'),
('1fd95f1ed6db5734b344975ba3986a61'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'EOS|EFB130
EFB130P|003660/2020|220 V', 'EOS', 'EFB130
EFB130P', 'inmetro_refrigerators', NULL, 213.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 17.8, 'kWh/mes'),
('20ff44664bbb5719a0fdf02ca6e6d435'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF505TI|001056/2020|220 V', 'Philco', 'PRF505TI', 'inmetro_refrigerators', NULL, 480.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 40.0, 'kWh/mes'),
('2178f0cc34ce508b9fbb82ca89db4f6e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF90PRR|000222/2018|220 V', 'BERTAZZONI', 'REF90PRR', 'inmetro_refrigerators', NULL, 469.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 39.1, 'kWh/mes'),
('21d0918a3f32584d933a1c09d6cac5f7'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Mobility scooter charger', NULL, NULL, 'WATTSIMPLE', 100.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('22525a6ca453579aaf5b079ef1338e95'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM39|005218/2016|220 V', 'CONSUL', 'CRM39', 'inmetro_refrigerators', NULL, 589.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 49.1, 'kWh/mes'),
('2271c42920955f9da6af5186ad39312f'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'CPAP machine', NULL, NULL, 'WATTSIMPLE', 40.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('231ffaa43f9d553f9afbefa8d7836e5e'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG50ICE|003271/2019|127 V', 'Philco', 'PFG50ICE', 'inmetro_refrigerators', NULL, 141.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 11.8, 'kWh/mes'),
('233dfb49159558aa9678dfea1ddd7ccc'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM38|005218/2016|220 V', 'CONSUL', 'CRM38', 'inmetro_refrigerators', NULL, 589.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 49.1, 'kWh/mes'),
('23f2f0f19fca5ef99721bc404306f92a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Esmaltec|ROC35|002251/2017|220 V', 'Esmaltec', 'ROC35', 'inmetro_refrigerators', NULL, 270.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 22.5, 'kWh/mes'),
('243b5d2606d751b4b15a1c51c33a450b'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DM90X_DM91X|000514/2018|220 V', 'Electrolux', 'DM90X_DM91X', 'inmetro_refrigerators', NULL, 675.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 56.3, 'kWh/mes'),
('247634b89fe6566f8bb2d3b452913150'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Viking Range|VCSB5483 / FDSB5483|007592/2016|127 V', 'Viking Range', 'VCSB5483 / FDSB5483', 'inmetro_refrigerators', NULL, 1213.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 101.1, 'kWh/mes'),
('2498cbdd9d095e4fa4f6e190809c0ad3'::uuid, '3c56d7551b375487a95a1882b9a6df57'::uuid, 'WATTSIMPLE', 'Toaster oven', NULL, NULL, 'WATTSIMPLE', 1200.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('24a4a0f2d8e75558a33fef0d9f5e0552'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF505TI|001056/2020|127 V', 'Philco', 'PRF505TI', 'inmetro_refrigerators', NULL, 480.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 40.0, 'kWh/mes'),
('24bd3dfa71fb553eb427eab94ed65533'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Bread maker', NULL, NULL, 'WATTSIMPLE', 600.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('24dc46d7ec255d32951f19c8d8834c8e'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Electrolux|FE18|005399/2016|220 V', 'Electrolux', 'FE18', 'inmetro_refrigerators', NULL, 501.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 41.8, 'kWh/mes'),
('25ad42f333a75c8288aab677ca232583'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Wine fridge', NULL, NULL, 'WATTSIMPLE', 100.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('25c5c03025f958cda201194c6ff0d4eb'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Miele|K 2801 Vi 127 Volts|001051/2020|127 V', 'Miele', 'K 2801 Vi 127 Volts', 'inmetro_refrigerators', NULL, 250.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 20.9, 'kWh/mes'),
('25e424ca4554579bbbe26c94e4f1e920'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Panasonic|NR-CB85|3738/2020|127 V', 'Panasonic', 'NR-CB85', 'inmetro_refrigerators', NULL, 792.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 66.0, 'kWh/mes'),
('2613364197df5f2ea3d181e935c0951e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRD37|005217/2016|220 V', 'CONSUL', 'CRD37', 'inmetro_refrigerators', NULL, 522.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 43.5, 'kWh/mes'),
('26b0b6a502565801bc755bd06e0017d5'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Electric kettle', NULL, NULL, 'WATTSIMPLE', 1500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('271a33b7beb555dc9157fcd9c7516252'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Midea|MD-RT468MTA041|002748/2020|127 V', 'Midea', 'MD-RT468MTA041', 'inmetro_refrigerators', NULL, 492.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 41.0, 'kWh/mes'),
('281118dbd58c51a49e858a7e669d2475'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRY59|005218/2016|127 V', 'BRASTEMP', 'BRY59', 'inmetro_refrigerators', NULL, 756.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 63.0, 'kWh/mes'),
('28ea6d87816c5e3e8635ae50f19477d4'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'LED TV (65")', NULL, NULL, 'WATTSIMPLE', 100.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('29a6fc8629ec5af48342385921babb18'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DFN39_DFX39_TF39_TF39S|005404/2016|220 V', 'Electrolux', 'DFN39_DFX39_TF39_TF39S', 'inmetro_refrigerators', NULL, 523.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 43.6, 'kWh/mes'),
('29adce6d6c575611a62f5a9530b299bf'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM59|005218/2016|220 V', 'BRASTEMP', 'BRM59', 'inmetro_refrigerators', NULL, 792.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 66.0, 'kWh/mes'),
('29b15e6e39735967829d3d5906e7d01f'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GT51BPP / GT51BPP1|006368/2019|220 V', 'LG', 'GT51BPP / GT51BPP1', 'inmetro_refrigerators', NULL, 522.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 43.5, 'kWh/mes'),
('29f0958b163357b08cef6e7fd0b2d519'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM42|005218/2016|127 V', 'CONSUL', 'CRM42', 'inmetro_refrigerators', NULL, 669.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 55.8, 'kWh/mes'),
('2a5aed0722a756c7b9609e97d07ffbc1'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RT38K5A0KS9/FZ|001495/2017|127 V', 'Samsung', 'RT38K5A0KS9/FZ', 'inmetro_refrigerators', NULL, 471.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 39.3, 'kWh/mes'),
('2a7934e3c2d95ef5b7a0be8384973538'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GR-X228NMSM / GR-X228NMS1|005754/2019|220 V', 'LG', 'GR-X228NMSM / GR-X228NMS1', 'inmetro_refrigerators', NULL, 842.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 70.2, 'kWh/mes'),
('2a7eeaeb165f5ea4bdbfd1ffc2c958cf'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DF44_DF44S|005404/2016|127 V', 'Electrolux', 'DF44_DF44S', 'inmetro_refrigerators', NULL, 675.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 56.3, 'kWh/mes'),
('2b098c0db8a95b7f9949be7e2d38008d'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DB83_DB83X_DB84_DB84X|005404/2016|220 V', 'Electrolux', 'DB83_DB83X_DB84_DB84X', 'inmetro_refrigerators', NULL, 816.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 68.0, 'kWh/mes'),
('2b544f5ce73550ab90bc305ec700b81e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RL4363RBASL/AZ|001495/2017|127 V', 'Samsung', 'RL4363RBASL/AZ', 'inmetro_refrigerators', NULL, 462.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 38.5, 'kWh/mes'),
('2ba80f4c6cff5ac89331ea87e773c6c3'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Gorenje|NRKI5182A2|005039/2019|220 V', 'Gorenje', 'NRKI5182A2', 'inmetro_refrigerators', NULL, 282.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 23.5, 'kWh/mes'),
('2bcfe15950d559b888ce610161948822'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Electrolux|H330|004053/2020|220 V', 'Electrolux', 'H330', 'inmetro_refrigerators', NULL, 555.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 46.3, 'kWh/mes'),
('2c8b5eedac0057cf89e8011606c5cce3'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF533ID|002671/2020|220 V', 'Philco', 'PRF533ID', 'inmetro_refrigerators', NULL, 528.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 44.0, 'kWh/mes'),
('2cc2523ac9065f8e8046c907fe5e8f3d'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Venax|NGV 10|001450/2018|127 V', 'Venax', 'NGV 10', 'inmetro_refrigerators', NULL, 216.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 18.0, 'kWh/mes'),
('2d1fdbb7f0be57f888e3c32da6136374'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF36FDFIXNV|005435/2019|127 V', 'BERTAZZONI', 'REF36FDFIXNV', 'inmetro_refrigerators', NULL, 518.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 43.2, 'kWh/mes'),
('2dade4fd9dab53d6b1553147b9d02e54'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRB39|005223/2016|220 V', 'CONSUL', 'CRB39', 'inmetro_refrigerators', NULL, 439.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 36.6, 'kWh/mes'),
('2daf27960e845011a8d5c3d5b4b12786'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DQ90X|000514/2018|127 V', 'Electrolux', 'DQ90X', 'inmetro_refrigerators', NULL, 750.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 62.5, 'kWh/mes'),
('2db4bed13e655764b749bdad5382489c'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF380I|002671/2020|127 V', 'Philco', 'PRF380I', 'inmetro_refrigerators', NULL, 432.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 36.0, 'kWh/mes'),
('2dcef728d1815deaafd0a754ce921532'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GR-B413PSJU / GR-B413PSJ1|001421/2019|220 V', 'LG', 'GR-B413PSJU / GR-B413PSJ1', 'inmetro_refrigerators', NULL, 595.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 49.6, 'kWh/mes'),
('2e3e24c9337051e69d61b89ec40313c2'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Miele|K 2901 Vi 127 Volts|001051/2020|127 V', 'Miele', 'K 2901 Vi 127 Volts', 'inmetro_refrigerators', NULL, 277.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 23.1, 'kWh/mes'),
('2edacd5cc3d65b52b83c8747a844e499'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Britânia|BRF533BD|002671/2020|127 V', 'Britânia', 'BRF533BD', 'inmetro_refrigerators', NULL, 528.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 44.0, 'kWh/mes'),
('2f1161839c595456bb9449e835c81792'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRE58|005218/2016|220 V', 'BRASTEMP', 'BRE58', 'inmetro_refrigerators', NULL, 828.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 69.0, 'kWh/mes'),
('307bbf53984d51a2a06e13f19433f7c5'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PFG120 Vintage|008093/2017|127 V', 'Philco', 'PFG120 Vintage', 'inmetro_refrigerators', NULL, 240.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 20.0, 'kWh/mes'),
('309c07359e34582ea82daefb12b9d5f4'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Midea|MD-RF556FGA|002669/2020|220 V', 'Midea', 'MD-RF556FGA', 'inmetro_refrigerators', NULL, 554.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 46.2, 'kWh/mes'),
('30b85a14b8865fe3951f6539b4212e62'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Viking Range|VCSB5423 / FDSB5423|007592/2016|127 V', 'Viking Range', 'VCSB5423 / FDSB5423', 'inmetro_refrigerators', NULL, 1222.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 101.9, 'kWh/mes'),
('31238380dd1053f49b0128f121e158e4'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PFG120 Vintage|008093/2017|220 V', 'Philco', 'PFG120 Vintage', 'inmetro_refrigerators', NULL, 235.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 19.6, 'kWh/mes'),
('314a45c0aa5a56be8e1908c9ec74b21a'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'White noise machine', NULL, NULL, 'WATTSIMPLE', 5.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('317f49e8fa7a5d8dbe1e1cec2f17ae4a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RF56K9040SR/AZ|007317/2017|127 V', 'Samsung', 'RF56K9040SR/AZ', 'inmetro_refrigerators', NULL, 705.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 58.8, 'kWh/mes'),
('31f9505e4b5355db97fb00c097b66b83'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Galanz|GFb07C01A-Ix220
GFb07C01A-Pt220
GFb07C01A-Br220
GFb07C01A-Ix127
GFb07C01A-Pt127
GFb07C01A-Br127|004319/2020|220 V', 'Galanz', 'GFb07C01A-Ix220
GFb07C01A-Pt220
GFb07C01A-Br220
GFb07C01A-Ix127
GFb07C01A-Pt127
GFb07C01A-Br127', 'inmetro_refrigerators', NULL, 162.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 13.5, 'kWh/mes'),
('3222078fc462515e87741631c20e6d66'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Microwave', NULL, NULL, 'WATTSIMPLE', 1000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('3270ff783a9159d1ae510d3056ea4d4d'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRB36|005223/2016|127 V', 'CONSUL', 'CRB36', 'inmetro_refrigerators', NULL, 426.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 35.5, 'kWh/mes'),
('3276c8b8e5c453cdab90f59e545c5e4c'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG85B|003271/2019|127 V', 'Philco', 'PFG85B', 'inmetro_refrigerators', NULL, 148.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 12.4, 'kWh/mes'),
('32d929cbd68c5eacb2ef6b294fb3ab10'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Viking Range|VCFB5363 / FDFB5363|001954/2017|127 V', 'Viking Range', 'VCFB5363 / FDFB5363', 'inmetro_refrigerators', NULL, 1080.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 90.0, 'kWh/mes'),
('333505f49bd35784b1f7e948d0ceca34'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GM86SDDB / GM86SDDB1|003968/2017|220 V', 'LG', 'GM86SDDB / GM86SDDB1', 'inmetro_refrigerators', NULL, 710.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 59.2, 'kWh/mes'),
('3338bf6e4c795293b526cfb378ed833c'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RF22R7351SR/AZ|007317/2017|127 V', 'Samsung', 'RF22R7351SR/AZ', 'inmetro_refrigerators', NULL, 744.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 62.0, 'kWh/mes'),
('3360bff5950d52a899c3f8216be557c9'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM56Z|005218/2016|127 V', 'BRASTEMP', 'BRM56Z', 'inmetro_refrigerators', NULL, 744.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 62.0, 'kWh/mes'),
('3381e075686e50be98048b78074eff94'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG85ICE|003271/2019|127 V', 'Philco', 'PFG85ICE', 'inmetro_refrigerators', NULL, 148.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 12.4, 'kWh/mes'),
('33ad4a30c5eb5453a4043384a65f8969'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PH85 Platinum|007591/2016|127 V', 'Philco', 'PH85 Platinum', 'inmetro_refrigerators', NULL, 210.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 17.5, 'kWh/mes'),
('33bd5ae5d0345bfa88a58cc58f4ad123'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'TECNO|TR54FXDA|005755/2019|127 V', 'TECNO', 'TR54FXDA', 'inmetro_refrigerators', NULL, 498.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 41.5, 'kWh/mes'),
('3408b9fc4c9354e68635ab2b4c11d732'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Midea|CFA10|003109/2016|127 V', 'Midea', 'CFA10', 'inmetro_refrigerators', NULL, 237.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 19.8, 'kWh/mes'),
('345f0f89a3aa58eab59690dd2e035c16'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Well pump (1/2 HP)', NULL, NULL, 'WATTSIMPLE', 1000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('347b159262595f10bf0d304d05949d79'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RS50N3413S8/BZ|004878/2019|220 V', 'Samsung', 'RS50N3413S8/BZ', 'inmetro_refrigerators', NULL, 770.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 64.2, 'kWh/mes'),
('348caa9288c952e9866ced5fa9b2f3ba'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Midea|MD-RS587FGA|002669/2020|127 V', 'Midea', 'MD-RS587FGA', 'inmetro_refrigerators', NULL, 660.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 55.0, 'kWh/mes'),
('34e9b9b446995c8293a722aa4e5ce10a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF600I|003507/2020|220 V', 'Philco', 'PRF600I', 'inmetro_refrigerators', NULL, 588.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 49.0, 'kWh/mes'),
('34eadeae75c45da5bf0b75a7dbb8a8a0'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Curling iron', NULL, NULL, 'WATTSIMPLE', 90.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('35d3f8f69b9d5c77bab020cd0e58c0d4'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM55|005218/2016|127 V', 'CONSUL', 'CRM55', 'inmetro_refrigerators', NULL, 672.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 56.0, 'kWh/mes'),
('35f47d853c055fc3828595e83f13dc5f'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Electrolux|FE26|005399/2016|220 V', 'Electrolux', 'FE26', 'inmetro_refrigerators', NULL, 524.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 43.7, 'kWh/mes'),
('362137a17dcb50c384e573eb154fc438'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CVU30|005220/2016|220 V', 'CONSUL', 'CVU30', 'inmetro_refrigerators', NULL, 552.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 46.0, 'kWh/mes'),
('3727bdcf468a5d1ca257c81a12c06e04'::uuid, '32bc03267d0a5a009753fd6f5f31723e'::uuid, 'WATTSIMPLE', 'String lights (LED, 100 ft)', NULL, NULL, 'WATTSIMPLE', 15.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('373cb3d273b95d63a9f920af04bca999'::uuid, 'b833c7d7cc495b119be3f541aa8ec840'::uuid, 'WATTSIMPLE', 'Tower fan', NULL, NULL, 'WATTSIMPLE', 60.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('3784b89ecc365f74aa21afe8577ca058'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DFN41_DFX41|005404/2016|127 V', 'Electrolux', 'DFN41_DFX41', 'inmetro_refrigerators', NULL, 651.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 54.3, 'kWh/mes'),
('37e513f54716548680351624f8ec2ebf'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|SH72X_SS72X|005403/2016|220 V', 'Electrolux', 'SH72X_SS72X', 'inmetro_refrigerators', NULL, 768.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 64.0, 'kWh/mes'),
('37ee82b836ce5f609602ded6834548b0'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Heated mattress pad', NULL, NULL, 'WATTSIMPLE', 100.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('381dd8228e6e5a45919594324037839a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Midea|MD-RT453FGA042|002748/2020|220 V', 'Midea', 'MD-RT453FGA042', 'inmetro_refrigerators', NULL, 504.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 42.0, 'kWh/mes'),
('38b95cc624515517ab48b85cd62a1a63'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'EOS|EFH350X|003659/2020|220 V', 'EOS', 'EFH350X', 'inmetro_refrigerators', NULL, 444.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 37.0, 'kWh/mes'),
('390cb09009bd550a98e6686e73bdaa02'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Viking Range|VCRB5363 / FDRB5363|007095/2016|127 V', 'Viking Range', 'VCRB5363 / FDRB5363', 'inmetro_refrigerators', NULL, 373.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 31.1, 'kWh/mes'),
('397f4958b9f4567fb5fdeb65c22d963d'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Galanz|GFb07C01A-Ix220
GFb07C01A-Pt220
GFb07C01A-Br220
GFb07C01A-Ix127
GFb07C01A-Pt127
GFb07C01A-Br127|004319/2020|127 V', 'Galanz', 'GFb07C01A-Ix220
GFb07C01A-Pt220
GFb07C01A-Br220
GFb07C01A-Ix127
GFb07C01A-Pt127
GFb07C01A-Br127', 'inmetro_refrigerators', NULL, 168.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 14.0, 'kWh/mes'),
('399ec8040fb7547e9ef2ceaa6f98ef2b'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Panasonic|NR-BT51|5576/2017|220 V', 'Panasonic', 'NR-BT51', 'inmetro_refrigerators', NULL, 424.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 35.4, 'kWh/mes'),
('39ac44c5f12e5851bed3ac4095bea125'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Britânia|BFG50B|007591/2016|220 V', 'Britânia', 'BFG50B', 'inmetro_refrigerators', NULL, 204.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 17.0, 'kWh/mes'),
('3a7ec806734e5add94cc667e7611f0dc'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM38|005218/2016|127 V', 'CONSUL', 'CRM38', 'inmetro_refrigerators', NULL, 589.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 49.1, 'kWh/mes'),
('3a7f8a3196e853018965278bbb80b221'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RT46K6A4KBS/FZ|001495/2017|220 V', 'Samsung', 'RT46K6A4KBS/FZ', 'inmetro_refrigerators', NULL, 420.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 35.0, 'kWh/mes'),
('3aabdf8bc306558697df9db21d662240'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Aquarium (55-gallon)', NULL, NULL, 'WATTSIMPLE', 100.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('3ab8a02fa9485af6884f4825c906d180'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'EOS|EFH550XX|003659/2020|127 V', 'EOS', 'EFH550XX', 'inmetro_refrigerators', NULL, 733.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 61.1, 'kWh/mes'),
('3b118fb4afa95df3b0d5b1295dd08d70'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Washing machine', NULL, NULL, 'WATTSIMPLE', 500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('3bd823ce08095d6fa89629b8b08a12f5'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CVU20|005220/2016|127 V', 'CONSUL', 'CVU20', 'inmetro_refrigerators', NULL, 458.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 38.2, 'kWh/mes'),
('3d56b21f37c05b1cbc4efe8bd809e680'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Electrolux|FE22|005399/2016|127 V', 'Electrolux', 'FE22', 'inmetro_refrigerators', NULL, 511.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 42.6, 'kWh/mes'),
('3d95f92463eb52968427a9ca6786322c'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF75PRL|000222/2018|127 V', 'BERTAZZONI', 'REF75PRL', 'inmetro_refrigerators', NULL, 447.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 37.3, 'kWh/mes'),
('3f1a41021e355b4ca70fb3f1dd3c2faa'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|RE31|005401/2016|127 V', 'Electrolux', 'RE31', 'inmetro_refrigerators', NULL, 279.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 23.3, 'kWh/mes'),
('3f1d94a19e1d59ceb1cbb593f0cbe658'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Waterbed heater', NULL, NULL, 'WATTSIMPLE', 300.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('3fe1afcc50a55cfeb12ab7d6c231a694'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Garbage disposal', NULL, NULL, 'WATTSIMPLE', 550.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('409daf215b635b959c7860888574d9b7'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|IF55_IF55S_IF55B|005404/2016|127 V', 'Electrolux', 'IF55_IF55S_IF55B', 'inmetro_refrigerators', NULL, 423.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 35.3, 'kWh/mes'),
('41f1679b32495c3dadbca69e5073b895'::uuid, '0f11d15f0f7a59659123a465abfcc20a'::uuid, 'WATTSIMPLE', 'Home server / NAS', NULL, NULL, 'WATTSIMPLE', 60.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('41fb157ff8e257bc931ed66bf96a7735'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Midea|RCFA31|003109/2016|127 V', 'Midea', 'RCFA31', 'inmetro_refrigerators', NULL, 381.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 31.8, 'kWh/mes'),
('4305fb6ea55c54d9984148a477ca8d4a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRB36|005223/2016|220 V', 'CONSUL', 'CRB36', 'inmetro_refrigerators', NULL, 426.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 35.5, 'kWh/mes'),
('433bb30da35f5272805c63150cb5d2de'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFV300I|005214/2021|127 V', 'Philco', 'PFV300I', 'inmetro_refrigerators', NULL, 438.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 36.5, 'kWh/mes'),
('43c1fe91cae55643bec9325dd2d9425c'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG125B|003271/2019|220 V', 'Philco', 'PFG125B', 'inmetro_refrigerators', NULL, 176.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 14.7, 'kWh/mes'),
('43d79ab330a85a42916b47e133412105'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Galanz|GFb12C01A-Ix127
GFb12C01A-Pt127
GFb12C01A-Br127
GFb12C01A-Ix220
GFb12C01A-Pt220
GFb12C01A-Br220|004319/2020|220 V', 'Galanz', 'GFb12C01A-Ix127
GFb12C01A-Pt127
GFb12C01A-Br127
GFb12C01A-Ix220
GFb12C01A-Pt220
GFb12C01A-Br220', 'inmetro_refrigerators', NULL, 254.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 21.2, 'kWh/mes'),
('443c7ef1a18a516cb5d74782f13b2068'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Viking Range|RVRF3361|006283/2018|127 V', 'Viking Range', 'RVRF3361', 'inmetro_refrigerators', NULL, 880.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 73.4, 'kWh/mes'),
('448f21ac596d544fa202815b3e2b11f9'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RF22R7351SR/BZ|007317/2017|220 V', 'Samsung', 'RF22R7351SR/BZ', 'inmetro_refrigerators', NULL, 744.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 62.0, 'kWh/mes'),
('44a1680529c25f2985d7405600ee30be'::uuid, '32bc03267d0a5a009753fd6f5f31723e'::uuid, 'WATTSIMPLE', 'Grow light (600 W)', NULL, NULL, 'WATTSIMPLE', 600.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('453c9041dd81528a9e73c024021c4004'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CHA22|005219/2016|220 V', 'CONSUL', 'CHA22', 'inmetro_refrigerators', NULL, 432.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 36.0, 'kWh/mes'),
('46040157301e5391a19d9d6546267293'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PH85N|007591/2016|127 V', 'Philco', 'PH85N', 'inmetro_refrigerators', NULL, 210.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 17.5, 'kWh/mes'),
('46b0fa27414b5660b882e7292204d4c4'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Pottery kiln (240 V)', NULL, NULL, 'WATTSIMPLE', 8000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('46b776cb48b95a6c998b9961ca2be401'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DC49A|005402/2016|220 V', 'Electrolux', 'DC49A', 'inmetro_refrigerators', NULL, 697.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 58.1, 'kWh/mes'),
('46c74229fc155e34b7b2d71e18dc2472'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Esmaltec|RCD34|002252/2017|220 V', 'Esmaltec', 'RCD34', 'inmetro_refrigerators', NULL, 462.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 38.5, 'kWh/mes'),
('4758cbb5921e5c0f99ff9709efa6ccc4'::uuid, '32bc03267d0a5a009753fd6f5f31723e'::uuid, 'WATTSIMPLE', 'Reptile terrarium (heat + light)', NULL, NULL, 'WATTSIMPLE', 150.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('47710f05dbd75109838d180da0080b78'::uuid, 'c0370d524de75c549a84f38230f1ef98'::uuid, 'WATTSIMPLE', 'Dishwasher', NULL, NULL, 'WATTSIMPLE', 1800.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('48060b89b8465418a8261ed8a241d88e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RS58T5561B1/AZ|000243/2019|127 V', 'Samsung', 'RS58T5561B1/AZ', 'inmetro_refrigerators', NULL, 576.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 48.0, 'kWh/mes'),
('480dcfd73e8250f2b6150cdfd93962f0'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RF23R6301SR/AZ|007317/2017|127 V', 'Samsung', 'RF23R6301SR/AZ', 'inmetro_refrigerators', NULL, 840.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 70.0, 'kWh/mes'),
('48972fe9d9a95deb9d1880a67d6aa724'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'LED TV (55")', NULL, NULL, 'WATTSIMPLE', 90.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('491c367f7b7f5e86b016ca0514d5518b'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'EOS|EFB130
EFB130P|003660/2020|127 V', 'EOS', 'EFB130
EFB130P', 'inmetro_refrigerators', NULL, 213.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 17.8, 'kWh/mes'),
('493e0d8e91c65cf29254b4cc60b87e49'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF90X2|000222/2018|220 V', 'BERTAZZONI', 'REF90X2', 'inmetro_refrigerators', NULL, 608.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 50.7, 'kWh/mes'),
('49c7c19cc6a05251afa6a8a1dec6142b'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PFG100RV|000963/2021|127 V', 'Philco', 'PFG100RV', 'inmetro_refrigerators', NULL, 266.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 22.2, 'kWh/mes'),
('49f4043f3bd757159f1aa3953b4ecfa5'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Oil-filled radiator', NULL, NULL, 'WATTSIMPLE', 1500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('4a283bccbc05522994fdeeb657560ed5'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF510IP|004318/2020|220 V', 'Philco', 'PRF510IP', 'inmetro_refrigerators', NULL, 660.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 55.0, 'kWh/mes'),
('4a28c9ac928e50b689f0acd5328659ab'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG112B|001955/2017|220 V', 'Philco', 'PFG112B', 'inmetro_refrigerators', NULL, 168.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 14.0, 'kWh/mes'),
('4a4462b0d2cb5ff986a05be2cc0edf05'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'EOS|EFH150X|003659/2020|127 V', 'EOS', 'EFH150X', 'inmetro_refrigerators', NULL, 259.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 21.6, 'kWh/mes'),
('4a4f6d9ccdd95f1383e5ea51204b26ed'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RT38K5A0KS9/FZ|001495/2017|220 V', 'Samsung', 'RT38K5A0KS9/FZ', 'inmetro_refrigerators', NULL, 471.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 39.3, 'kWh/mes'),
('4a9db5e66782507890805e76ca9d0e55'::uuid, 'b474827c81b256d88508786ca0b7c60a'::uuid, 'WATTSIMPLE', 'Coffee maker', NULL, NULL, 'WATTSIMPLE', 900.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('4b63e2d617475533b24f63dc4275c472'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF90PRL|000222/2018|220 V', 'BERTAZZONI', 'REF90PRL', 'inmetro_refrigerators', NULL, 469.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 39.1, 'kWh/mes'),
('4cdfde41e831547d880d6fad59b2a06b'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Viking Range|VCRB5303 / FDRB5303|007095/2016|127 V', 'Viking Range', 'VCRB5303 / FDRB5303', 'inmetro_refrigerators', NULL, 399.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 33.3, 'kWh/mes'),
('4d207006852f5e209c4264f32268c8a7'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Midea|MD-RF556FGA|002669/2020|127 V', 'Midea', 'MD-RF556FGA', 'inmetro_refrigerators', NULL, 588.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 49.0, 'kWh/mes'),
('4d507e9ede045abdbc87548136e50309'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Wi-Fi router + modem', NULL, NULL, 'WATTSIMPLE', 20.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('4d7f40696c7752e0928dea5a35074bec'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'EOS|EFB50
EFB50P|003660/2020|127 V', 'EOS', 'EFB50
EFB50P', 'inmetro_refrigerators', NULL, 189.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 15.8, 'kWh/mes'),
('4f00c960cf625d7c913dbc1c8ac49d6f'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRO80|005218/2016|127 V', 'BRASTEMP', 'BRO80', 'inmetro_refrigerators', NULL, 872.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 72.7, 'kWh/mes'),
('4fac1fecfe2c580d9226544070101785'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF500I|008370/2019|220 V', 'Philco', 'PRF500I', 'inmetro_refrigerators', NULL, 560.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 46.7, 'kWh/mes'),
('4ffc2b0193e35f88bdf9110938be5962'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|TF55_TF55S|005404/2016|127 V', 'Electrolux', 'TF55_TF55S', 'inmetro_refrigerators', NULL, 597.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 49.8, 'kWh/mes'),
('505794c24d875f788db33abac41cbfb7'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Britânia|BFG111B|003271/2019|220 V', 'Britânia', 'BFG111B', 'inmetro_refrigerators', NULL, 198.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 16.5, 'kWh/mes'),
('50bccd5115fe52618ddbd947867ba2bf'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GC-L247SLUV / GC-L247SLU1|003968/2017|127 V', 'LG', 'GC-L247SLUV / GC-L247SLU1', 'inmetro_refrigerators', NULL, 690.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 57.5, 'kWh/mes'),
('5193731182fc56a7bf4f33defd5d373e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Panasonic|NR-BT50|5576/2017|220 V', 'Panasonic', 'NR-BT50', 'inmetro_refrigerators', NULL, 544.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 45.4, 'kWh/mes'),
('51d2df0c20475566a1b053ca6392a237'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Miele|KF 2901 Vi 127 Volts|001057/2020|127 V', 'Miele', 'KF 2901 Vi 127 Volts', 'inmetro_refrigerators', NULL, 402.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 33.5, 'kWh/mes'),
('524a085fc7d750b1b0314945850e49bf'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG85PL|003271/2019|220 V', 'Philco', 'PFG85PL', 'inmetro_refrigerators', NULL, 145.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 12.1, 'kWh/mes'),
('528154636412545ab7d051b1c313fc21'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Panasonic|NR-CB85|3738/2020|220 V', 'Panasonic', 'NR-CB85', 'inmetro_refrigerators', NULL, 792.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 66.0, 'kWh/mes'),
('5382eef17f0858fc94b6a553f1c48ada'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Battery tender (trickle charger)', NULL, NULL, 'WATTSIMPLE', 30.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('539577a914295979b0da93d0be974ed5'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRC12|005222/2016|220 V', 'CONSUL', 'CRC12', 'inmetro_refrigerators', NULL, 228.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 19.0, 'kWh/mes'),
('546b47ed218150dcab2602d6b35763d2'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Leaf blower (corded)', NULL, NULL, 'WATTSIMPLE', 1000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('546efd7440ae59a5be8abf6fee1e5b8b'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG50P|007591/2016|220 V', 'Philco', 'PFG50P', 'inmetro_refrigerators', NULL, 204.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 17.0, 'kWh/mes'),
('547215f99c2957f691af8a4ad8cf176e'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Midea|MRV10|001496/2017|220 V', 'Midea', 'MRV10', 'inmetro_refrigerators', NULL, 163.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 13.6, 'kWh/mes'),
('54c3fcd4189e50dd8be58ff1c4b8f2a3'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RS65R5411M9/BZ|004878/2019|220 V', 'Samsung', 'RS65R5411M9/BZ', 'inmetro_refrigerators', NULL, 656.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 54.7, 'kWh/mes'),
('553702b42c725fb3a347d4cd31a739f8'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RT53K6240S8/AZ|001495/2017|127 V', 'Samsung', 'RT53K6240S8/AZ', 'inmetro_refrigerators', NULL, 489.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 40.8, 'kWh/mes'),
('556f9be1e61458df904641034fa2f553'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Table saw', NULL, NULL, 'WATTSIMPLE', 1800.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('55ce4716107a5c1cb1212075db75a5c8'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRD46|005217/2016|127 V', 'CONSUL', 'CRD46', 'inmetro_refrigerators', NULL, 645.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 53.8, 'kWh/mes'),
('55cf6b24951e5ec69d340dad12e9dd39'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFH160B|003272/2019|127 V', 'Philco', 'PFH160B', 'inmetro_refrigerators', NULL, 334.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 27.9, 'kWh/mes'),
('574308a0fe3b5a87b99da7bc9b9fd7dc'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Midea|RCFB21|003109/2016|127 V', 'Midea', 'RCFB21', 'inmetro_refrigerators', NULL, 237.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 19.8, 'kWh/mes'),
('57a6fc019a465d80a922f48228d9d019'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF75PIXR|000222/2018|220 V', 'BERTAZZONI', 'REF75PIXR', 'inmetro_refrigerators', NULL, 447.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 37.3, 'kWh/mes'),
('57bfe2bddb6d5329bdd23bb5aee876ad'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRD46|005217/2016|220 V', 'CONSUL', 'CRD46', 'inmetro_refrigerators', NULL, 645.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 53.8, 'kWh/mes'),
('586a0f4f122c503d807ae5ebabaf0c30'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRO90|005218/2016|127 V', 'BRASTEMP', 'BRO90', 'inmetro_refrigerators', NULL, 780.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 65.0, 'kWh/mes'),
('586e0b048f1a58f198279251892d7ed5'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Electrolux|H222|005396/2016|220 V', 'Electrolux', 'H222', 'inmetro_refrigerators', NULL, 408.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 34.0, 'kWh/mes'),
('59c02c2e47c45654b2c3fb0c1c24eba1'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG50B|007591/2016|220 V', 'Philco', 'PFG50B', 'inmetro_refrigerators', NULL, 204.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 17.0, 'kWh/mes'),
('59caf48856dd5756b6fd9442b26b294e'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFV205I|004608/2020|127 V', 'Philco', 'PFV205I', 'inmetro_refrigerators', NULL, 384.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 32.0, 'kWh/mes'),
('59ea751a5c7e57f6834713f9b7b9969b'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF90X2|000222/2018|127 V', 'BERTAZZONI', 'REF90X2', 'inmetro_refrigerators', NULL, 608.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 50.7, 'kWh/mes'),
('5a8c7e0efa8055edbcfc9000b0db031c'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM54|005218/2016|220 V', 'BRASTEMP', 'BRM54', 'inmetro_refrigerators', NULL, 684.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 57.0, 'kWh/mes'),
('5a9e74b0d68c55c8a474c97b86c2f5dd'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRO90|005218/2016|220 V', 'BRASTEMP', 'BRO90', 'inmetro_refrigerators', NULL, 780.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 65.0, 'kWh/mes'),
('5ac5f191c4895a9f8470f59f83cad235'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|RFE39|005397/2016|127 V', 'Electrolux', 'RFE39', 'inmetro_refrigerators', NULL, 450.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 37.5, 'kWh/mes'),
('5b923af0c38456ebaab919ee8c51bc17'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RF27T5501SG/AZ|000243/2019|127 V', 'Samsung', 'RF27T5501SG/AZ', 'inmetro_refrigerators', NULL, 720.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 60.0, 'kWh/mes'),
('5beb2eb507595794980cedd08aa33e5d'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM50|005218/2016|220 V', 'CONSUL', 'CRM50', 'inmetro_refrigerators', NULL, 672.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 56.0, 'kWh/mes')
ON CONFLICT (id) DO UPDATE SET canonical_product_id = EXCLUDED.canonical_product_id, source = EXCLUDED.source, external_id = EXCLUDED.external_id, brand = EXCLUDED.brand, model = EXCLUDED.model, dataset_id = EXCLUDED.dataset_id, power_w = EXCLUDED.power_w, annual_energy_kwh = EXCLUDED.annual_energy_kwh, standby_power_w = EXCLUDED.standby_power_w, observed_at = EXCLUDED.observed_at, is_generic = EXCLUDED.is_generic, voltage_raw = EXCLUDED.voltage_raw, voltage_kind = EXCLUDED.voltage_kind, voltage_min_v = EXCLUDED.voltage_min_v, voltage_max_v = EXCLUDED.voltage_max_v, raw_energy_value = EXCLUDED.raw_energy_value, raw_energy_unit = EXCLUDED.raw_energy_unit;
INSERT INTO public.product_source_observation (id, canonical_product_id, source, external_id, brand, model, dataset_id, power_w, annual_energy_kwh, standby_power_w, observed_at, is_generic, voltage_raw, voltage_kind, voltage_min_v, voltage_max_v, raw_energy_value, raw_energy_unit) VALUES
('5d48174d3e855cd2afd7a6dcc45bc883'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Panasonic|NR-BB53|5576/2017|220 V', 'Panasonic', 'NR-BB53', 'inmetro_refrigerators', NULL, 478.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 39.9, 'kWh/mes'),
('5db5a7ead6445a78a5d1401c531261b9'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Electrolux|RE80|005401/2016|127 V', 'Electrolux', 'RE80', 'inmetro_refrigerators', NULL, 208.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 17.4, 'kWh/mes'),
('5e02848cb92a57f6909fbf5936108cbc'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Esmaltec|ROC35R|002251/2017|220 V', 'Esmaltec', 'ROC35R', 'inmetro_refrigerators', NULL, 262.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 21.9, 'kWh/mes'),
('5e0a29c7681f5f1e83249dd6654c4ea3'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'TECNO|TR14GXDA|004358/2020|127 V', 'TECNO', 'TR14GXDA', 'inmetro_refrigerators', NULL, 284.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 23.7, 'kWh/mes'),
('5e3960f64f97545681bf8cab86c6b7ce'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM56|005218/2016|127 V', 'BRASTEMP', 'BRM56', 'inmetro_refrigerators', NULL, 780.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 65.0, 'kWh/mes'),
('5e4acae3a3ab54e7b1946caa26fe758e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF36FDFIXNV|005435/2019|220 V', 'BERTAZZONI', 'REF36FDFIXNV', 'inmetro_refrigerators', NULL, 518.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 43.2, 'kWh/mes'),
('5ef736820df353598af5f0dd2ec0b51f'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG51B|001955/2017|220 V', 'Philco', 'PFG51B', 'inmetro_refrigerators', NULL, 192.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 16.0, 'kWh/mes'),
('6019e921c07955aaad01aa9e54e445a8'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GC-B659BSB / GC-B659BSB1|003968/2017|127 V', 'LG', 'GC-B659BSB / GC-B659BSB1', 'inmetro_refrigerators', NULL, 399.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 33.3, 'kWh/mes'),
('602851f127435584a66b9f62407bada0'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG125B|003271/2019|127 V', 'Philco', 'PFG125B', 'inmetro_refrigerators', NULL, 182.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 15.2, 'kWh/mes'),
('605740fc62545aebb9e407ec324a16b5'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF260RP|003507/2020|127 V', 'Philco', 'PRF260RP', 'inmetro_refrigerators', NULL, 420.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 35.0, 'kWh/mes'),
('606f1a376aec53a38569dc7915983540'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Stand mixer', NULL, NULL, 'WATTSIMPLE', 300.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('611f09bc3b8357ecaf70d7cf07f7d1f8'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Britânia|BFG85PL|003271/2019|220 V', 'Britânia', 'BFG85PL', 'inmetro_refrigerators', NULL, 145.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 12.1, 'kWh/mes'),
('626c493efe7d5577a61977f8e6d6b1da'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Well pump (1 HP)', NULL, NULL, 'WATTSIMPLE', 1500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('62bb4ca21ea25677b42fc1033864986b'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Panasonic|NR-BT50|5576/2017|127 V', 'Panasonic', 'NR-BT50', 'inmetro_refrigerators', NULL, 544.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 45.4, 'kWh/mes'),
('62d38c293efe54b2adef91c06f61057d'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|IB52_IB52X_IB53_IB53X|005404/2016|127 V', 'Electrolux', 'IB52_IB52X_IB53_IB53X', 'inmetro_refrigerators', NULL, 548.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 45.7, 'kWh/mes'),
('62de03cf091d5b71844c283abd1f18e5'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Water softener', NULL, NULL, 'WATTSIMPLE', 70.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('638b794efa295d58b2d89dd16f433575'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RT53K6240S8/BZ|001495/2017|220 V', 'Samsung', 'RT53K6240S8/BZ', 'inmetro_refrigerators', NULL, 489.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 40.8, 'kWh/mes'),
('643feb620e43544da4bad0290ebf3c9d'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'TECNO|TR45FXDA|005755/2019|127 V', 'TECNO', 'TR45FXDA', 'inmetro_refrigerators', NULL, 601.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 50.1, 'kWh/mes'),
('647ed1bb70d7582696cd982335d27b58'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'BRASTEMP|BVR28|005221/2016|220 V', 'BRASTEMP', 'BVR28', 'inmetro_refrigerators', NULL, 660.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 55.0, 'kWh/mes'),
('64854c8da3085b338f7db4c53a85609f'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Electric wall heater', NULL, NULL, 'WATTSIMPLE', 1500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('64a3fc728485580294056773a05d8659'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Fountain pump', NULL, NULL, 'WATTSIMPLE', 50.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('656bcc0e3ec9585381469961ce36451d'::uuid, '3c56d7551b375487a95a1882b9a6df57'::uuid, 'WATTSIMPLE', 'Range hood', NULL, NULL, 'WATTSIMPLE', 150.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('65dd613d0686559e82bcd7898597f331'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF520DIP|008370/2019|127 V', 'Philco', 'PRF520DIP', 'inmetro_refrigerators', NULL, 715.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 59.6, 'kWh/mes'),
('6615b40a7f3c56cca8808c0ed4bae11e'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CHA22|005219/2016|127 V', 'CONSUL', 'CHA22', 'inmetro_refrigerators', NULL, 432.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 36.0, 'kWh/mes'),
('6664686aebef53a4a507e397d09fc6a8'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRB39|005223/2016|127 V', 'CONSUL', 'CRB39', 'inmetro_refrigerators', NULL, 439.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 36.6, 'kWh/mes'),
('66ae7a37c26d544a8ac7ad79132d0738'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Panasonic|NR-BT42|5576/2017|127 V', 'Panasonic', 'NR-BT42', 'inmetro_refrigerators', NULL, 372.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 31.0, 'kWh/mes'),
('66c2a79a48f2599c8834a9f2baa88865'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Esmaltec|ROC31R|002251/2017|127 V', 'Esmaltec', 'ROC31R', 'inmetro_refrigerators', NULL, 282.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 23.5, 'kWh/mes'),
('66e1f22f7e3953478b99c8152f558f61'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM53|005218/2016|220 V', 'BRASTEMP', 'BRM53', 'inmetro_refrigerators', NULL, 684.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 57.0, 'kWh/mes'),
('67ca53c41c7f56bcbb6636480a7e70db'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM57|005218/2016|220 V', 'BRASTEMP', 'BRM57', 'inmetro_refrigerators', NULL, 828.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 69.0, 'kWh/mes'),
('67e5737ff5325456a6a8ee9508ed2f74'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Midea|MRC12B2|001496/2017|220 V', 'Midea', 'MRC12B2', 'inmetro_refrigerators', NULL, 171.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 14.3, 'kWh/mes'),
('67f78757fb9d5940b75887110fb18545'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Egg incubator', NULL, NULL, 'WATTSIMPLE', 100.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('6813d15946b75e0aa6b1be833339955d'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF533IPD|002671/2020|220 V', 'Philco', 'PRF533IPD', 'inmetro_refrigerators', NULL, 528.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 44.0, 'kWh/mes'),
('682a680558285853a837453e6659def7'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Midea|RCFB22|003109/2016|220 V', 'Midea', 'RCFB22', 'inmetro_refrigerators', NULL, 277.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 23.1, 'kWh/mes'),
('68516666855a5cfb8b176416ab550e26'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM52|005218/2016|127 V', 'CONSUL', 'CRM52', 'inmetro_refrigerators', NULL, 630.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 52.5, 'kWh/mes'),
('690ddcdcb0b85831b9a13a36ad9e50aa'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|GRO80|005218/2016|220 V', 'BRASTEMP', 'GRO80', 'inmetro_refrigerators', NULL, 872.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 72.7, 'kWh/mes'),
('69349d9bea055bcf83193ddab87bf3c5'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF90PRR|000222/2018|127 V', 'BERTAZZONI', 'REF90PRR', 'inmetro_refrigerators', NULL, 469.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 39.1, 'kWh/mes'),
('694e41044f355c77a70e6de6f3c5f46c'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRA30|005222/2016|220 V', 'CONSUL', 'CRA30', 'inmetro_refrigerators', NULL, 291.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 24.3, 'kWh/mes'),
('6a1521f92e73512ab0bed5519945fa6d'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Electrolux|FE26|005399/2016|127 V', 'Electrolux', 'FE26', 'inmetro_refrigerators', NULL, 524.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 43.7, 'kWh/mes'),
('6b72923038e25c03b49d58617b5508e0'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG107RV|001955/2017|127 V', 'Philco', 'PFG107RV', 'inmetro_refrigerators', NULL, 210.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 17.5, 'kWh/mes'),
('6b78b9d9cf4b590e8b0d685849c91ddf'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Britânia|BFH162B|003272/2019|127 V', 'Britânia', 'BFH162B', 'inmetro_refrigerators', NULL, 334.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 27.9, 'kWh/mes'),
('6c41857b23c25c589488d587d42eb2c7'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DF80_DF80X_DF82_DF82X|005404/2016|220 V', 'Electrolux', 'DF80_DF80X_DF82_DF82X', 'inmetro_refrigerators', NULL, 852.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 71.0, 'kWh/mes'),
('6c79223faee65d11abcfb48f8883ce59'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DF44_DF44S|005404/2016|220 V', 'Electrolux', 'DF44_DF44S', 'inmetro_refrigerators', NULL, 675.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 56.3, 'kWh/mes'),
('6ccae49fecb75c39b6a9ea51afc2744c'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF500I|008370/2019|127 V', 'Philco', 'PRF500I', 'inmetro_refrigerators', NULL, 534.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 44.5, 'kWh/mes'),
('6ce04a22c1ed5fa49ef34bbedf1cc7c6'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Electrolux|BEER2|006524/2018|127 V', 'Electrolux', 'BEER2', 'inmetro_refrigerators', NULL, 204.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 17.0, 'kWh/mes'),
('6ced8736984650cfb40fda81d6433ed4'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DM85X_DM86X_DM86V|005404/2016|220 V', 'Electrolux', 'DM85X_DM86X_DM86V', 'inmetro_refrigerators', NULL, 828.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 69.0, 'kWh/mes'),
('6d8d4159852859208bfd1654b1bcb4fd'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Toshiba|GR-RF646WEPMA|002669/2020|220 V', 'Toshiba', 'GR-RF646WEPMA', 'inmetro_refrigerators', NULL, 698.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 58.2, 'kWh/mes'),
('6dad539dbb93564ea0f749929a803d63'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM56|005218/2016|220 V', 'CONSUL', 'CRM56', 'inmetro_refrigerators', NULL, 708.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 59.0, 'kWh/mes'),
('6e0086f9240a532b936cfcfff6b6adb7'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM58|005218/2016|220 V', 'BRASTEMP', 'BRM58', 'inmetro_refrigerators', NULL, 828.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 69.0, 'kWh/mes'),
('6e723f6038c9546889bc3e4ab4133cb1'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Toaster', NULL, NULL, 'WATTSIMPLE', 1100.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('6e90749efafc5c9aaba86ecbeccc3f1f'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRE58|005218/2016|127 V', 'BRASTEMP', 'BRE58', 'inmetro_refrigerators', NULL, 828.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 69.0, 'kWh/mes'),
('6f1fa6ac458c5d87afd10ba5a9bd53ae'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Miele|KF 2901 Vi 220 Volts|003340/2021|220 V', 'Miele', 'KF 2901 Vi 220 Volts', 'inmetro_refrigerators', NULL, 355.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 29.6, 'kWh/mes'),
('6f91cce3b3ff5a13b88eb8f565fb9294'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRS62|005218/2016|127 V', 'BRASTEMP', 'BRS62', 'inmetro_refrigerators', NULL, 804.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 67.0, 'kWh/mes'),
('6fe5d886d0c45baa9578917402da08bc'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM35|005218/2016|220 V', 'CONSUL', 'CRM35', 'inmetro_refrigerators', NULL, 494.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 41.2, 'kWh/mes'),
('701491ef7a6a5e919013b72ed5b7b659'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'BRASTEMP|BVG24|005221/2016|127 V', 'BRASTEMP', 'BVG24', 'inmetro_refrigerators', NULL, 636.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 53.0, 'kWh/mes'),
('707fc9998c825200b3c1b3cf7f20a328'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Midea|MRC12B1|001496/2017|127 V', 'Midea', 'MRC12B1', 'inmetro_refrigerators', NULL, 175.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 14.6, 'kWh/mes'),
('709d4757853457ba8612021ff2e7602f'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFH205B|003272/2019|220 V', 'Philco', 'PFH205B', 'inmetro_refrigerators', NULL, 386.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 32.2, 'kWh/mes'),
('709e0078bc8f502a8e0f45a588d02f27'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRD36|005217/2016|220 V', 'CONSUL', 'CRD36', 'inmetro_refrigerators', NULL, 522.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 43.5, 'kWh/mes'),
('71ec8cddf91650ee971c0a45b8b6477a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF90X|000222/2018|127 V', 'BERTAZZONI', 'REF90X', 'inmetro_refrigerators', NULL, 608.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 50.7, 'kWh/mes'),
('720cae2bfddb5d00bf8e4b9364adc493'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFH515B|002580/2017|220 V', 'Philco', 'PFH515B', 'inmetro_refrigerators', NULL, 768.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 64.0, 'kWh/mes'),
('72f132592b3752bc98b4d833283baced'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Britânia|BRF533ID|002671/2020|220 V', 'Britânia', 'BRF533ID', 'inmetro_refrigerators', NULL, 528.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 44.0, 'kWh/mes'),
('7323e80a4c915057955adc24c2d38177'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM54|005218/2016|127 V', 'BRASTEMP', 'BRM54', 'inmetro_refrigerators', NULL, 684.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 57.0, 'kWh/mes'),
('7363ebb56695518aa3224d2d42f06ff9'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRE44|005218/2016|127 V', 'CONSUL', 'CRE44', 'inmetro_refrigerators', NULL, 696.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 58.0, 'kWh/mes'),
('7367e7028be4564a90f0f08239b223e5'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'EOS|EFH350X|003659/2020|127 V', 'EOS', 'EFH350X', 'inmetro_refrigerators', NULL, 444.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 37.0, 'kWh/mes'),
('737c5f4e6cee59daadba988104ee3cde'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF600I|003507/2020|127 V', 'Philco', 'PRF600I', 'inmetro_refrigerators', NULL, 588.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 49.0, 'kWh/mes'),
('742f9f9765a65b698193dbed13d1af80'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Infrared heater', NULL, NULL, 'WATTSIMPLE', 1500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('7452145e68005e979045cf0b14f14de4'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RL4363RBASL/BZ|001495/2017|220 V', 'Samsung', 'RL4363RBASL/BZ', 'inmetro_refrigerators', NULL, 462.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 38.5, 'kWh/mes'),
('74d04b5dcdb55627b2df51064aaf033f'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG50B|003271/2019|220 V', 'Philco', 'PFG50B', 'inmetro_refrigerators', NULL, 144.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 12.0, 'kWh/mes'),
('7556d41b0f515944b884770867a93f8d'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DM83X_DM84X|005404/2016|127 V', 'Electrolux', 'DM83X_DM84X', 'inmetro_refrigerators', NULL, 900.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 75.0, 'kWh/mes'),
('75d5903f55045817b3a1c1e68edf9e7f'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Whirlpool tub pump', NULL, NULL, 'WATTSIMPLE', 1000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('762936eea814516c9ca3d2e21c211167'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Espresso machine', NULL, NULL, 'WATTSIMPLE', 1300.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('765464e95eb25a9492674936ba9b2a8f'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRD49|005217/2016|127 V', 'CONSUL', 'CRD49', 'inmetro_refrigerators', NULL, 696.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 58.0, 'kWh/mes'),
('766afe3c3d07560f836283f1ad6d4a68'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Electrolux|FE18|005399/2016|127 V', 'Electrolux', 'FE18', 'inmetro_refrigerators', NULL, 501.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 41.8, 'kWh/mes'),
('7685ed18b63655fd92d45765d2697bd3'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Slow cooker', NULL, NULL, 'WATTSIMPLE', 200.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('768bc91148d259489dc3b3d09e43f3e9'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DFN39_DFX39_TF39_TF39S|005404/2016|127 V', 'Electrolux', 'DFN39_DFX39_TF39_TF39S', 'inmetro_refrigerators', NULL, 523.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 43.6, 'kWh/mes'),
('76a2068e73ca5b2d87097e1d06442bf1'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Treadmill', NULL, NULL, 'WATTSIMPLE', 700.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('76b5cc572abb5cfba6061f32940ca0bd'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG50P|007591/2016|127 V', 'Philco', 'PFG50P', 'inmetro_refrigerators', NULL, 204.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 17.0, 'kWh/mes'),
('76b7934a11f65fabad2dbca3b6ed8d05'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|GRO80|005218/2016|127 V', 'BRASTEMP', 'GRO80', 'inmetro_refrigerators', NULL, 872.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 72.7, 'kWh/mes'),
('7710cae68d4c50ccbb2358f98568cf9a'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CVT10|005220/2016|220 V', 'CONSUL', 'CVT10', 'inmetro_refrigerators', NULL, 420.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 35.0, 'kWh/mes'),
('7715f51bfb4e5ecf8d19370225eff60f'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GS65SDN / GS65SDN1|003968/2017|220 V', 'LG', 'GS65SDN / GS65SDN1', 'inmetro_refrigerators', NULL, 690.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 57.5, 'kWh/mes'),
('776202088b2e5d6d876fbea7964bf337'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM43|005218/2016|220 V', 'CONSUL', 'CRM43', 'inmetro_refrigerators', NULL, 669.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 55.8, 'kWh/mes'),
('78afe03460e4547da3c3abe10b80b50f'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Miele|KS 37472 iD|001051/2020|220 V', 'Miele', 'KS 37472 iD', 'inmetro_refrigerators', NULL, 187.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 15.6, 'kWh/mes'),
('78e980ec7aa350119a884ca5c7b0ded6'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Central AC (3 ton)', NULL, NULL, 'WATTSIMPLE', 3500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('796c5269cc75583bad070d08d8ab93c4'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DF80_DF80X_DF82_DF82X|005404/2016|127 V', 'Electrolux', 'DF80_DF80X_DF82_DF82X', 'inmetro_refrigerators', NULL, 852.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 71.0, 'kWh/mes'),
('7a45076e6bcd57a8b062ebc415627f5f'::uuid, '8158deed5e4c55db9f8fcfbedbe6c2eb'::uuid, 'WATTSIMPLE', 'Heat-pump water heater', NULL, NULL, 'WATTSIMPLE', 550.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('7a6e31864ce4512799c0846533a8bdd0'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFZ330B|003272/2019|127 V', 'Philco', 'PFZ330B', 'inmetro_refrigerators', NULL, 430.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 35.9, 'kWh/mes'),
('7a9aaed93c6f55f78f76b8f22cf92ad6'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DFN41_DFX41|005404/2016|220 V', 'Electrolux', 'DFN41_DFX41', 'inmetro_refrigerators', NULL, 651.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 54.3, 'kWh/mes'),
('7aeefe4c08725c5ab4eb89b9c9d169b1'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RT46K6A4KS9/FZ|001495/2017|127 V', 'Samsung', 'RT46K6A4KS9/FZ', 'inmetro_refrigerators', NULL, 499.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 41.6, 'kWh/mes'),
('7afa2c5def7454e2be222ba743e314bb'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRA08|005222/2016|220 V', 'BRASTEMP', 'BRA08', 'inmetro_refrigerators', NULL, 210.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 17.5, 'kWh/mes'),
('7b6cf5507c7a5c78b43e6c7498502f79'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG85PL|003271/2019|127 V', 'Philco', 'PFG85PL', 'inmetro_refrigerators', NULL, 148.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 12.4, 'kWh/mes'),
('7b9ce849bbe1591b86d5ae3a50455e22'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Midea|MRC08|001496/2017|220 V', 'Midea', 'MRC08', 'inmetro_refrigerators', NULL, 156.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 13.0, 'kWh/mes'),
('7be810de5d925e2cb540bf9b27997139'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Electrolux|H330|004053/2020|127 V', 'Electrolux', 'H330', 'inmetro_refrigerators', NULL, 555.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 46.3, 'kWh/mes'),
('7bfc5002dba55c319e8b5dfb7e040a7f'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'EOS|EFH550XX|003659/2020|220 V', 'EOS', 'EFH550XX', 'inmetro_refrigerators', NULL, 733.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 61.1, 'kWh/mes'),
('7c0c889a2ed75b2192b17f329d1de94c'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG95B|007591/2016|220 V', 'Philco', 'PFG95B', 'inmetro_refrigerators', NULL, 216.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 18.0, 'kWh/mes'),
('7cb689a399a25ad6a924078082959ab9'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRA30|005222/2016|127 V', 'CONSUL', 'CRA30', 'inmetro_refrigerators', NULL, 291.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 24.3, 'kWh/mes'),
('7d1fc571df2056c2b6dba81c5260ab68'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DM85X_DM86X_DM86V|005404/2016|127 V', 'Electrolux', 'DM85X_DM86X_DM86V', 'inmetro_refrigerators', NULL, 828.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 69.0, 'kWh/mes'),
('7d98148217a65f61b688bc210aca30a3'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|RFE39|005397/2016|220 V', 'Electrolux', 'RFE39', 'inmetro_refrigerators', NULL, 450.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 37.5, 'kWh/mes'),
('7dea7bab6114518daa7a2606710739f4'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM45|005218/2016|127 V', 'CONSUL', 'CRM45', 'inmetro_refrigerators', NULL, 630.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 52.5, 'kWh/mes'),
('7e82436635365701bedfb4f86b06c444'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|H200L|002580/2017|127 V', 'Philco', 'H200L', 'inmetro_refrigerators', NULL, 414.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 34.5, 'kWh/mes'),
('7ea0fe488ea8584f8d78ab4f2ad2e2f5'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'TECNO|TR65FXDA|005435/2019|220 V', 'TECNO', 'TR65FXDA', 'inmetro_refrigerators', NULL, 518.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 43.2, 'kWh/mes'),
('7ea4595707155412801a86c717e01dc0'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Garment steamer', NULL, NULL, 'WATTSIMPLE', 1500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('7f22d3607653538385b109090af67d12'::uuid, 'be389ae923875726a7dffeeda9b2e4c4'::uuid, 'WATTSIMPLE', 'Tankless electric water heater (18 kW)', NULL, NULL, 'WATTSIMPLE', 18000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('7f8e07bafdff530b8c6a781dab38b908'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRE59|005218/2016|127 V', 'BRASTEMP', 'BRE59', 'inmetro_refrigerators', NULL, 804.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 67.0, 'kWh/mes'),
('7fa5e76ac4f15214bbd905ef051ead31'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF90PIXR|000222/2018|220 V', 'BERTAZZONI', 'REF90PIXR', 'inmetro_refrigerators', NULL, 469.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 39.1, 'kWh/mes'),
('7fbbaa282dfd529e92b63e8ab626bef4'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Miele|KFNS 37692 IDE|004923/2020|220 V', 'Miele', 'KFNS 37692 IDE', 'inmetro_refrigerators', NULL, 306.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 25.5, 'kWh/mes'),
('7ff6702089d15f4bb5054d9bcffa152b'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RF27T5501SG/BZ|000243/2019|220 V', 'Samsung', 'RF27T5501SG/BZ', 'inmetro_refrigerators', NULL, 720.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 60.0, 'kWh/mes'),
('8005977467a653588b775ed9a03c18a2'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Miele|F 2411 Vi 127 volts|001052/2020|127 V', 'Miele', 'F 2411 Vi 127 volts', 'inmetro_refrigerators', NULL, 426.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 35.5, 'kWh/mes'),
('800e5e61bca1528e957bf14aea8b4a8c'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF504ID|001056/2020|127 V', 'Philco', 'PRF504ID', 'inmetro_refrigerators', NULL, 612.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 51.0, 'kWh/mes'),
('8075e12836e85318b0b71752058b6f8c'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Midea|MD-RT453FGA041|002748/2020|127 V', 'Midea', 'MD-RT453FGA041', 'inmetro_refrigerators', NULL, 535.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 44.6, 'kWh/mes'),
('80df0f559afa5ff1aa36d0278f1ed187'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Mini fridge', NULL, NULL, 'WATTSIMPLE', 70.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('8150944038955237862b0fff8aed20ce'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM43|005218/2016|127 V', 'CONSUL', 'CRM43', 'inmetro_refrigerators', NULL, 669.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 55.8, 'kWh/mes'),
('817c2625808059b78701071b4da6f210'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Midea|RCFB32|003109/2016|220 V', 'Midea', 'RCFB32', 'inmetro_refrigerators', NULL, 430.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 35.9, 'kWh/mes'),
('819f189d43bd500cbfcc194cf3a5c451'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Window AC (10k BTU)', NULL, NULL, 'WATTSIMPLE', 1200.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('81f3ab54e0725d3aa23168716a2af67d'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GC-B659BSB / GC-B659BSB1|003968/2017|220 V', 'LG', 'GC-B659BSB / GC-B659BSB1', 'inmetro_refrigerators', NULL, 399.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 33.3, 'kWh/mes'),
('8402e6e86b725a1586a132727c37a4ba'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Continental|TC44_TC44S|005404/2016|220 V', 'Continental', 'TC44_TC44S', 'inmetro_refrigerators', NULL, 663.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 55.3, 'kWh/mes'),
('84097b51fbbc5bd38b39aae31f05153e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DW44S|005404/2016|127 V', 'Electrolux', 'DW44S', 'inmetro_refrigerators', NULL, 675.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 56.3, 'kWh/mes'),
('842d33c4568e536ba36827a9af3b4bfe'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Miele|F 2811 Vi 220 Volts|00579/2021|220 V', 'Miele', 'F 2811 Vi 220 Volts', 'inmetro_refrigerators', NULL, 546.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 45.5, 'kWh/mes'),
('84fb5f9301a05d2ea020157dde72584c'::uuid, '32bc03267d0a5a009753fd6f5f31723e'::uuid, 'WATTSIMPLE', 'Fluorescent shop light (2× T8)', NULL, NULL, 'WATTSIMPLE', 60.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('857baa134c17548fa750131af651892f'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Robot vacuum (charging)', NULL, NULL, 'WATTSIMPLE', 40.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('8589043f89675c65b2076b5923057094'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF411I|002671/2020|127 V', 'Philco', 'PRF411I', 'inmetro_refrigerators', NULL, 456.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 38.0, 'kWh/mes'),
('8646e7b730a55d529569afeb18624a1f'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFH105B|003272/2019|220 V', 'Philco', 'PFH105B', 'inmetro_refrigerators', NULL, 276.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 23.0, 'kWh/mes'),
('86fdedda3a035d1c804f730a1ee9357c'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Heated birdbath', NULL, NULL, 'WATTSIMPLE', 60.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('876eeff51ee05635b1e881bda8bc9115'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG50B|007591/2016|127 V', 'Philco', 'PFG50B', 'inmetro_refrigerators', NULL, 204.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 17.0, 'kWh/mes'),
('87cd5ea76249588594caa4752461e577'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PFG100RV|000963/2021|220 V', 'Philco', 'PFG100RV', 'inmetro_refrigerators', NULL, 266.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 22.2, 'kWh/mes'),
('87d4efd8f14c506c9d492047d4a3b4ee'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Rice cooker', NULL, NULL, 'WATTSIMPLE', 500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('8817ede703ab57a2aa63b4aeb5a93b8b'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Midea|CBA10|003109/2016|220 V', 'Midea', 'CBA10', 'inmetro_refrigerators', NULL, 210.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 17.5, 'kWh/mes'),
('88ac3aee82e15b64b0b38a30e7ef22a3'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Panasonic|NR-BB71|5576/2017|220 V', 'Panasonic', 'NR-BB71', 'inmetro_refrigerators', NULL, 490.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 40.9, 'kWh/mes'),
('89168df0b6c15cd79d7c8d17994663b6'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GT44BPP / GT44BPP1|003968/2017|127 V', 'LG', 'GT44BPP / GT44BPP1', 'inmetro_refrigerators', NULL, 415.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 34.6, 'kWh/mes'),
('892652b5b56c5133b5c97b119ce354f7'::uuid, '44b152237bec5d678facdb985e3e01c5'::uuid, 'WATTSIMPLE', 'Laptop', NULL, NULL, 'WATTSIMPLE', 60.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('8a3e2823a90a563aa833d9d0aee9cf2e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GC-L247SLUV / GC-L247SLU1|003968/2017|220 V', 'LG', 'GC-L247SLUV / GC-L247SLU1', 'inmetro_refrigerators', NULL, 690.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 57.5, 'kWh/mes'),
('8cbcdbdbc270554f8e9c2cd08631f1c9'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RF23R6201SR/AZ|007317/2017|127 V', 'Samsung', 'RF23R6201SR/AZ', 'inmetro_refrigerators', NULL, 720.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 60.0, 'kWh/mes'),
('8dbbd82bcd095686976dd9ee789a4404'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Midea|MRC10B1|001496/2017|127 V', 'Midea', 'MRC10B1', 'inmetro_refrigerators', NULL, 170.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 14.2, 'kWh/mes'),
('8de3e9e2eb795a7fbec5bf154a33462d'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Gorenje|ONR192BK, NRK6192UX|002863/2017|220 V', 'Gorenje', 'ONR192BK, NRK6192UX', 'inmetro_refrigerators', NULL, 350.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 29.2, 'kWh/mes'),
('8e2088b2f0a9555390d3f4400bf1c860'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF75PIXR|000222/2018|127 V', 'BERTAZZONI', 'REF75PIXR', 'inmetro_refrigerators', NULL, 447.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 37.3, 'kWh/mes'),
('8e480ce03aac5e85b55c9dda885b5330'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG90I|007591/2016|220 V', 'Philco', 'PFG90I', 'inmetro_refrigerators', NULL, 216.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 18.0, 'kWh/mes'),
('8ead46ea69a95a25b378ab97f31059a3'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Britânia|BFG85B|003271/2019|220 V', 'Britânia', 'BFG85B', 'inmetro_refrigerators', NULL, 145.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 12.1, 'kWh/mes'),
('8eceea51d0f55925a9e57f07bc44d1d3'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Engine block heater', NULL, NULL, 'WATTSIMPLE', 800.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('8fb749b68f955a93af2cf9307f4378c8'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFH205B|003272/2019|127 V', 'Philco', 'PFH205B', 'inmetro_refrigerators', NULL, 414.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 34.5, 'kWh/mes'),
('8fbcf3e3bdf355988cf85eca3ce28e50'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFV205B|004608/2020|220 V', 'Philco', 'PFV205B', 'inmetro_refrigerators', NULL, 384.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 32.0, 'kWh/mes'),
('9000c9714701524a9dd2403ae7c055dc'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Galanz|GFb12C01A-Ix127
GFb12C01A-Pt127
GFb12C01A-Br127
GFb12C01A-Ix220
GFb12C01A-Pt220
GFb12C01A-Br220|004319/2020|127 V', 'Galanz', 'GFb12C01A-Ix127
GFb12C01A-Pt127
GFb12C01A-Br127
GFb12C01A-Ix220
GFb12C01A-Pt220
GFb12C01A-Br220', 'inmetro_refrigerators', NULL, 289.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 24.1, 'kWh/mes'),
('90ecaa9b62465adebc63a76863e06b37'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CHB42|005219/2016|127 V', 'CONSUL', 'CHB42', 'inmetro_refrigerators', NULL, 699.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 58.3, 'kWh/mes'),
('911a359e2ca6530799c1c60223721ee5'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM50|005218/2016|127 V', 'CONSUL', 'CRM50', 'inmetro_refrigerators', NULL, 672.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 56.0, 'kWh/mes'),
('912bae2489cb5df9adb46cbbc1eb9621'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GC-L228FTLK / GC-L228FTL1|003968/2017|220 V', 'LG', 'GC-L228FTLK / GC-L228FTL1', 'inmetro_refrigerators', NULL, 684.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 57.0, 'kWh/mes'),
('916aa79e0e3b5f0d8348004aaafe52c7'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Gorenje|RI5182A1|005038/2019|220 V', 'Gorenje', 'RI5182A1', 'inmetro_refrigerators', NULL, 189.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 15.8, 'kWh/mes'),
('9256d900ff4d50b6a10d3e9bfc34a8bf'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|IF55_IF55S_IF55B|005404/2016|220 V', 'Electrolux', 'IF55_IF55S_IF55B', 'inmetro_refrigerators', NULL, 423.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 35.3, 'kWh/mes'),
('926f2ab34e2f5222b4aa75fd01c70f3a'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFV205I|004608/2020|220 V', 'Philco', 'PFV205I', 'inmetro_refrigerators', NULL, 384.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 32.0, 'kWh/mes'),
('93a2a597e2ef5a35b0e511e91f27df7b'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Midea|RCFB31|003109/2016|127 V', 'Midea', 'RCFB31', 'inmetro_refrigerators', NULL, 492.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 41.0, 'kWh/mes'),
('93eae7e46f345f91a0fb53404b7c521e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF503TI|003507/2020|220 V', 'Philco', 'PRF503TI', 'inmetro_refrigerators', NULL, 432.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 36.0, 'kWh/mes'),
('94d10d7b58b25ca1a3cefe2df6555ea2'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CVU26Z|005220/2016|220 V', 'CONSUL', 'CVU26Z', 'inmetro_refrigerators', NULL, 470.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 39.2, 'kWh/mes'),
('9510561e2d1f579eb0178fcc45340fa2'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG50B|003271/2019|127 V', 'Philco', 'PFG50B', 'inmetro_refrigerators', NULL, 141.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 11.8, 'kWh/mes'),
('959986dd24a65069b2b33eeb9b289729'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG107RV|001955/2017|220 V', 'Philco', 'PFG107RV', 'inmetro_refrigerators', NULL, 210.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 17.5, 'kWh/mes'),
('96f9b171d453590b841f5eeb61430361'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Britânia|BFG50B|007591/2016|127 V', 'Britânia', 'BFG50B', 'inmetro_refrigerators', NULL, 204.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 17.0, 'kWh/mes'),
('9772d0096d5d59628ccaed6a7e24db5e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RS65R5691M9/BZ|004878/2019|220 V', 'Samsung', 'RS65R5691M9/BZ', 'inmetro_refrigerators', NULL, 710.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 59.2, 'kWh/mes'),
('979535222bdb5b35baa14a50a5f269ab'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Countertop ice maker', NULL, NULL, 'WATTSIMPLE', 150.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('97dba6e2333a559ba2342041cfb37b24'::uuid, '32bc03267d0a5a009753fd6f5f31723e'::uuid, 'WATTSIMPLE', 'Heat lamp (250 W)', NULL, NULL, 'WATTSIMPLE', 250.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('988110082177548a8239e15027f04a03'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM54|005218/2016|127 V', 'CONSUL', 'CRM54', 'inmetro_refrigerators', NULL, 672.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 56.0, 'kWh/mes'),
('98a5d7b949755a2da1174cd0efcea6ae'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF406I|008370/2019|127 V', 'Philco', 'PRF406I', 'inmetro_refrigerators', NULL, 480.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 40.0, 'kWh/mes'),
('98b6f4e2f2c65c83b5c91a980acb8df4'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFH260B|002580/2017|127 V', 'Philco', 'PFH260B', 'inmetro_refrigerators', NULL, 456.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 38.0, 'kWh/mes'),
('98d16ceca1c8561a8747161a1253fcaa'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Crissair|RFD 01|004457/2018|127 V', 'Crissair', 'RFD 01', 'inmetro_refrigerators', NULL, 673.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 56.1, 'kWh/mes'),
('98f6872f74aa5d069c7b4f305a39bbd7'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'TECNO|TR14GXDA|004358/2020|220 V', 'TECNO', 'TR14GXDA', 'inmetro_refrigerators', NULL, 284.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 23.7, 'kWh/mes'),
('9964b28edb1c5976bbd1bf1516262fb9'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG85ICE|003271/2019|220 V', 'Philco', 'PFG85ICE', 'inmetro_refrigerators', NULL, 145.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 12.1, 'kWh/mes'),
('998e864afb675928aed574e7c87912c2'::uuid, 'b0a058f4cfe75882a3550c0298f5ec68'::uuid, 'WATTSIMPLE', 'Air fryer', NULL, NULL, 'WATTSIMPLE', 1500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('99c36853f9c35c858b4dc82b78687be0'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Britânia|BFH162B|003272/2019|220 V', 'Britânia', 'BFH162B', 'inmetro_refrigerators', NULL, 309.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 25.8, 'kWh/mes'),
('99c6fa862462527f90e31470e3236916'::uuid, 'b9d0e8a295d95ec9916ba71cc0771ea8'::uuid, 'WATTSIMPLE', 'Pool pump', NULL, NULL, 'WATTSIMPLE', 1100.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('9a9293745b6d5118b3418c31a9114c54'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|TW42S|005404/2016|127 V', 'Electrolux', 'TW42S', 'inmetro_refrigerators', NULL, 636.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 53.0, 'kWh/mes'),
('9a986fc507f6545abb64882bb07d131e'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Miele|F 2911 Vi 127 Volts|001052/2020|127 V', 'Miele', 'F 2911 Vi 127 Volts', 'inmetro_refrigerators', NULL, 601.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 50.1, 'kWh/mes'),
('9ac7f424ced558b49a688b779e7b7c69'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Electrolux|BEER2|006524/2018|220 V', 'Electrolux', 'BEER2', 'inmetro_refrigerators', NULL, 204.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 17.0, 'kWh/mes'),
('9b30f219aec35c7da7bda09c70942bed'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PFG121RV|000963/2021|220 V', 'Philco', 'PFG121RV', 'inmetro_refrigerators', NULL, 234.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 19.5, 'kWh/mes'),
('9b4f120fbc6d5215a509f4d397c09823'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Viking Range|VCFB5303 / FDFB5303|001954/2017|127 V', 'Viking Range', 'VCFB5303 / FDFB5303', 'inmetro_refrigerators', NULL, 1296.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 108.0, 'kWh/mes'),
('9b6f2709ccdf512f8afd50b33eb82f57'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RF23R6301SR/BZ|007317/2017|220 V', 'Samsung', 'RF23R6301SR/BZ', 'inmetro_refrigerators', NULL, 840.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 70.0, 'kWh/mes'),
('9b75919cd21e5bb986d840a5bfaf7361'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Elettromec|RF-BF-360-VT-2HMC / RF-BF-360-XX-2HMC|001451/2018|220 V', 'Elettromec', 'RF-BF-360-VT-2HMC / RF-BF-360-XX-2HMC', 'inmetro_refrigerators', NULL, 292.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 24.4, 'kWh/mes'),
('9be3181136195aa7ac54a853f242de65'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GT51BPP / GT51BPP1|006368/2019|127 V', 'LG', 'GT51BPP / GT51BPP1', 'inmetro_refrigerators', NULL, 522.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 43.5, 'kWh/mes'),
('9bfb3c55f096561b9661fe7794d297c2'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Britânia|BFG85B|003271/2019|127 V', 'Britânia', 'BFG85B', 'inmetro_refrigerators', NULL, 148.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 12.4, 'kWh/mes'),
('9c8a7f47ae9659ddb491e6cbedb8a940'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Toshiba|GR-RF646WEPMA|002669/2020|127 V', 'Toshiba', 'GR-RF646WEPMA', 'inmetro_refrigerators', NULL, 718.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 59.9, 'kWh/mes'),
('9cacfc52dba15977bf0abd9dc27a5ee1'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM52|005218/2016|220 V', 'CONSUL', 'CRM52', 'inmetro_refrigerators', NULL, 630.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 52.5, 'kWh/mes'),
('9cdc39d0bb535edfbe21eb42dc981916'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Britânia|BFG50B|003271/2019|220 V', 'Britânia', 'BFG50B', 'inmetro_refrigerators', NULL, 144.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 12.0, 'kWh/mes'),
('9d275505ff305c53aac0cd3199635f65'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CHA31|005219/2016|127 V', 'CONSUL', 'CHA31', 'inmetro_refrigerators', NULL, 554.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 46.2, 'kWh/mes'),
('9d616033a31d57ea91bea638e538b0ae'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG112B|001955/2017|127 V', 'Philco', 'PFG112B', 'inmetro_refrigerators', NULL, 198.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 16.5, 'kWh/mes'),
('9f2a935f27a45116b4c8e79cbbdb960c'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF520DI|008370/2019|127 V', 'Philco', 'PRF520DI', 'inmetro_refrigerators', NULL, 715.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 59.6, 'kWh/mes'),
('9f6e08e83bff590b95bfbacf0911e766'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RF59A7011SR/BZ|007317/2017|220 V', 'Samsung', 'RF59A7011SR/BZ', 'inmetro_refrigerators', NULL, 720.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 60.0, 'kWh/mes'),
('9fc1f8194b305fc4802c5f16b099f55a'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CVT10|005220/2016|127 V', 'CONSUL', 'CVT10', 'inmetro_refrigerators', NULL, 420.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 35.0, 'kWh/mes'),
('9fe886072f8752eaa7dcf39613cb2ed7'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Britânia|BFG85PL|003271/2019|127 V', 'Britânia', 'BFG85PL', 'inmetro_refrigerators', NULL, 148.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 12.4, 'kWh/mes'),
('a080e815bb525c649acbf318d93a4ad7'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM56|005218/2016|220 V', 'BRASTEMP', 'BRM56', 'inmetro_refrigerators', NULL, 780.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 65.0, 'kWh/mes'),
('a16250618f1651d1848ea5043600ba41'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Midea|CBA10|003109/2016|127 V', 'Midea', 'CBA10', 'inmetro_refrigerators', NULL, 249.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 20.8, 'kWh/mes'),
('a18498fdbbeb5be3bd97c1c16ec39720'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Miele|F 2411 Vi 220 Volts|003476/2021|220 V', 'Miele', 'F 2411 Vi 220 Volts', 'inmetro_refrigerators', NULL, 397.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 33.1, 'kWh/mes'),
('a1949539ad7c50e7b07288ac8d38790f'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFV205B|004608/2020|127 V', 'Philco', 'PFV205B', 'inmetro_refrigerators', NULL, 384.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 32.0, 'kWh/mes'),
('a1ac7e71882053b98f3cbf974d22fc4f'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Esmaltec|RCD38|002252/2017|220 V', 'Esmaltec', 'RCD38', 'inmetro_refrigerators', NULL, 492.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 41.0, 'kWh/mes'),
('a2e833b98cab5805bbba7795d8975943'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'MIG welder (240 V)', NULL, NULL, 'WATTSIMPLE', 4000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('a309a3820e7b5ddf94b3ddf2a664141b'::uuid, '37d947f088cc55f1be5bd59977d45976'::uuid, 'WATTSIMPLE', 'Upright freezer', NULL, NULL, 'WATTSIMPLE', 150.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('a373394bf7c75f11b94f627a5524fd64'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Patio heater (electric)', NULL, NULL, 'WATTSIMPLE', 1500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('a3d5554ffa9e53479d395e55dedfeb33'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'LED TV (75")', NULL, NULL, 'WATTSIMPLE', 150.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('a42855d8ced05aa899826b511257e48b'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRE80|005218/2016|220 V', 'BRASTEMP', 'BRE80', 'inmetro_refrigerators', NULL, 816.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 68.0, 'kWh/mes'),
('a45aac41fcad56f3bfb6b648b64ac07b'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Soundbar', NULL, NULL, 'WATTSIMPLE', 30.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('a4bb0cef657251f9aff3cf225c4c724e'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Electrolux|H222|005396/2016|127 V', 'Electrolux', 'H222', 'inmetro_refrigerators', NULL, 408.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 34.0, 'kWh/mes'),
('a547a9e2a9615830a205582974562cb8'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRC08|005222/2016|127 V', 'CONSUL', 'CRC08', 'inmetro_refrigerators', NULL, 210.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 17.5, 'kWh/mes'),
('a562137e1b2c58498683a29f8958bcf3'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRA08|005222/2016|127 V', 'BRASTEMP', 'BRA08', 'inmetro_refrigerators', NULL, 210.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 17.5, 'kWh/mes'),
('a56801d076c055cb84562e1e8bece0dc'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF75PRR|000222/2018|127 V', 'BERTAZZONI', 'REF75PRR', 'inmetro_refrigerators', NULL, 447.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 37.3, 'kWh/mes'),
('a5f6a26aa1845ad297023df2a1a9cc84'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFH440B|003272/2019|127 V', 'Philco', 'PFH440B', 'inmetro_refrigerators', NULL, 429.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 35.8, 'kWh/mes'),
('a66aa67359e656ab92c4978181a4fa0f'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Britânia|BFG111B|003271/2019|127 V', 'Britânia', 'BFG111B', 'inmetro_refrigerators', NULL, 198.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 16.5, 'kWh/mes'),
('a68f393f3be85662be3c947bad178608'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF90PRL|000222/2018|127 V', 'BERTAZZONI', 'REF90PRL', 'inmetro_refrigerators', NULL, 469.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 39.1, 'kWh/mes'),
('a6c5fe9df2165c99aac8f7c850213335'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DQ90X|000514/2018|220 V', 'Electrolux', 'DQ90X', 'inmetro_refrigerators', NULL, 750.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 62.5, 'kWh/mes'),
('a749cdf0741d5e929a9b2a69648ac29c'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Crissair|RFD 02|004457/2018|220 V', 'Crissair', 'RFD 02', 'inmetro_refrigerators', NULL, 736.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 61.4, 'kWh/mes'),
('a7cb924a067454c5acee27ceba7ba1d7'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Flat iron', NULL, NULL, 'WATTSIMPLE', 150.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('a8bad3541c0c5789adff6bc66e095e98'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Heated pet bed', NULL, NULL, 'WATTSIMPLE', 40.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('a8f96dbc87a95b36801713f33f6292ae'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG87B|001955/2017|220 V', 'Philco', 'PFG87B', 'inmetro_refrigerators', NULL, 177.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 14.8, 'kWh/mes'),
('a8fc084807e75a95afe130d42961ebf6'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PH85PR|007591/2016|127 V', 'Philco', 'PH85PR', 'inmetro_refrigerators', NULL, 210.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 17.5, 'kWh/mes'),
('aa924aac7d275a58bbfdbbb3ca7a0e95'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM44|005218/2016|220 V', 'BRASTEMP', 'BRM44', 'inmetro_refrigerators', NULL, 648.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 54.0, 'kWh/mes'),
('aaf36aef300453d89336c710a5eeab35'::uuid, '32bc03267d0a5a009753fd6f5f31723e'::uuid, 'WATTSIMPLE', 'Incandescent bulb', NULL, NULL, 'WATTSIMPLE', 60.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('ab3dc0bac9c5541c96a0babd2a1aab78'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Miele|K 2801 Vi 220 Volts|001592/2021|220 V', 'Miele', 'K 2801 Vi 220 Volts', 'inmetro_refrigerators', NULL, 218.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 18.2, 'kWh/mes'),
('ab83d97e9830570f9695c2ea1155bece'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG111B|003271/2019|127 V', 'Philco', 'PFG111B', 'inmetro_refrigerators', NULL, 198.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 16.5, 'kWh/mes'),
('ab8e599d4af851d993d14506dc990447'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF411I|002671/2020|220 V', 'Philco', 'PRF411I', 'inmetro_refrigerators', NULL, 504.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 42.0, 'kWh/mes'),
('ab9b82624def5648a518828b5c3b448b'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Golf cart charger', NULL, NULL, 'WATTSIMPLE', 1000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('ac4bcedf9e5353b6bf3e81780c65edbf'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Elettromec|RF-FD-531-XX-2HSA|004429/2016|220 V', 'Elettromec', 'RF-FD-531-XX-2HSA', 'inmetro_refrigerators', NULL, 559.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 46.6, 'kWh/mes'),
('aceb0691820f50cbb075348938118457'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF510I|004318/2020|127 V', 'Philco', 'PRF510I', 'inmetro_refrigerators', NULL, 756.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 63.0, 'kWh/mes'),
('ad1fd71d73b7597ea53116584399887b'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|TW42S|005404/2016|220 V', 'Electrolux', 'TW42S', 'inmetro_refrigerators', NULL, 636.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 53.0, 'kWh/mes'),
('ae2e87b41d405d659b28ff48fcac036e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Esmaltec|ROC35R|002251/2017|127 V', 'Esmaltec', 'ROC35R', 'inmetro_refrigerators', NULL, 262.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 21.9, 'kWh/mes'),
('ae33a3d686c45f6c879198bc7422a73f'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Salt chlorinator', NULL, NULL, 'WATTSIMPLE', 150.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('ae3bc9ecee0f5241af6e026405468eea'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Mini-split (12k BTU)', NULL, NULL, 'WATTSIMPLE', 1000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('ae46e34f5ac451caa554ab6019290414'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Chicken coop heater', NULL, NULL, 'WATTSIMPLE', 250.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('aea1829db54c5c438dc719a4c69e3810'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|RE31|005401/2016|220 V', 'Electrolux', 'RE31', 'inmetro_refrigerators', NULL, 279.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 23.3, 'kWh/mes'),
('b0903c4782eb5abd9f7249ac9296a692'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DC51_DC51X|005402/2016|220 V', 'Electrolux', 'DC51_DC51X', 'inmetro_refrigerators', NULL, 705.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 58.8, 'kWh/mes'),
('b0e79eabc826556e9b47079ab39cb913'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RT46K6A4KBS/FZ|001495/2017|127 V', 'Samsung', 'RT46K6A4KBS/FZ', 'inmetro_refrigerators', NULL, 434.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 36.2, 'kWh/mes'),
('b147279ecef3531ba8f0d2fe4aee4190'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PH85N|007591/2016|220 V', 'Philco', 'PH85N', 'inmetro_refrigerators', NULL, 210.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 17.5, 'kWh/mes'),
('b1c1396d18a55a64a13ae38c5996dff7'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Panasonic|NR-BT55|5576/2017|220 V', 'Panasonic', 'NR-BT55', 'inmetro_refrigerators', NULL, 468.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 39.0, 'kWh/mes'),
('b2698f5edf40503892c03c0668cc95fd'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'EOS|EFH150X|003659/2020|220 V', 'EOS', 'EFH150X', 'inmetro_refrigerators', NULL, 259.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 21.6, 'kWh/mes'),
('b2b84a97b61358a7b16529aec80d459e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRS75|005218/2016|127 V', 'BRASTEMP', 'BRS75', 'inmetro_refrigerators', NULL, 864.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 72.0, 'kWh/mes'),
('b2e9e9d819bd5fa59cf6b63f54b04f61'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Esmaltec|ROC31|002251/2017|127 V', 'Esmaltec', 'ROC31', 'inmetro_refrigerators', NULL, 286.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 23.9, 'kWh/mes'),
('b3396606e95053a7abaf57e47ced64de'::uuid, '8158deed5e4c55db9f8fcfbedbe6c2eb'::uuid, 'WATTSIMPLE', 'Pool heat pump', NULL, NULL, 'WATTSIMPLE', 5000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('b4ce729ba9ca5d7badf77cdc38be46e7'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Blender', NULL, NULL, 'WATTSIMPLE', 500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('b4d94459dd775809b8ab7e012d7a13f2'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF533I|002671/2020|220 V', 'Philco', 'PRF533I', 'inmetro_refrigerators', NULL, 504.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 42.0, 'kWh/mes'),
('b54f11a666295066af8c6deee7e35f4a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GR-X228NMSM / GR-X228NMS1|005754/2019|127 V', 'LG', 'GR-X228NMSM / GR-X228NMS1', 'inmetro_refrigerators', NULL, 842.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 70.2, 'kWh/mes'),
('b5b8fac4fd3753c48ee3f21e5f68402f'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Towel warmer', NULL, NULL, 'WATTSIMPLE', 100.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('b63e3ffbe40c5b5a83ebddce9d77efb8'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF90PIXL|000222/2018|127 V', 'BERTAZZONI', 'REF90PIXL', 'inmetro_refrigerators', NULL, 469.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 39.1, 'kWh/mes'),
('b651cb70384058ba98043ba2fc85de12'::uuid, '23542654676958e69a8ec8708d8238ff'::uuid, 'WATTSIMPLE', 'Electric griddle', NULL, NULL, 'WATTSIMPLE', 1200.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('b669fb891cfa55dda7cd2bf74222c4f1'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'WATTSIMPLE', 'Refrigerator', NULL, NULL, 'WATTSIMPLE', 150.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('b7b39f114f9b59798803f09ea584acb9'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Electrolux|H440|004053/2020|220 V', 'Electrolux', 'H440', 'inmetro_refrigerators', NULL, 709.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 59.15, 'kWh/mes'),
('b7faf61527065942b6adf9ecf03b64a2'::uuid, '32bc03267d0a5a009753fd6f5f31723e'::uuid, 'WATTSIMPLE', 'Landscape lighting (LED, 10 fixtures)', NULL, NULL, 'WATTSIMPLE', 50.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('b899a26e1a9a54409c2b34b38f9b2c00'::uuid, '8158deed5e4c55db9f8fcfbedbe6c2eb'::uuid, 'WATTSIMPLE', 'Heat pump', NULL, NULL, 'WATTSIMPLE', 3000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('b9083cd09d225a4da91590932c3c1d55'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RL4353RBASL/AZ|001495/2017|127 V', 'Samsung', 'RL4353RBASL/AZ', 'inmetro_refrigerators', NULL, 462.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 38.5, 'kWh/mes'),
('b980cdbf63cf502d92436f170b7fdde0'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PFG100RP|000963/2021|220 V', 'Philco', 'PFG100RP', 'inmetro_refrigerators', NULL, 266.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 22.2, 'kWh/mes'),
('b98a5c19506b5a05af52c140e527f142'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'EOS|EFB100
EFB100P|003660/2020|127 V', 'EOS', 'EFB100
EFB100P', 'inmetro_refrigerators', NULL, 200.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 16.7, 'kWh/mes'),
('b99cc22046d351c2a1bf312955717291'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM57|005218/2016|127 V', 'BRASTEMP', 'BRM57', 'inmetro_refrigerators', NULL, 828.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 69.0, 'kWh/mes'),
('b9d59272698e5da185f60aa2d6f34b3b'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Pressure cooker (Instant Pot)', NULL, NULL, 'WATTSIMPLE', 1000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('b9dfa98971455ff698a2583ffb0690d8'::uuid, 'b04ab1927d35522ea8fe0b7413e719d9'::uuid, 'WATTSIMPLE', 'Laser printer', NULL, NULL, 'WATTSIMPLE', 500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('ba659c9d429950779333069f70a059d4'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Miele|K 2901 Vi 220 Volts|000663/2021|220 V', 'Miele', 'K 2901 Vi 220 Volts', 'inmetro_refrigerators', NULL, 224.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 18.7, 'kWh/mes'),
('ba7b8edff7ce5f4d9e0ff5b4ff2feb39'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF380I|002671/2020|220 V', 'Philco', 'PRF380I', 'inmetro_refrigerators', NULL, 432.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 36.0, 'kWh/mes'),
('baa5f557085a5195a42c434bbee23d68'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DF35A_DF35X|005404/2016|220 V', 'Electrolux', 'DF35A_DF35X', 'inmetro_refrigerators', NULL, 468.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 39.0, 'kWh/mes'),
('bafa94ab814a5066886f0c9cd7431658'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GS65SDN / GS65SDN1|003968/2017|127 V', 'LG', 'GS65SDN / GS65SDN1', 'inmetro_refrigerators', NULL, 690.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 57.5, 'kWh/mes'),
('bb29b12929d65ae2a9aeb72970e0d225'::uuid, 'b833c7d7cc495b119be3f541aa8ec840'::uuid, 'WATTSIMPLE', 'Attic fan', NULL, NULL, 'WATTSIMPLE', 300.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('bba2c427d34c5d8e9d2fbdfcd7b6147d'::uuid, 'e30e84bfb86257288ad3c6c70a5e50d4'::uuid, 'WATTSIMPLE', 'Dehumidifier', NULL, NULL, 'WATTSIMPLE', 500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('bba3d398cb015ff790691a27138e06e2'::uuid, '37d947f088cc55f1be5bd59977d45976'::uuid, 'WATTSIMPLE', 'Chest freezer', NULL, NULL, 'WATTSIMPLE', 100.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET canonical_product_id = EXCLUDED.canonical_product_id, source = EXCLUDED.source, external_id = EXCLUDED.external_id, brand = EXCLUDED.brand, model = EXCLUDED.model, dataset_id = EXCLUDED.dataset_id, power_w = EXCLUDED.power_w, annual_energy_kwh = EXCLUDED.annual_energy_kwh, standby_power_w = EXCLUDED.standby_power_w, observed_at = EXCLUDED.observed_at, is_generic = EXCLUDED.is_generic, voltage_raw = EXCLUDED.voltage_raw, voltage_kind = EXCLUDED.voltage_kind, voltage_min_v = EXCLUDED.voltage_min_v, voltage_max_v = EXCLUDED.voltage_max_v, raw_energy_value = EXCLUDED.raw_energy_value, raw_energy_unit = EXCLUDED.raw_energy_unit;
INSERT INTO public.product_source_observation (id, canonical_product_id, source, external_id, brand, model, dataset_id, power_w, annual_energy_kwh, standby_power_w, observed_at, is_generic, voltage_raw, voltage_kind, voltage_min_v, voltage_max_v, raw_energy_value, raw_energy_unit) VALUES
('bbbbeb1865a553a49d3dccb3837a409f'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Electrolux|FE22|005399/2016|220 V', 'Electrolux', 'FE22', 'inmetro_refrigerators', NULL, 511.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 42.6, 'kWh/mes'),
('bbdf7c007fd5532fbb474e6b8abe6bb3'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CVU26|005220/2016|220 V', 'CONSUL', 'CVU26', 'inmetro_refrigerators', NULL, 494.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 41.2, 'kWh/mes'),
('bc6c4bd48b3d52d3960df380f158656a'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Bidet seat (heated)', NULL, NULL, 'WATTSIMPLE', 50.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('bca33de72d9c589fb97a872fceb7fde4'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG85B|003271/2019|220 V', 'Philco', 'PFG85B', 'inmetro_refrigerators', NULL, 145.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 12.1, 'kWh/mes'),
('be392b584e49559a9118f3092e6efc42'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RF23R6201SR/BZ|007317/2017|220 V', 'Samsung', 'RF23R6201SR/BZ', 'inmetro_refrigerators', NULL, 720.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 60.0, 'kWh/mes'),
('be881505bc38570eb544e32f228bebc6'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Panasonic|NR-BT42|5576/2017|220 V', 'Panasonic', 'NR-BT42', 'inmetro_refrigerators', NULL, 372.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 31.0, 'kWh/mes'),
('bec77c4d1c65531a9e266f6c48dc9566'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'EOS|EFB100
EFB100P|003660/2020|220 V', 'EOS', 'EFB100
EFB100P', 'inmetro_refrigerators', NULL, 200.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 16.7, 'kWh/mes'),
('bf14bbfd4ef153e8ba1290d0cb41c60a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GC-X247CSAV / GC-X247CSA1 / GC-X247CQBV / GC-X247CQB1 / GC-X247CSBV / GC-X247CSB1|003968/2017|127 V', 'LG', 'GC-X247CSAV / GC-X247CSA1 / GC-X247CQBV / GC-X247CQB1 / GC-X247CSBV / GC-X247CSB1', 'inmetro_refrigerators', NULL, 690.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 57.5, 'kWh/mes'),
('bf9667aa743a58afa76657af30c595d7'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Franke|FCB 320 NR ENF V A++ BRA|008199/2019|220 V', 'Franke', 'FCB 320 NR ENF V A++ BRA', 'inmetro_refrigerators', NULL, 309.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 25.8, 'kWh/mes'),
('bf96abd18e5951b292c00bbdcb6488d7'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Air compressor (1.5 HP)', NULL, NULL, 'WATTSIMPLE', 1500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('bf9e73401a7f5f5bae3e6607de582664'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Venax|NGV 10|001450/2018|220 V', 'Venax', 'NGV 10', 'inmetro_refrigerators', NULL, 216.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 18.0, 'kWh/mes'),
('c03eeaf2b52051a490aa5cc3b652f58a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DC44|005402/2016|127 V', 'Electrolux', 'DC44', 'inmetro_refrigerators', NULL, 552.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 46.0, 'kWh/mes'),
('c07dcdf5cc5b53a888ee15f6f1935453'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFV300I|005214/2021|220 V', 'Philco', 'PFV300I', 'inmetro_refrigerators', NULL, 438.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 36.5, 'kWh/mes'),
('c0976841e9455be9a97a4df1781f1530'::uuid, '3c56d7551b375487a95a1882b9a6df57'::uuid, 'WATTSIMPLE', 'Electric range/oven', NULL, NULL, 'WATTSIMPLE', 3000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('c0a773853c8d5eeda9061f03cfda8bec'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG90RV|001955/2017|220 V', 'Philco', 'PFG90RV', 'inmetro_refrigerators', NULL, 177.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 14.8, 'kWh/mes'),
('c0b8e200b5d0565f88c69b246dd3421d'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|IF56B_IT56S|005404/2016|220 V', 'Electrolux', 'IF56B_IT56S', 'inmetro_refrigerators', NULL, 436.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 36.4, 'kWh/mes'),
('c119b078e3015b2e950c5a43538f16d3'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'E-bike charger', NULL, NULL, 'WATTSIMPLE', 150.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('c15d9f8843f35c32b1852eedced13ff1'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Security camera system (4 cams + NVR)', NULL, NULL, 'WATTSIMPLE', 40.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('c182fb9bd2a8519c8c9ea9d4d61048e9'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Invita|i-RF-BF-360-XX-2HMA|001451/2018|220 V', 'Invita', 'i-RF-BF-360-XX-2HMA', 'inmetro_refrigerators', NULL, 454.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 37.9, 'kWh/mes'),
('c1e8721b050d5f12875e7b471d8ac5e6'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Electrolux|RE120|005401/2016|220 V', 'Electrolux', 'RE120', 'inmetro_refrigerators', NULL, 238.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 19.9, 'kWh/mes'),
('c20cd86d58595ee19dfc5c36c4b9e8d7'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Home theater projector', NULL, NULL, 'WATTSIMPLE', 300.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('c23b9b2021f35721854708c9b0434df4'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Britânia|BFG50B|003271/2019|127 V', 'Britânia', 'BFG50B', 'inmetro_refrigerators', NULL, 141.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 11.8, 'kWh/mes'),
('c2cf68cf510d57cd88e107b5ca90745c'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Midea|RCFA32|003109/2016|220 V', 'Midea', 'RCFA32', 'inmetro_refrigerators', NULL, 386.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 32.2, 'kWh/mes'),
('c2d1b6ce2afe5df2b2fa848bcd9ac854'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Gaming PC', NULL, NULL, 'WATTSIMPLE', 500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('c2e8266123b45988bb9f108193b296b3'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Gorenje|FNI5182A1|002508/2019|220 V', 'Gorenje', 'FNI5182A1', 'inmetro_refrigerators', NULL, 315.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 26.3, 'kWh/mes'),
('c322544458be5e9288aa6963793bf8ba'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Midea|MD-RT507FGA042|002748/2020|220 V', 'Midea', 'MD-RT507FGA042', 'inmetro_refrigerators', NULL, 553.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 46.1, 'kWh/mes'),
('c35aec0f91b75d4eb7700eccfea3369a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'TECNO|TR30BXDA|004343/2020|127 V', 'TECNO', 'TR30BXDA', 'inmetro_refrigerators', NULL, 321.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 26.8, 'kWh/mes'),
('c38a0d4e051d55369dc877ffccdbf7a3'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM59|005218/2016|127 V', 'BRASTEMP', 'BRM59', 'inmetro_refrigerators', NULL, 792.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 66.0, 'kWh/mes'),
('c39c67c338b15a8aa0f4c5f172ddddf3'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CVU18|005220/2016|127 V', 'CONSUL', 'CVU18', 'inmetro_refrigerators', NULL, 444.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 37.0, 'kWh/mes'),
('c44f6eca70755cf9a5fd47cff76ac8bb'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Panasonic|NR-BB53|5576/2017|127 V', 'Panasonic', 'NR-BB53', 'inmetro_refrigerators', NULL, 478.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 39.9, 'kWh/mes'),
('c4c1ce4008d4503989d64f19a378289b'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DF42_DF42X_TF42_TF42S|005404/2016|127 V', 'Electrolux', 'DF42_DF42X_TF42_TF42S', 'inmetro_refrigerators', NULL, 636.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 53.0, 'kWh/mes'),
('c4eec00c02525168aa2350cf697b33dc'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Britânia|BFH109B|003272/2019|220 V', 'Britânia', 'BFH109B', 'inmetro_refrigerators', NULL, 276.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 23.0, 'kWh/mes'),
('c4f5e71fa81058069c1ec80b90e19ce0'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GR-B413PSJU / GR-B413PSJ1|001421/2019|127 V', 'LG', 'GR-B413PSJU / GR-B413PSJ1', 'inmetro_refrigerators', NULL, 595.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 49.6, 'kWh/mes'),
('c54f1f4e90fe538d904a5d1b5acb5859'::uuid, '3c56d7551b375487a95a1882b9a6df57'::uuid, 'WATTSIMPLE', 'Pellet stove', NULL, NULL, 'WATTSIMPLE', 300.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('c5e6116c82eb5702925e9812c37175cc'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Midea|MRV10|001496/2017|127 V', 'Midea', 'MRV10', 'inmetro_refrigerators', NULL, 194.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 16.2, 'kWh/mes'),
('c66423e3742c5cdebe89e0da55286afe'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM55|005218/2016|220 V', 'CONSUL', 'CRM55', 'inmetro_refrigerators', NULL, 672.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 56.0, 'kWh/mes'),
('c689a151673554f59b9d1c463fcadba0'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Crissair|FRZ 06.2 260 Litros 220V|009779/2019|220 V', 'Crissair', 'FRZ 06.2 260 Litros 220V', 'inmetro_refrigerators', NULL, 384.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 32.0, 'kWh/mes'),
('c6c2d84fc3e35793a567fd7a95644faf'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'AV receiver', NULL, NULL, 'WATTSIMPLE', 250.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('c702508647e754b18b669d55cc0c10dd'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Elettromec|FZ-DU-262-XX-2HSB|000069/2018|220 V', 'Elettromec', 'FZ-DU-262-XX-2HSB', 'inmetro_refrigerators', NULL, 484.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 40.4, 'kWh/mes'),
('c78a461267b055aa8b1325d70c464c3b'::uuid, 'b04ab1927d35522ea8fe0b7413e719d9'::uuid, 'WATTSIMPLE', '3D printer', NULL, NULL, 'WATTSIMPLE', 150.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('c84368bbf0de5191b30a315bcf22449c'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM45|005218/2016|127 V', 'BRASTEMP', 'BRM45', 'inmetro_refrigerators', NULL, 648.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 54.0, 'kWh/mes'),
('c8b411d0570e58f2be9575274da8985e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF503TI|003507/2020|127 V', 'Philco', 'PRF503TI', 'inmetro_refrigerators', NULL, 432.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 36.0, 'kWh/mes'),
('c92d3ef870bb5fba9f79b18975524841'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Elettromec|RF-BF-360-VT-2HMB / RF-BF-360-XX-2HMB|001451/2018|220 V', 'Elettromec', 'RF-BF-360-VT-2HMB / RF-BF-360-XX-2HMB', 'inmetro_refrigerators', NULL, 454.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 37.9, 'kWh/mes'),
('c934e4f5183d560bb6e987acdd31dff9'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF75PRL|000222/2018|220 V', 'BERTAZZONI', 'REF75PRL', 'inmetro_refrigerators', NULL, 447.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 37.3, 'kWh/mes'),
('c939d596dfb9556e87378aa955f9518f'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'TECNO|TR30BXDA|004343/2020|220 V', 'TECNO', 'TR30BXDA', 'inmetro_refrigerators', NULL, 321.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 26.8, 'kWh/mes'),
('c9616d728f8d5e86ad297f4d11de5ae9'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Vacuum cleaner (corded)', NULL, NULL, 'WATTSIMPLE', 1200.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('c975dead4bf7595b80bea01ebd323177'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFH440B|003272/2019|220 V', 'Philco', 'PFH440B', 'inmetro_refrigerators', NULL, 429.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 35.8, 'kWh/mes'),
('c9fab9df87495876b2bbbc342d8fcee8'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PH85 Platinum|007591/2016|220 V', 'Philco', 'PH85 Platinum', 'inmetro_refrigerators', NULL, 210.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 17.5, 'kWh/mes'),
('cab01d91e20159bc9e394de8846ad571'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RS65R5691M9/AZ|004878/2019|127 V', 'Samsung', 'RS65R5691M9/AZ', 'inmetro_refrigerators', NULL, 710.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 59.2, 'kWh/mes'),
('cad995b9bad150a9bace8f2a6d3399cd'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Galanz|GFb04C01A-Ix220
GFb04C01A-Pt220
GFb04C01A-Br220
GFb04C01A-Ix127
GFb04C01A-Pt127
GFb04C01A-Br127|004319/2020|220 V', 'Galanz', 'GFb04C01A-Ix220
GFb04C01A-Pt220
GFb04C01A-Br220
GFb04C01A-Ix127
GFb04C01A-Pt127
GFb04C01A-Br127', 'inmetro_refrigerators', NULL, 153.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 12.8, 'kWh/mes'),
('cb00a3c5f2d152729c3334dca0fe0331'::uuid, '6f44b7227cc051a682040ed72691b38b'::uuid, 'WATTSIMPLE', 'Electric furnace (10 kW)', NULL, NULL, 'WATTSIMPLE', 10000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('cb5f8181b2b4589f96cda97d19ce51af'::uuid, '44b152237bec5d678facdb985e3e01c5'::uuid, 'WATTSIMPLE', 'Computer monitor', NULL, NULL, 'WATTSIMPLE', 30.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('cbd760a450ee5e07920db91bd88d76e8'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRS62|005218/2016|220 V', 'BRASTEMP', 'BRS62', 'inmetro_refrigerators', NULL, 804.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 67.0, 'kWh/mes'),
('cbed226ebed0541bbf250b60d1215cb2'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Continental|TC56_TC56S|005404/2016|220 V', 'Continental', 'TC56_TC56S', 'inmetro_refrigerators', NULL, 672.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 56.0, 'kWh/mes'),
('cbfa7efe62555a7482b9ef54074de026'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Elettromec|RF-DU-360-XX-2HSB|000070/2018|220 V', 'Elettromec', 'RF-DU-360-XX-2HSB', 'inmetro_refrigerators', NULL, 216.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 18.0, 'kWh/mes'),
('ccba2717e3d25045815b7a6cc78ca341'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Waffle maker', NULL, NULL, 'WATTSIMPLE', 1000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('ccbe08c9666f5c108f68827160fae008'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Midea|RCFC42|003109/2016|220 V', 'Midea', 'RCFC42', 'inmetro_refrigerators', NULL, 439.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 36.6, 'kWh/mes'),
('cce7c328307257689be35c72a0db6d96'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM45|005218/2016|220 V', 'BRASTEMP', 'BRM45', 'inmetro_refrigerators', NULL, 648.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 54.0, 'kWh/mes'),
('cd5b28577eea564ba46d702f6ecd2e64'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Cable/satellite box', NULL, NULL, 'WATTSIMPLE', 25.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('ce5bbf91b47f54b99fb46266cb03d2ad'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF507IP|001056/2020|220 V', 'Philco', 'PRF507IP', 'inmetro_refrigerators', NULL, 510.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 42.5, 'kWh/mes'),
('ce7e071395c152e0918670c1d78b4b93'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM44|005218/2016|127 V', 'BRASTEMP', 'BRM44', 'inmetro_refrigerators', NULL, 648.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 54.0, 'kWh/mes'),
('ceeae780abb65788afb87142f823c93b'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Electrolux|H550|004053/2020|127 V', 'Electrolux', 'H550', 'inmetro_refrigerators', NULL, 870.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 72.5, 'kWh/mes'),
('cf9f0b2f203a55c490baba446c6d7edb'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|IF56B_IT56S|005404/2016|127 V', 'Electrolux', 'IF56B_IT56S', 'inmetro_refrigerators', NULL, 436.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 36.4, 'kWh/mes'),
('d2040675e7435a949b9af02584572016'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RT46K6A4KS9/FZ|001495/2017|220 V', 'Samsung', 'RT46K6A4KS9/FZ', 'inmetro_refrigerators', NULL, 499.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 41.6, 'kWh/mes'),
('d23fb2eb3c0b59dda3fcbb4ad9045f77'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'EOS|EFB80
EFB80P|003660/2020|220 V', 'EOS', 'EFB80
EFB80P', 'inmetro_refrigerators', NULL, 170.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 14.2, 'kWh/mes'),
('d27076c4225a5d07a1bc680f4d995b91'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'TECNO|TR45FXDA|005755/2019|220 V', 'TECNO', 'TR45FXDA', 'inmetro_refrigerators', NULL, 601.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 50.1, 'kWh/mes'),
('d29af0486b7a58ee941a38e36e50888a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DC35A|005402/2016|220 V', 'Electrolux', 'DC35A', 'inmetro_refrigerators', NULL, 460.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 38.4, 'kWh/mes'),
('d34c2ffd1ac85d43bb29a6a807f47a1a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM39|005218/2016|127 V', 'CONSUL', 'CRM39', 'inmetro_refrigerators', NULL, 589.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 49.1, 'kWh/mes'),
('d4b1a0bdc3c852acb184a0540319a52b'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CHB53|005219/2016|127 V', 'CONSUL', 'CHB53', 'inmetro_refrigerators', NULL, 865.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 72.1, 'kWh/mes'),
('d54f523205aa5714898813f86574a692'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Britânia|BFG94P|007591/2016|127 V', 'Britânia', 'BFG94P', 'inmetro_refrigerators', NULL, 216.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 18.0, 'kWh/mes'),
('d5800a456e6e57ddb5f77658c036ca22'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Oxygen concentrator', NULL, NULL, 'WATTSIMPLE', 300.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('d60a3e58b63252b59f386ad93b6ce8bc'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Sump pump', NULL, NULL, 'WATTSIMPLE', 800.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('d72a8585a24f58708751e8f4ea5edf44'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRY59|005218/2016|220 V', 'BRASTEMP', 'BRY59', 'inmetro_refrigerators', NULL, 756.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 63.0, 'kWh/mes'),
('d799ad8ae0ec50649fde8e7d3bd96ef4'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Food processor', NULL, NULL, 'WATTSIMPLE', 500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('d85d448c4ef25f28b4110426b023e868'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Continental|TC41_TC41S|005404/2016|220 V', 'Continental', 'TC41_TC41S', 'inmetro_refrigerators', NULL, 615.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 51.3, 'kWh/mes'),
('d873f1ba56f1598fa5239730ac1850ed'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM54|005218/2016|220 V', 'CONSUL', 'CRM54', 'inmetro_refrigerators', NULL, 672.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 56.0, 'kWh/mes'),
('d8d3d20b22c85a2cb66ed0ab554c5630'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CVU18|005220/2016|220 V', 'CONSUL', 'CVU18', 'inmetro_refrigerators', NULL, 444.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 37.0, 'kWh/mes'),
('d98ee1ab57725ce187e0ca3963b39948'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Continental|TC44_TC44S|005404/2016|127 V', 'Continental', 'TC44_TC44S', 'inmetro_refrigerators', NULL, 663.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 55.3, 'kWh/mes'),
('d98f738884b65856aa21eb73f7254a6a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Gorenje|ORB152R|002863/2017|220 V', 'Gorenje', 'ORB152R', 'inmetro_refrigerators', NULL, 350.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 29.2, 'kWh/mes'),
('da0ff0eda8ed5e2096e45d8f576e348c'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRE80|005218/2016|127 V', 'BRASTEMP', 'BRE80', 'inmetro_refrigerators', NULL, 816.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 68.0, 'kWh/mes'),
('db07911cb88f5ad4b5aabf64b0d4de44'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG51B|001955/2017|127 V', 'Philco', 'PFG51B', 'inmetro_refrigerators', NULL, 165.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 13.8, 'kWh/mes'),
('dba76c21acb15c18b79285f78308ecc4'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DW44S|005404/2016|220 V', 'Electrolux', 'DW44S', 'inmetro_refrigerators', NULL, 675.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 56.3, 'kWh/mes'),
('dbf622fc5d555a57aeeed69bb91523f3'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRO81|005218/2016|127 V', 'BRASTEMP', 'BRO81', 'inmetro_refrigerators', NULL, 872.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 72.7, 'kWh/mes'),
('dc099b3f2ace5e4fa3d7305f9a29d72c'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GR-X248LKZM / GR-X248LKZ1|003968/2017|127 V', 'LG', 'GR-X248LKZM / GR-X248LKZ1', 'inmetro_refrigerators', NULL, 876.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 73.0, 'kWh/mes'),
('dc76f8ae7e475ca3a346005b222febd7'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'EOS|EFB80
EFB80P|003660/2020|127 V', 'EOS', 'EFB80
EFB80P', 'inmetro_refrigerators', NULL, 170.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 14.2, 'kWh/mes'),
('dcc58c89c4fe5c9cbc380bf10e66f4ba'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RS50N3413S8/AZ|004878/2019|127 V', 'Samsung', 'RS50N3413S8/AZ', 'inmetro_refrigerators', NULL, 826.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 68.9, 'kWh/mes'),
('dcfa869746b85563954561b5a70de382'::uuid, '780845d2b0975576812c7e4f3a667900'::uuid, 'WATTSIMPLE', 'Air purifier', NULL, NULL, 'WATTSIMPLE', 50.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('dd5bc52eee5d50fabc2f132406be916e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRD36|005217/2016|127 V', 'CONSUL', 'CRD36', 'inmetro_refrigerators', NULL, 522.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 43.5, 'kWh/mes'),
('ddb45a8622535b428992ff0276e2d558'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DC35A|005402/2016|127 V', 'Electrolux', 'DC35A', 'inmetro_refrigerators', NULL, 460.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 38.4, 'kWh/mes'),
('de5c8dab4e9a5430bf233a59c314c448'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DC44|005402/2016|220 V', 'Electrolux', 'DC44', 'inmetro_refrigerators', NULL, 552.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 46.0, 'kWh/mes'),
('dec31cbdf9d7557599c4f1f351c864c9'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Britânia|BFH202B|002580/2017|220 V', 'Britânia', 'BFH202B', 'inmetro_refrigerators', NULL, 414.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 34.5, 'kWh/mes'),
('def4013e364e599e9143331c2c2ba469'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFH105B|003272/2019|127 V', 'Philco', 'PFH105B', 'inmetro_refrigerators', NULL, 276.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 23.0, 'kWh/mes'),
('df8ac6619c9b5863a2b02273784cc472'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRC12|005222/2016|127 V', 'BRASTEMP', 'BRC12', 'inmetro_refrigerators', NULL, 228.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 19.0, 'kWh/mes'),
('dfb386e55e2b535e812dfb9b67985ac2'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF75PIXL|000222/2018|220 V', 'BERTAZZONI', 'REF75PIXL', 'inmetro_refrigerators', NULL, 447.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 37.3, 'kWh/mes'),
('dfc9d260ca47507ab135659ee7683d90'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'BRASTEMP|BVR28|005221/2016|127 V', 'BRASTEMP', 'BVR28', 'inmetro_refrigerators', NULL, 660.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 55.0, 'kWh/mes'),
('dff49cdd8a7a5c9a825c475d63420b56'::uuid, 'd8ca8c3931f25c429f716765892d24ac'::uuid, 'WATTSIMPLE', 'Hair dryer', NULL, NULL, 'WATTSIMPLE', 1500.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('e003707d52c25eaba7848ef840e40b0a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM45|005218/2016|220 V', 'CONSUL', 'CRM45', 'inmetro_refrigerators', NULL, 630.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 52.5, 'kWh/mes'),
('e01974f77655584093273c5fc038c8dd'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFH515B|002580/2017|127 V', 'Philco', 'PFH515B', 'inmetro_refrigerators', NULL, 801.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 66.8, 'kWh/mes'),
('e06fe0f450ba5c2abe8287a3da89f9d1'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DB52 _DB52X_DT52X_DB53_DB53X|005404/2016|220 V', 'Electrolux', 'DB52 _DB52X_DT52X_DB53_DB53X', 'inmetro_refrigerators', NULL, 708.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 59.0, 'kWh/mes'),
('e0bd794f5beb5b66b5af454de62ad102'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF260RV|003507/2020|220 V', 'Philco', 'PRF260RV', 'inmetro_refrigerators', NULL, 420.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 35.0, 'kWh/mes'),
('e14faef747245d09b6c7f46e2ca9ba62'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRD37|005217/2016|127 V', 'CONSUL', 'CRD37', 'inmetro_refrigerators', NULL, 522.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 43.5, 'kWh/mes'),
('e197721d96cd59f58f550e64ba428789'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Miele|FNS 37402 i|001052/2020|220 V', 'Miele', 'FNS 37402 i', 'inmetro_refrigerators', NULL, 294.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 24.5, 'kWh/mes'),
('e1ac36a27b8f5a08b8c8311fe38ebc2e'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Smart speaker', NULL, NULL, 'WATTSIMPLE', 5.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('e28c86390f56530b9d9bf3009c9edc35'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DC51_DC51X|005402/2016|127 V', 'Electrolux', 'DC51_DC51X', 'inmetro_refrigerators', NULL, 705.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 58.8, 'kWh/mes'),
('e2d8151123d25e7ea6a465b0c0e02317'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Elettromec|RF-MD-472-VT-2HMA / RF-MD-472-XX-2HMA|007381/2020|220 V', 'Elettromec', 'RF-MD-472-VT-2HMA / RF-MD-472-XX-2HMA', 'inmetro_refrigerators', NULL, 367.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 30.6, 'kWh/mes'),
('e34a1b4b674b5bb29fe6e0e0d5270703'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'BRASTEMP|BVG24|005221/2016|220 V', 'BRASTEMP', 'BVG24', 'inmetro_refrigerators', NULL, 636.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 53.0, 'kWh/mes'),
('e390cacf35085a9ebc7ae3657b30218f'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|IB52_IB52X_IB53_IB53X|005404/2016|220 V', 'Electrolux', 'IB52_IB52X_IB53_IB53X', 'inmetro_refrigerators', NULL, 548.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 45.7, 'kWh/mes'),
('e4232be8fc9f576db45c877a47c068cf'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Sewage ejector pump', NULL, NULL, 'WATTSIMPLE', 800.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('e4cff13110a15e1085262f94b8af51e0'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRE57|005218/2016|127 V', 'BRASTEMP', 'BRE57', 'inmetro_refrigerators', NULL, 792.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 66.0, 'kWh/mes'),
('e4e4c6448c2f5dc79a7c1de42b94530f'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF260RV|003507/2020|127 V', 'Philco', 'PRF260RV', 'inmetro_refrigerators', NULL, 420.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 35.0, 'kWh/mes'),
('e65456081e445ddc9d719df0e4c6568e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RT46K6A4KWW/FZ|001495/2017|127 V', 'Samsung', 'RT46K6A4KWW/FZ', 'inmetro_refrigerators', NULL, 499.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 41.6, 'kWh/mes'),
('e747d9fb81665f278d2e6356805b773b'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF75PIXL|000222/2018|127 V', 'BERTAZZONI', 'REF75PIXL', 'inmetro_refrigerators', NULL, 447.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 37.3, 'kWh/mes'),
('e7776f2d61f45ed4939af6cd37486314'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RF59A7011SR/AZ|007317/2017|127 V', 'Samsung', 'RF59A7011SR/AZ', 'inmetro_refrigerators', NULL, 720.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 60.0, 'kWh/mes'),
('e7e771637db257379db83a267879f56b'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM43Z|005218/2016|220 V', 'CONSUL', 'CRM43Z', 'inmetro_refrigerators', NULL, 624.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 52.0, 'kWh/mes'),
('e83a0a7159d251968f79317fb2659839'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Continental|TC56_TC56S|005404/2016|127 V', 'Continental', 'TC56_TC56S', 'inmetro_refrigerators', NULL, 672.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 56.0, 'kWh/mes'),
('e890a23e689b5dadb405c304ac93370e'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DF56_DF56S_TF56_TF56S|005404/2016|127 V', 'Electrolux', 'DF56_DF56S_TF56_TF56S', 'inmetro_refrigerators', NULL, 648.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 54.0, 'kWh/mes'),
('e8a8422c73a7518a8cf2b352d2896bf1'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BERTAZZONI|REF90X|000222/2018|220 V', 'BERTAZZONI', 'REF90X', 'inmetro_refrigerators', NULL, 608.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 50.7, 'kWh/mes'),
('e8b61af9abfe54daac8e2e9f1a20a3a9'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Esmaltec|ROC31R|002251/2017|220 V', 'Esmaltec', 'ROC31R', 'inmetro_refrigerators', NULL, 282.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 23.5, 'kWh/mes'),
('e8e4f330712d5571b3def2cd000179f3'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Electrolux|H162|005396/2016|220 V', 'Electrolux', 'H162', 'inmetro_refrigerators', NULL, 319.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 26.6, 'kWh/mes'),
('e9156156d3fe5f7c915a7dafc9f34a0f'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Midea|MD-RT507FGA041|002748/2020|127 V', 'Midea', 'MD-RT507FGA041', 'inmetro_refrigerators', NULL, 628.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 52.4, 'kWh/mes'),
('e95719e117bb5300bb2086789cec548f'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Streaming stick', NULL, NULL, 'WATTSIMPLE', 5.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('e95caf80d10e54d8818bffab64dd0685'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Corded lawn mower', NULL, NULL, 'WATTSIMPLE', 1200.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('e99066c88f4855339e4cb544fe1279d1'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Panasonic|NR-BB71|5576/2017|127 V', 'Panasonic', 'NR-BB71', 'inmetro_refrigerators', NULL, 490.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 40.9, 'kWh/mes'),
('ea25872154af539390d97fe165084596'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'EV charger (Level 2, 40A)', NULL, NULL, 'WATTSIMPLE', 9600.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('ea7cfac3f9e759ff99b8541f9d2c9056'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM51|005218/2016|220 V', 'CONSUL', 'CRM51', 'inmetro_refrigerators', NULL, 630.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 52.5, 'kWh/mes'),
('eab51e476f7f566483960a3f36100be3'::uuid, 'b833c7d7cc495b119be3f541aa8ec840'::uuid, 'WATTSIMPLE', 'Box fan', NULL, NULL, 'WATTSIMPLE', 75.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('eac79caf2e025206b0202b9b8a625830'::uuid, '32bc03267d0a5a009753fd6f5f31723e'::uuid, 'WATTSIMPLE', 'CFL bulb', NULL, NULL, 'WATTSIMPLE', 14.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('eb030925709f51b9b9bb99eb1b61d518'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Home sauna (6 kW)', NULL, NULL, 'WATTSIMPLE', 6000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('ebfee4248b5a578aa28e87ce76a46683'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Electric blanket', NULL, NULL, 'WATTSIMPLE', 150.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('ec64f1071ef2505cac3f1dc4e7767d61'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF520DI|008370/2019|220 V', 'Philco', 'PRF520DI', 'inmetro_refrigerators', NULL, 735.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 61.3, 'kWh/mes'),
('ed09cfa54b685108970d7d58965da0f2'::uuid, 'b833c7d7cc495b119be3f541aa8ec840'::uuid, 'WATTSIMPLE', 'Whole-house fan', NULL, NULL, 'WATTSIMPLE', 400.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('ed596bfe9a52515aacd1a058a1804d7e'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Electric fireplace', NULL, NULL, 'WATTSIMPLE', 1400.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('edb56719eaa05de58813221c290f3ca6'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Electrolux|H162|005396/2016|127 V', 'Electrolux', 'H162', 'inmetro_refrigerators', NULL, 319.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 26.6, 'kWh/mes'),
('eddfe9f2b74e5f04b976fe510809c930'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PFG121RV|000963/2021|127 V', 'Philco', 'PFG121RV', 'inmetro_refrigerators', NULL, 234.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 19.5, 'kWh/mes'),
('eecdbb058c4251f1a42d3cdcd230a079'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Septic aerator', NULL, NULL, 'WATTSIMPLE', 80.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('ef00268822655e97a804ad2787f1518c'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DB83_DB83X_DB84_DB84X|005404/2016|127 V', 'Electrolux', 'DB83_DB83X_DB84_DB84X', 'inmetro_refrigerators', NULL, 816.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 68.0, 'kWh/mes'),
('ef24adc7f161530cb3a74b3d222fea5a'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Humidifier', NULL, NULL, 'WATTSIMPLE', 40.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('efbf4fe6e4735f77a398c48f026d045a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DB52 _DB52X_DT52X_DB53_DB53X|005404/2016|127 V', 'Electrolux', 'DB52 _DB52X_DT52X_DB53_DB53X', 'inmetro_refrigerators', NULL, 708.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 59.0, 'kWh/mes'),
('efd9af9c6a965709881a84e682e5ac31'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Evaporative (swamp) cooler', NULL, NULL, 'WATTSIMPLE', 400.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('efdf5323f78c5b9bbe68c47199a89a98'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Panasonic|NR-BT55|5576/2017|127 V', 'Panasonic', 'NR-BT55', 'inmetro_refrigerators', NULL, 468.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 39.0, 'kWh/mes'),
('f04f96c46d0e5f9b914cc6f096c1efa6'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Britânia|BFH202B|002580/2017|127 V', 'Britânia', 'BFH202B', 'inmetro_refrigerators', NULL, 414.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 34.5, 'kWh/mes'),
('f066776ce5d859258f35fecd84bf0b64'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'LG|GR-X248LKZM / GR-X248LKZ1|003968/2017|220 V', 'LG', 'GR-X248LKZM / GR-X248LKZ1', 'inmetro_refrigerators', NULL, 876.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 73.0, 'kWh/mes'),
('f1057a1aa3ce5a958d009f8fdafbb041'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRC12|005222/2016|127 V', 'CONSUL', 'CRC12', 'inmetro_refrigerators', NULL, 228.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 19.0, 'kWh/mes'),
('f213a6ab9c705af382e0b3736c57385b'::uuid, '8158deed5e4c55db9f8fcfbedbe6c2eb'::uuid, 'WATTSIMPLE', 'Heat-pump dryer', NULL, NULL, 'WATTSIMPLE', 1000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('f21aaa19216a52468666af19aafd4e36'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Electric fence charger', NULL, NULL, 'WATTSIMPLE', 5.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('f27b6eeb0e47574a85f24eed0b835cbe'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DF42_DF42X_TF42_TF42S|005404/2016|220 V', 'Electrolux', 'DF42_DF42X_TF42_TF42S', 'inmetro_refrigerators', NULL, 636.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 53.0, 'kWh/mes'),
('f2d2b942a26b57e28cae3ee5887bce5e'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CHB42|005219/2016|220 V', 'CONSUL', 'CHB42', 'inmetro_refrigerators', NULL, 699.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 58.3, 'kWh/mes'),
('f342497388135497ba9f0b93473c56e0'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CVU30|005220/2016|127 V', 'CONSUL', 'CVU30', 'inmetro_refrigerators', NULL, 552.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 46.0, 'kWh/mes'),
('f34de93e0fa35681af8ae88360bfee36'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM58|005218/2016|127 V', 'BRASTEMP', 'BRM58', 'inmetro_refrigerators', NULL, 828.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 69.0, 'kWh/mes'),
('f350718e89015cfea91bd2dce38c1c56'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RT38K5A0KWW/FZ|001495/2017|127 V', 'Samsung', 'RT38K5A0KWW/FZ', 'inmetro_refrigerators', NULL, 471.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 39.3, 'kWh/mes'),
('f3573ad767b65281890c9e2348d51c7c'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG90RV|001955/2017|127 V', 'Philco', 'PFG90RV', 'inmetro_refrigerators', NULL, 163.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 13.6, 'kWh/mes'),
('f35f3fbe87395dd0897f485a93b40900'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Philco|PFG95B|007591/2016|127 V', 'Philco', 'PFG95B', 'inmetro_refrigerators', NULL, 216.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 18.0, 'kWh/mes'),
('f362e217db3b5850a683425c5b19aae3'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'EOS|EFH250X|003659/2020|127 V', 'EOS', 'EFH250X', 'inmetro_refrigerators', NULL, 344.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 28.7, 'kWh/mes'),
('f366f74432145ce98232e632aa168399'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Game console', NULL, NULL, 'WATTSIMPLE', 150.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('f3893802d45f59c6bc5369494401c63b'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRE57|005218/2016|220 V', 'BRASTEMP', 'BRE57', 'inmetro_refrigerators', NULL, 792.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 66.0, 'kWh/mes'),
('f3dbac9b92d855c1b1b122aebdcd1c4f'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Sewing machine', NULL, NULL, 'WATTSIMPLE', 100.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('f3df1209bf5059239f5b375b6a91101b'::uuid, 'd8ca8c3931f25c429f716765892d24ac'::uuid, 'WATTSIMPLE', 'Clothes dryer (electric)', NULL, NULL, 'WATTSIMPLE', 3000.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('f49e5e3d371e558ca02815203d778a7f'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CVU26|005220/2016|127 V', 'CONSUL', 'CVU26', 'inmetro_refrigerators', NULL, 494.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 41.2, 'kWh/mes'),
('f4ae4ec3d8835fb4a823b1de00f281a7'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Britânia|BFH109B|003272/2019|127 V', 'Britânia', 'BFH109B', 'inmetro_refrigerators', NULL, 276.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 23.0, 'kWh/mes'),
('f50d0e1163c7537ebf2d67892ba6a8e6'::uuid, 'd8ca8c3931f25c429f716765892d24ac'::uuid, 'WATTSIMPLE', 'Gas dryer (electric motor)', NULL, NULL, 'WATTSIMPLE', 300.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('f58aba422e575adc9ce517db17586a50'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRM56Z|005218/2016|220 V', 'BRASTEMP', 'BRM56Z', 'inmetro_refrigerators', NULL, 744.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 62.0, 'kWh/mes'),
('f7954a7bbd9d57a395e88e465f16f1bc'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CHB53|005219/2016|220 V', 'CONSUL', 'CHB53', 'inmetro_refrigerators', NULL, 865.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 72.1, 'kWh/mes'),
('f7f33f2906f2596c900147d37e73731e'::uuid, '6f44b7227cc051a682040ed72691b38b'::uuid, 'WATTSIMPLE', 'Furnace blower', NULL, NULL, 'WATTSIMPLE', 800.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('f7f3589153fd5d68bc2085f5f2128699'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DF56_DF56S_TF56_TF56S|005404/2016|220 V', 'Electrolux', 'DF56_DF56S_TF56_TF56S', 'inmetro_refrigerators', NULL, 648.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 54.0, 'kWh/mes'),
('f807f23754775732a750d970a2c58786'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM42|005218/2016|220 V', 'CONSUL', 'CRM42', 'inmetro_refrigerators', NULL, 669.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 55.8, 'kWh/mes'),
('f80a2e6358965d3189fb52e28106223d'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'EOS|EFB50
EFB50P|003660/2020|220 V', 'EOS', 'EFB50
EFB50P', 'inmetro_refrigerators', NULL, 189.60, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 15.8, 'kWh/mes'),
('f8954fdb7c435d23aa138bbf20eeaa62'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Portable AC (10k BTU)', NULL, NULL, 'WATTSIMPLE', 1100.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('f941cfe580a9513e9d5dded79a2ea94a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Viking Range|VCBB5363 / FDBB5363|007592/2016|127 V', 'Viking Range', 'VCBB5363 / FDBB5363', 'inmetro_refrigerators', NULL, 734.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 61.2, 'kWh/mes'),
('f99337f2a8105d4cab1b674c3e93e44b'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DM83X_DM84X|005404/2016|220 V', 'Electrolux', 'DM83X_DM84X', 'inmetro_refrigerators', NULL, 900.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 75.0, 'kWh/mes'),
('fafc87db6a725eecaddc31e948cdea3f'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Snow blower (corded)', NULL, NULL, 'WATTSIMPLE', 1800.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('fbc9a7cdba285cf7a14216c1b3ff8ec5'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Philco|PFZ330B|003272/2019|220 V', 'Philco', 'PFZ330B', 'inmetro_refrigerators', NULL, 394.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 32.9, 'kWh/mes'),
('fbe00fbb67435a75adb4ba66bfd7cf41'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Electrolux|DF35A_DF35X|005404/2016|127 V', 'Electrolux', 'DF35A_DF35X', 'inmetro_refrigerators', NULL, 468.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 39.0, 'kWh/mes'),
('fc172dd770cb5e998b198edb41b22f77'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Esmaltec|RCD34|002252/2017|127 V', 'Esmaltec', 'RCD34', 'inmetro_refrigerators', NULL, 462.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 38.5, 'kWh/mes'),
('fc5210e6169c57749e452f2e3fb240db'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRC08|005222/2016|220 V', 'CONSUL', 'CRC08', 'inmetro_refrigerators', NULL, 210.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 17.5, 'kWh/mes'),
('fc847633be58517e92a3b794349638bb'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Electrolux|H440|004053/2020|127 V', 'Electrolux', 'H440', 'inmetro_refrigerators', NULL, 709.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 59.15, 'kWh/mes'),
('fd94f1c2e582581b9c3018a52fce3c43'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Samsung|RF49A5202S9/BZ|001495/2017|220 V', 'Samsung', 'RF49A5202S9/BZ', 'inmetro_refrigerators', NULL, 522.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 43.5, 'kWh/mes'),
('fde668b4a8be5d078c09271a273be661'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF507IP|001056/2020|127 V', 'Philco', 'PRF507IP', 'inmetro_refrigerators', NULL, 570.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 47.5, 'kWh/mes'),
('fdf82dd3939951d782d6c31b161a09b5'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'CONSUL|CRM56|005218/2016|127 V', 'CONSUL', 'CRM56', 'inmetro_refrigerators', NULL, 708.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 59.0, 'kWh/mes'),
('fea7869b419b574c9aca212069f66671'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'Miele|F 2811 Vi 127 Volts|001052/2020|127 V', 'Miele', 'F 2811 Vi 127 Volts', 'inmetro_refrigerators', NULL, 508.80, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '127 V', 'monovolt', 127, 127, 42.4, 'kWh/mes'),
('feaf41b91afd5f9595032d4cb10f5673'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Bug zapper', NULL, NULL, 'WATTSIMPLE', 40.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('fef357bfbe7a53d5b3bb6d7681a2db48'::uuid, '17ec20331274587c9c0803f16e660662'::uuid, 'INMETRO', 'Midea|MRC10B2|001496/2017|220 V', 'Midea', 'MRC10B2', 'inmetro_refrigerators', NULL, 169.20, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 14.1, 'kWh/mes'),
('ff225bdcb6e754779ec715824436c09d'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'Philco|PRF260RP|003507/2020|220 V', 'Philco', 'PRF260RP', 'inmetro_refrigerators', NULL, 420.00, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 35.0, 'kWh/mes'),
('ffbdfb09f4d252869ef32aa7159844cf'::uuid, 'a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'INMETRO', 'CONSUL|CVU20|005220/2016|220 V', 'CONSUL', 'CVU20', 'inmetro_refrigerators', NULL, 458.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 38.2, 'kWh/mes'),
('ffdbedca27255c24b7c467ff0891a439'::uuid, '716745a9712e5f8c9d3ee809fe240b42'::uuid, 'WATTSIMPLE', 'Radiant floor heating (50 sq ft)', NULL, NULL, 'WATTSIMPLE', 600.0, NULL, NULL, '2026-09-09 22:14:32.066630+00:00'::timestamptz, false, NULL, 'unknown', NULL, NULL, NULL, NULL),
('ffe277799f015973a996ca7b0566169a'::uuid, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 'INMETRO', 'BRASTEMP|BRO81|005218/2016|220 V', 'BRASTEMP', 'BRO81', 'inmetro_refrigerators', NULL, 872.40, NULL, '2026-10-15 20:58:22.480867+00:00'::timestamptz, false, '220 V', 'monovolt', 220, 220, 72.7, 'kWh/mes')
ON CONFLICT (id) DO UPDATE SET canonical_product_id = EXCLUDED.canonical_product_id, source = EXCLUDED.source, external_id = EXCLUDED.external_id, brand = EXCLUDED.brand, model = EXCLUDED.model, dataset_id = EXCLUDED.dataset_id, power_w = EXCLUDED.power_w, annual_energy_kwh = EXCLUDED.annual_energy_kwh, standby_power_w = EXCLUDED.standby_power_w, observed_at = EXCLUDED.observed_at, is_generic = EXCLUDED.is_generic, voltage_raw = EXCLUDED.voltage_raw, voltage_kind = EXCLUDED.voltage_kind, voltage_min_v = EXCLUDED.voltage_min_v, voltage_max_v = EXCLUDED.voltage_max_v, raw_energy_value = EXCLUDED.raw_energy_value, raw_energy_unit = EXCLUDED.raw_energy_unit;
INSERT INTO public.registry_user_product (id, avg_active_hours, hours_standby, quantity, product_id, user_id) VALUES
('050430f70f8e4197a1847d08ac5d69ad'::uuid, 4.00, 20.00, 1, 'e4bf7c937db058b5972df7882fc7b082'::uuid, 1),
('13235ff500b14a58b0649286145e32b4'::uuid, 16.00, 8.00, 1, '026c3fd5d313569482c018f77cc18eb6'::uuid, 1),
('18025f0d141b4a5bb3fdb2204d6cd37f'::uuid, 16.00, 8.00, 1, '00507739daa35b3eb0aaabcb8d37fabc'::uuid, 1),
('30e70e6e4cd24c089346b27b1dc55202'::uuid, 3.00, 18.27, 2, '3c00c3cfd99d5541a36a32da1ed90050'::uuid, 1),
('4c86763ba26b4409a462f5e018967f84'::uuid, 16.00, 8.00, 1, '040c45bfe2b756828fca1328a4a10a59'::uuid, 1),
('52a98e2098314a21b2c091a60d019774'::uuid, 4.00, 22.21, 1, 'f8646dc0f58c5b6baab3562c5197382c'::uuid, 3),
('6028752b0add49459b6a1687732c3330'::uuid, 4.00, 4.00, 1, 'b03224d6390e55a59ea893d8f62bc65c'::uuid, 7465833),
('7ce816a33edb4d6881e900f2b1182ab8'::uuid, 4.00, NULL, 1, 'f8646dc0f58c5b6baab3562c5197382c'::uuid, 4588452),
('8fa407ac26a54749a33c1afe5a2172e8'::uuid, 4.00, NULL, 1, 'ebecd64986735ff5813cb93a39d8481e'::uuid, 3),
('9d7d7bf78c5a4b4b8b66a0b79387b62d'::uuid, 316.12, NULL, 10, '0590883427c8597faea3a3918717b3d8'::uuid, 1),
('a848870472a04b02a8de4e4335f6ad60'::uuid, 2.00, 0.00, 2, '3c56d7551b375487a95a1882b9a6df57'::uuid, 7465833),
('ad286db5b05647e2a2fed8ce12e085eb'::uuid, 4.00, 5.00, 1, 'ef7b6029df375b47820d33fefd5e5375'::uuid, 1),
('c715e9e045b747a0b30ec7f6b9aed2e3'::uuid, 20.00, 8.00, 1, '0089f14381f55a62a72bd24a769040d8'::uuid, 1),
('d40a3766441441e1842daed884cf1f33'::uuid, 24.00, 15.55, 1, '0f86c22bd12257fea3b1481af0067470'::uuid, 1),
('d81199253660462ca476f11a03f95b0f'::uuid, 3.00, 24.00, 2, '25b30afae9875c61a808021efa553d51'::uuid, 4),
('dad7cc7737764a5981f491cf56b7fbb1'::uuid, 12.00, NULL, 1, '44b152237bec5d678facdb985e3e01c5'::uuid, 5),
('e43ca553a3f44056ac91bbe3cc667582'::uuid, 3.00, 0.00, 1, 'b2e1745891eb5288bcfd1f57bbd66fe9'::uuid, 1),
('ed2ecc32eafd4180b0336d05525d13d3'::uuid, 5.00, 9.90, 2, '12f975bdf4d75edc8df1251d45aacbaa'::uuid, 4),
('f1e3ffaf9ec941aca0746748e6d15f07'::uuid, 4.00, NULL, 1, 'cd2f57c4936755ecbebe0240ed495f0d'::uuid, 4588452),
('f31a742edd224528bc18759b1f0e1734'::uuid, 4.00, NULL, 1, '0590883427c8597faea3a3918717b3d8'::uuid, 4588452),
('fb192c191e7c4c96b1465eb20f57a291'::uuid, 16.00, 10.00, 1, '022b6365d7ce58d0b3cebe205f8a0151'::uuid, 1),
('fe4b06ddc15343deafba8ebef3ed2a7d'::uuid, 24.00, 0.00, 5, '37d947f088cc55f1be5bd59977d45976'::uuid, 7465833)
ON CONFLICT (id) DO UPDATE SET avg_active_hours = EXCLUDED.avg_active_hours, hours_standby = EXCLUDED.hours_standby, quantity = EXCLUDED.quantity, product_id = EXCLUDED.product_id, user_id = EXCLUDED.user_id;
INSERT INTO public.energy_label_class (id, label_class, updated_at) VALUES
('17ec20331274587c9c0803f16e660662'::uuid, 'A+++', '2026-10-15 20:58:22.566199+00:00'::timestamptz),
('a869831f0baa5dcfacf729b5bb7baeaf'::uuid, 'A', '2026-10-15 20:58:22.566199+00:00'::timestamptz),
('b03224d6390e55a59ea893d8f62bc65c'::uuid, 'A+++', '2026-10-15 20:58:22.566199+00:00'::timestamptz)
ON CONFLICT (id) DO UPDATE SET label_class = EXCLUDED.label_class, updated_at = EXCLUDED.updated_at;

-- ============================================================================
-- SINCRONIZA A SEQUENCE apos a carga (funciona mesmo com users vazio)
-- ============================================================================
SELECT setval('public.users_id_seq', COALESCE((SELECT MAX(id) FROM public.users), 0) + 1, false);
