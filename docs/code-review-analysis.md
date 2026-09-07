# Análise Completa do Backend Java — Ampares-InterCanneloMarques

Data: 2026-09-07
Escopo: src/main/java (612 linhas, 18 arquivos)

## 1. Falhas críticas
- RegistryUserService.createRegistry (l.81-84): fallback calcula unidade errada (kWh em horas) e salva antes do set.
- calculateAverageEnergyByUser duplica calculateEnergyByUser; divide total/quantidade (não pondera quantity).
- AuthService.login: NumberFormatException escapa; Integer.valueOf duplicado.
- CookieService.get compara com cookie.getValue() (nunca usado, mas quebrado).
- User.removeRegistryUserProduct usa indexOf(UUID) em RegistryUserProduct.
- User.equals sem hashCode; registryUserProducts sem cascade.
- MetricsByUserDTO/Category/Standby: @Valid não acionado nos endpoints MetricsController.
- UserService.addProduct não usa resultado; removeProduct não deleta; métodos não têm endpoint.

## 2. Segurança
- Auth é ID arbitrário + cookie sem Secure/SameSite; sem senha/token.
- debug=true em production (application.properties).
- data-rest expõe CRUD público sem auth (/product, /users, /registryUserProduct).
- .env importado opcionalmente; URL DB expõe credenciais.
- Sem CORS configurado.

## 3. JPA / Persistência
- ddl-auto=update sem migração (Flyway/Liquibase ausente).
- User.id = int IDENTITY; Product/Registry = UUID — mistura.
- findByUser gera N+1 (sem JOIN FETCH). Sem paginação.
- Repository: métodos derivados nunca usados.

## 4. Cálculo / Domínio
- RegistryUserService: cálculo contínuo diverge de thresholds do seed.sql.
- calculateMostConsumerProduct ignora standby; averageEnergyByUser não pondera quantity.
- avg(): sem null guard; divide sem checar lista vazia.
- BigDecimal.divide sem escala (risco ArithmeticException).

## 5. Arquitetura / Padrões
- HoursProvider (@Aspect mal usado, código morto).
- MetricsService genérico inútil (<Client extends User>); MetricsByCategoryDTO sem uso no controller.
- Lombok no POM mas não usado (entidades com getters/setters manuais).
- SpringAplicationMapper vazio / typo.
- AuthService usa jakarta.transaction.Transactional.
- Código morto: CookieService.get, UserService.add/remove (sem endpoint).
- MetricsController injeta Repositories diretamente.

## 6. Performance
- Queries não agregadas; cálculos em Java que cabem em SQL.
- findByUser sem JOIN FETCH = N+1.
- Sem cache; sem paginação.
- 2-3 queries por endpoint de métricas.

## 7. Testes
- Cobertura: apenas ConsumptionCalculatorTest e RegistryCalculatorTest. 0 testes de service/controller/repository.

## 8. Configuração / Build
- webservices, restclient, aspectj: sem uso.
- data-rest: expõe CRUD público.
- springdoc-openapi: sem restrição de acesso.
- Sem profile prod/dev.

## Prioridade
Top 5: isolar data-rest, corrigir RegistryUserService fallback, @Valid nos DTOs, auth real, JOIN FETCH findByUser.
Backlog: Lombok, SQL agregado, CORS/auth, profile prod, Flyway.
