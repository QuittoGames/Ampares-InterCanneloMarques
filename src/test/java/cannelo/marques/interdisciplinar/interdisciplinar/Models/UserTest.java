package cannelo.marques.interdisciplinar.interdisciplinar.Models;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * Testes unitários para {@link User} — entidade enxuta (id + name).
 *
 * <p>Sem Spring context (rápido, determinético). A associação M:N com
 * {@link Product} vive em {@code registry_user_product}
 * ({@link RegistryUserProduct}), NÃO em coleção na entidade User
 * (DECISÃO 003). Este teste cobre apenas o contrato atual de User:
 * construtores, getters, {@code setName}, {@code equals} e {@code toString}.
 */
class UserTest {

    // --------------------------------------------------------- construtores

    @Test
    @DisplayName("construtor completo: id e name são atribuídos")
    void construtorCompleto_atribuiIdEName() {
        User user = new User(7, "Quitto");

        assertEquals(7, user.getId());
        assertEquals("Quitto", user.getName());
    }

    @Test
    @DisplayName("construtor por id: name permanece null (estado transiente de login)")
    void construtorPorId_nameNulo() {
        User user = new User(3);

        assertEquals(3, user.getId());
        assertNull(user.getName());
    }

    @Test
    @DisplayName("construtor vazio: estado transiente para o JPA")
    void construtorVazio_estadoTransiente() {
        User user = new User();

        assertEquals(0, user.getId());
        assertNull(user.getName());
    }

    // ----------------------------------------------------------------- setters

    @Test
    @DisplayName("setName: altera o name após construção")
    void setName_alteraName() {
        User user = new User(1);
        user.setName("Maria");

        assertEquals("Maria", user.getName());
    }

    // ------------------------------------------------------------------ equals

    @Test
    @DisplayName("equals: mesma instância é igual (reflexividade)")
    void equals_mesmaInstancia() {
        User user = new User(1, "Quitto");

        assertTrue(user.equals(user));
    }

    @Test
    @DisplayName("equals: id e name iguais em instâncias distintas são iguais")
    void equals_instanciasDiferentesComMesmoEstado() {
        User a = new User(1, "Quitto");
        User b = new User(1, "Quitto");

        assertTrue(a.equals(b));
        assertEquals(a.hashCode(), b.hashCode(), "hashCode deve ser estável para iguais");
    }

    @Test
    @DisplayName("equals: id diferente torna os usuários desiguais")
    void equals_idDiferente() {
        User a = new User(1, "Quitto");
        User b = new User(2, "Quitto");

        assertNotEquals(a, b);
    }

    @Test
    @DisplayName("equals: name diferente torna os usuários desiguais")
    void equals_nameDiferente() {
        User a = new User(1, "Quitto");
        User b = new User(1, "Maria");

        assertNotEquals(a, b);
    }

    @Test
    @DisplayName("equals: null e classe diferente não são iguais")
    void equals_nullEDiferenteClasse() {
        User user = new User(1, "Quitto");

        assertFalse(user.equals(null));
        assertFalse(user.equals("Quitto"));
    }

    @Test
    @DisplayName("equals: name nulo em ambos é equivalente (idêntico estado nulo)")
    void equals_nameNuloEmAmbos() {
        User a = new User(1);
        User b = new User(1);

        assertTrue(a.equals(b));
    }

    @Test
    @DisplayName("equals: name nulo em um e presente no outro são desiguais")
    void equals_nameNuloEmUm() {
        User a = new User(1);
        User b = new User(1, "Quitto");

        assertNotEquals(a, b);
    }

    // ---------------------------------------------------------------- toString

    @Test
    @DisplayName("toString: formata id e name")
    void toString_formataCampos() {
        User user = new User(9, "Ana");

        assertEquals("User [id=9, name=Ana]", user.toString());
    }

    // ------------------------------------------------------- decisão 003

    @Test
    @DisplayName("decisão 003: entidade NÃO mantém coleção de registros (sem campo nem getter)")
    void entidadeNaoMantemColecaoDeRegistros() {
        assertThrows(NoSuchFieldException.class,
                () -> User.class.getDeclaredField("registryUserProducts"),
                "coleção bidirecional não deve existir em User (decisão 003)");
        assertThrows(NoSuchMethodException.class,
                () -> User.class.getDeclaredMethod("getRegistryUserProducts"),
                "não deve existir getter de coleção em User (decisão 003)");
    }
}
