package cannelo.marques.interdisciplinar.interdisciplinar.Services.User;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.sql.ResultSet;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.jdbc.core.RowCallbackHandler;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.core.namedparam.SqlParameterSource;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;

/**
 * Testes unitários de {@link ProductVoltageService#decorate(java.util.Collection)}.
 *
 * <p>A consulta real usa a sobrecarga {@code void query(String, SqlParameterSource,
 * RowCallbackHandler)} do {@link NamedParameterJdbcTemplate}. Cada teste mocka
 * essa sobrecarga com {@code doAnswer} e alimenta o {@link RowCallbackHandler}
 * capturado com um {@link ResultSet} mockado, simulando as linhas que o banco
 * (UNION DISTINCT + ORDER BY) devolveria. O serviço MUTA
 * {@code declaredVoltages} de cada produto — os asserts leem
 * {@code product.getDeclaredVoltages()}.</p>
 */
@ExtendWith(MockitoExtension.class)
class ProductVoltageServiceTest {

    @Mock
    private NamedParameterJdbcTemplate jdbcTemplate;

    private ProductVoltageService service;

    /** Uma linha que o resultset devolveria: (product_id, voltage). */
    private record Row(UUID productId, BigDecimal voltage) {
    }

    @BeforeEach
    void setUp() {
        service = new ProductVoltageService(jdbcTemplate);
    }

    /**
     * Stub da sobrecarga {@code void query(String, SqlParameterSource, RowCallbackHandler)}
     * que, ao ser invocada, chama o {@link RowCallbackHandler} uma vez por linha —
     * exatamente como o JdbcTemplate real percorre o resultset.
     */
    private void stubQueryReturning(Row... rows) {
        doAnswer(invocation -> {
            RowCallbackHandler handler = invocation.getArgument(2);
            for (Row row : rows) {
                ResultSet resultSet = mock(ResultSet.class);
                when(resultSet.getObject("product_id", UUID.class)).thenReturn(row.productId());
                when(resultSet.getBigDecimal("voltage")).thenReturn(row.voltage());
                handler.processRow(resultSet);
            }
            return null;
        }).when(jdbcTemplate)
                .query(anyString(), any(SqlParameterSource.class), any(RowCallbackHandler.class));
    }

    @Test
    @DisplayName("Monovolt 127/127: UNION DISTINCT devolve uma única linha e o produto recebe [127]")
    void shouldCollapseMonoVoltObservationIntoSingleVoltage() {
        UUID id = UUID.randomUUID();
        Product product = new Product(id);
        stubQueryReturning(new Row(id, new BigDecimal("127")));

        service.decorate(List.of(product));

        assertEquals(List.of(127), product.getDeclaredVoltages());
    }

    @Test
    @DisplayName("Bivolt 110/220: serviço preserva a ordem das linhas do banco (ORDER BY é do SQL)")
    void shouldPreserveOrderOfRowsReturnedByDatabase() {
        UUID id = UUID.randomUUID();
        Product product = new Product(id);
        stubQueryReturning(
                new Row(id, new BigDecimal("110")),
                new Row(id, new BigDecimal("220")));

        service.decorate(List.of(product));

        assertEquals(List.of(110, 220), product.getDeclaredVoltages());
    }

    @Test
    @DisplayName("Arredondamento HALF_UP: 220.4 vira 220")
    void shouldRoundVoltageHalfUpToInteger() {
        UUID id = UUID.randomUUID();
        Product product = new Product(id);
        stubQueryReturning(new Row(id, new BigDecimal("220.4")));

        service.decorate(List.of(product));

        assertEquals(List.of(220), product.getDeclaredVoltages());
    }

    @Test
    @DisplayName("Fronteira HALF_UP: 220.5 vira 221 (distingue HALF_UP de DOWN/HALF_EVEN/HALF_DOWN)")
    void shouldRoundVoltageHalfUpAtFiveBoundary() {
        UUID id = UUID.randomUUID();
        Product product = new Product(id);
        stubQueryReturning(new Row(id, new BigDecimal("220.5")));

        service.decorate(List.of(product));

        assertEquals(List.of(221), product.getDeclaredVoltages());
    }

    @Test
    @DisplayName("Vários produtos: linhas intercaladas são agrupadas por product_id")
    void shouldGroupVoltagesByProductIdWhenMultipleProductsHaveData() {
        UUID fridgeId = UUID.randomUUID();
        UUID washerId = UUID.randomUUID();
        Product fridge = new Product(fridgeId);
        Product washer = new Product(washerId);
        // ordem intercalada, como o UNION poderia devolver entre produtos
        stubQueryReturning(
                new Row(fridgeId, new BigDecimal("127")),
                new Row(washerId, new BigDecimal("220")),
                new Row(fridgeId, new BigDecimal("220")));

        service.decorate(List.of(fridge, washer));

        assertEquals(List.of(127, 220), fridge.getDeclaredVoltages());
        assertEquals(List.of(220), washer.getDeclaredVoltages());
    }

    @Test
    @DisplayName("Resultset vazio: todos os produtos recebem lista vazia")
    void shouldAssignEmptyListToAllProductsWhenNoRowsReturned() {
        Product first = new Product(UUID.randomUUID());
        Product second = new Product(UUID.randomUUID());
        stubQueryReturning();

        service.decorate(List.of(first, second));

        assertEquals(List.of(), first.getDeclaredVoltages());
        assertEquals(List.of(), second.getDeclaredVoltages());
    }

    @Test
    @DisplayName("Coleção vazia: não consulta o banco")
    void shouldNotQueryDatabaseWhenCollectionIsEmpty() {
        service.decorate(List.of());

        verifyNoInteractions(jdbcTemplate);
    }

    @Test
    @DisplayName("Ids nulos são filtrados: só o id não-nulo vai para o parâmetro 'ids'")
    void shouldExcludeNullIdsFromQueryParameters() {
        UUID validId = UUID.randomUUID();
        Product withNullId = new Product();
        Product withValidId = new Product(validId);

        service.decorate(List.of(withNullId, withValidId));

        ArgumentCaptor<SqlParameterSource> params = ArgumentCaptor.forClass(SqlParameterSource.class);
        verify(jdbcTemplate).query(anyString(), params.capture(), any(RowCallbackHandler.class));
        @SuppressWarnings("unchecked")
        List<UUID> sentIds = (List<UUID>) params.getValue().getValue("ids");
        assertEquals(List.of(validId), sentIds);
    }

    @Test
    @DisplayName("Mistura: produto com dados recebe lista, produto sem dados recebe []")
    void shouldFillOnlyProductsWithDeclaredVoltages() {
        UUID withDataId = UUID.randomUUID();
        Product withData = new Product(withDataId);
        Product withoutData = new Product(UUID.randomUUID());
        stubQueryReturning(new Row(withDataId, new BigDecimal("220")));

        service.decorate(List.of(withData, withoutData));

        assertEquals(List.of(220), withData.getDeclaredVoltages());
        assertEquals(List.of(), withoutData.getDeclaredVoltages());
    }
}
