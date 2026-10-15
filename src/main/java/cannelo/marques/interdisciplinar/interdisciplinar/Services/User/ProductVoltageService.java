package cannelo.marques.interdisciplinar.interdisciplinar.Services.User;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;

import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;

/**
 * Popula {@link Product#setDeclaredVoltages(List)} com as tensões
 * DISTINCTAS declaradas nas observações de fonte
 * ({@code product_source_observation}) — dado de EXIBIÇÃO da UI
 * ("Geladeira (150 W · 127/220 V)"), não persistido na entidade.
 *
 * <p>Consulta via {@code NamedParameterJdbcTemplate} (não vira entidade
 * JPA): a tabela pertence ao pipeline do collector e o
 * {@code ddl-auto=update} não deve tocá-la.</p>
 *
 * <p>Regras (mesmas do {@code collector/voltage.py} e do
 * {@code units.js} — nunca converter, nunca inferir):</p>
 * <ul>
 *   <li>somente valores efetivamente declarados ({@code voltage_min_v} /
 *       {@code voltage_max_v} não nulos — observações {@code unknown} não
 *       têm números e caem fora naturalmente);</li>
 *   <li>monovolt 127/127 → [127]; bivolt 110/220 → [110, 220]; range →
 *       [min, max]; produto só com tensões desconhecidas → lista vazia;</li>
 *   <li>ordem crescente, sem duplicatas (UNION + ordenação do banco).</li>
 * </ul>
 */
@Service
public class ProductVoltageService {

    private static final String DECLARED_VOLTAGES_QUERY = """
            SELECT declared.product_id, declared.voltage
            FROM (
                SELECT DISTINCT o.canonical_product_id AS product_id, o.voltage_min_v AS voltage
                FROM product_source_observation o
                WHERE o.canonical_product_id IN (:ids)
                  AND o.voltage_min_v IS NOT NULL
                UNION
                SELECT DISTINCT o.canonical_product_id AS product_id, o.voltage_max_v AS voltage
                FROM product_source_observation o
                WHERE o.canonical_product_id IN (:ids)
                  AND o.voltage_max_v IS NOT NULL
            ) declared
            ORDER BY declared.product_id, declared.voltage
            """;

    private final NamedParameterJdbcTemplate jdbcTemplate;

    public ProductVoltageService(NamedParameterJdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    /**
     * Preenche {@code declaredVoltages} de cada produto da coleção.
     * Produtos sem tensão declarada recebem lista vazia (a UI omite —
     * nunca infere). Ids nulos são ignorados; coleção sem ids válidos
     * não consulta o banco.
     */
    @Transactional(readOnly = true)
    public void decorate(Collection<Product> products) {
        List<UUID> ids = products.stream()
                .map(Product::getId)
                .filter(Objects::nonNull)
                .toList();

        if (ids.isEmpty()) {
            return;
        }

        Map<UUID, List<Integer>> voltagesByProduct = new HashMap<>();

        jdbcTemplate.query(
                DECLARED_VOLTAGES_QUERY,
                new MapSqlParameterSource("ids", ids),
                resultSet -> {
                    UUID productId = resultSet.getObject("product_id", UUID.class);
                    BigDecimal voltage = resultSet.getBigDecimal("voltage");

                    voltagesByProduct
                            .computeIfAbsent(productId, key -> new ArrayList<>())
                            .add(voltage.setScale(0, RoundingMode.HALF_UP).intValue());
                });

        products.forEach(product -> product.setDeclaredVoltages(
                voltagesByProduct.getOrDefault(product.getId(), List.of())));
    }
}
