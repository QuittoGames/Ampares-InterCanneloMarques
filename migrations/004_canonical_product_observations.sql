-- Proveniência multi-fonte sem alterar o contrato Spring da tabela product.
-- product continua sendo a projeção canônica; cada linha abaixo é uma
-- representação/modelo observado em uma fonte.
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
    observed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source, external_id)
);

CREATE INDEX IF NOT EXISTS idx_product_source_observation_canonical
    ON product_source_observation (canonical_product_id);

CREATE INDEX IF NOT EXISTS idx_product_source_observation_source
    ON product_source_observation (source);
