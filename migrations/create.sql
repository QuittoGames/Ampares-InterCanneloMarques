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
--   * docs/arquiteture.drawio                           (modelo conceitual — parcialmente
--                                                       obsoleto, ver notas)
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
--    OBS: o desenho arquiteture.drawio mostra campos obsoletos em Product
--    (avg_cosume, quantity, avg_active_hours, hours_standby). Estes NÃO pertencem
--    aqui — os de uso foram movidos para registry_user_product (ver README do
--    coletor), e avg_cosume era um typo para avg_power_w + annual_energy_kwh.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS product (
    id                UUID PRIMARY KEY,
    name              VARCHAR(150),
    brand             VARCHAR(255),
    model             VARCHAR(255),
    category          VARCHAR(255),
    avg_power_w       NUMERIC,
    annual_energy_kwh NUMERIC
);

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
