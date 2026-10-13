-- migrations/create.sql
-- Schema inicial do banco (PostgreSQL) para Ampares-InterCanneloMarques.
--
-- Fontes autoritativas:
--   * src/main/java/.../Models/Product.java             (entidade JPA -> tabela product)
--   * src/main/java/.../Models/User.java                (entidade JPA -> tabela users)
--   * src/main/java/.../Models/RegistryUserProduct.java (entidade JPA -> tabela registry_user_product)
--   * energy_collector/collector/database.py            (DDL canônico da tabela product)
--   * energy_collector/README.md                        (refactor: campos de USO saíram de
--                                                       product e foram para registry_user_product)
--   * docs/arquiteture.drawio                           (espelha os 8 campos de Product;
--                                                       proveniencia/uso em outras tabelas)
--
-- Ordem importa: registry_user_product referencia users e product, então vem por último.

-- ---------------------------------------------------------------------------
-- 1. users
--    Fonte: User.java -> @Table(name = "users"); id INT (GenerationType.IDENTITY
--    => SERIAL), name VARCHAR(50) anulável.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(50)
);

-- ---------------------------------------------------------------------------
-- 2. product
--    Fonte: Product.java + energy_collector/collector/database.py (canônico).
--    Espelha exatamente a entidade JPA. O coletor Python popula esta MESMA
--    tabela (apenas atributos intrínsecos do aparelho).
--
--    OBS: o desenho arquiteture.drawio agora espelha EXATAMENTE estes 8
--    campos (spec "Brazil-Aware Product Normalization"). Os campos de USO
--    (quantity, avg_active_hours, hours_standby) vivem em
--    registry_user_product; standby_power_w, is_generic, tensao declarada
--    (voltage_*) e valores brutos de energia vivem em
--    product_source_observation (migrations 004/005). O diagrama nao tem
--    mais avg_cosume/avg_idle_energy_for_hour em Product.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS product (
    id                UUID PRIMARY KEY,
    name              VARCHAR(150),
    brand             VARCHAR(255),
    model             VARCHAR(255),
    category          VARCHAR(255),
    subcategory       VARCHAR(255),
    avg_power_w       NUMERIC,
    annual_energy_kwh NUMERIC
);


-- ---------------------------------------------------------------------------
-- 2b. product_source_observation (proveniência multi-fonte)
--     Fonte: migrations/004 + 005 (espelhadas aqui para bancos novos).
--     Uma linha = modelo/registro ESPECÍFICO observado em uma fonte,
--     ligado ao produto canônico. Carrega o que NÃO pertence ao contrato
--     Java Product: standby_power_w, is_generic, tensão declarada
--     (voltage_*) e o valor/período brutos de energia. O coletor grava
--     aqui apenas com INSERT ... ON CONFLICT (source, external_id) DO NOTHING.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS product_source_observation (
    id UUID PRIMARY KEY,
    canonical_product_id UUID NOT NULL REFERENCES product(id) ON DELETE CASCADE,
    source VARCHAR(50) NOT NULL,
    external_id VARCHAR(255) NOT NULL,
    brand VARCHAR(255),
    model VARCHAR(255),
    dataset_id VARCHAR(255),
    power_w NUMERIC CHECK (power_w IS NULL OR power_w >= 0),
    annual_energy_kwh NUMERIC CHECK (annual_energy_kwh IS NULL OR annual_energy_kwh >= 0),
    standby_power_w NUMERIC CHECK (standby_power_w IS NULL OR standby_power_w >= 0),
    is_generic BOOLEAN NOT NULL DEFAULT FALSE,
    voltage_raw VARCHAR(50),
    voltage_kind VARCHAR(16) NOT NULL DEFAULT 'unknown'
        CHECK (voltage_kind IN ('unknown','monovolt','bivolt','range')),
    voltage_min_v NUMERIC CHECK (voltage_min_v IS NULL OR voltage_min_v > 0),
    voltage_max_v NUMERIC CHECK (voltage_max_v IS NULL OR voltage_max_v > 0),
    raw_energy_value NUMERIC CHECK (raw_energy_value IS NULL OR raw_energy_value >= 0),
    raw_energy_unit VARCHAR(30),
    observed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source, external_id)
);

CREATE INDEX IF NOT EXISTS idx_product_source_observation_canonical
    ON product_source_observation (canonical_product_id);

CREATE INDEX IF NOT EXISTS idx_product_source_observation_source
    ON product_source_observation (source);

-- ---------------------------------------------------------------------------
-- 3. registry_user_product  (junção M:N entre users e product)
--    Fonte: RegistryUserProduct.java -> @Table(name = "registry_user_product").
--      - id UUID PK (GenerationType.UUID)
--      - user_id / product_id: FKs NOT NULL (JoinColumn nullable = false)
--      - quantity: int (primitivo => NOT NULL)
--      - avg_active_hours / hours_standby: BigDecimal => NUMERIC (anuláveis)
--    UNIQUE(user_id, product_id): impede o mesmo usuário associar o mesmo
--    produto duas vezes.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS registry_user_product (
    id                UUID PRIMARY KEY,
    user_id           INT    NOT NULL REFERENCES users(id),
    product_id        UUID   NOT NULL REFERENCES product(id),
    quantity          INT    NOT NULL,
    avg_active_hours  NUMERIC,
    hours_standby     NUMERIC,
    UNIQUE (user_id, product_id)
);
