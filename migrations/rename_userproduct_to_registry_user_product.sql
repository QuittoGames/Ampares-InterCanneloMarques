-- migrations/rename_userproduct_to_registry_user_product.sql
-- Refatoração arquitetural: renomeia a tabela userproduct para
-- registry_user_product para refletir a nova entidade JPA RegistryUserProduct.
--
-- Estratégia: ALTER TABLE RENAME (preserva todos os dados, FKs, índices e
-- constraints). Nada é dropado.
--
-- Compatibilidade:
--   - PostgreSQL mantém os OIDs das constraints ao renomear a tabela, então
--     as FKs e a UNIQUE(user_id, product_id) continuam funcionando sem mudanças.
--   - O índice uk_userproduct_user_product do seed.sql tem nome fixo
--     (não acompanha o rename) — opcionalmente pode ser renomeado para
--     uk_registry_user_product_user_product para coerência, mas isso NÃO é
--     necessário para o funcionamento.

BEGIN;

ALTER TABLE userproduct RENAME TO registry_user_product;

COMMIT;
