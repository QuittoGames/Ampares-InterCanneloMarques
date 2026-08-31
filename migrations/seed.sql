-- migrations/seed.sql
-- Script de carga inicial para dados de teste (User + RegistryUserProduct)
-- Compatível mesmo se a tabela registry_user_product não tiver constraint UNIQUE pré-existente.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Cria ou atualiza o Usuário de Teste
-- ---------------------------------------------------------------------------
INSERT INTO users (id, name)
VALUES (1, 'Usuário Teste')
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name;

-- Sincroniza a sequence do SERIAL
SELECT setval(pg_get_serial_sequence('users', 'id'), COALESCE((SELECT MAX(id) FROM users), 1));

-- ---------------------------------------------------------------------------
-- 2. Garante o Índice Único (opcional, mas recomendado para integridade)
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uk_registry_user_product_user_product
ON registry_user_product (user_id, product_id);

-- ---------------------------------------------------------------------------
-- 3. Vincula o Usuário aos Produtos Existentes
-- ---------------------------------------------------------------------------
-- Usa WHERE NOT EXISTS para garantir idempotência mesmo sem depender do ON CONFLICT
INSERT INTO registry_user_product (id, user_id, product_id, quantity, avg_active_hours, hours_standby)
SELECT
    gen_random_uuid() AS id,
    1 AS user_id,
    p.id AS product_id,
    1 AS quantity,
    COALESCE(
        CASE
            WHEN p.avg_power_w >= 1000 THEN 4.0   -- Alta potência: 4h/dia
            WHEN p.avg_power_w >= 200  THEN 8.0   -- Média potência: 8h/dia
            ELSE 16.0                             -- Baixa potência: 16h/dia
        END,
        6.0
    ) AS avg_active_hours,
    COALESCE(
        CASE
            WHEN p.avg_power_w >= 1000 THEN 20.0
            WHEN p.avg_power_w >= 200  THEN 16.0
            ELSE 8.0
        END,
        18.0
    ) AS hours_standby
FROM (
    SELECT id, avg_power_w
    FROM product
    ORDER BY id
    LIMIT 5
) p
WHERE NOT EXISTS (
    SELECT 1 FROM registry_user_product up
    WHERE up.user_id = 1 AND up.product_id = p.id
);

COMMIT;
