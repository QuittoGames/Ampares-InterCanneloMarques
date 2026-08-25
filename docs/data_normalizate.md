# Normalizaço de  dados vindos da API SOCRATA

# Introduçao


# Formuulas aplicadas

Com isso em mente , nas buscas para produzir uma forma de calcular precisamente o valor gasto osiosametne pelos produtos , a propia Energy Star , detetora da API Scorata , possue um  banco de formulas as quais podem ser usadas neste cotexto , como podemos ver abai

## Fórmula de consumo energético anual

A energia consumida por um aparelho pode ser estimada a partir da
potência utilizada em cada modo de operação e do tempo em que o
aparelho permanece nesse modo.

A formulação geral é:

$$
E_{\text{ano}} =
\frac{1}{1000}
\sum_{i=1}^{n} P_i H_i
$$

Onde:

- $E_{\text{ano}}$ = energia consumida no ano, em **kWh**
- $P_i$ = potência média no modo de operação $i$, em **watts (W)**
- $H_i$ = quantidade de horas anuais no modo de operação $i$
- $n$ = número de modos de operação considerados

### Aparelho com um único modo de operação

Para um aparelho que possui aproximadamente uma única potência de
operação:

$$
E_{\text{ano}} =
\frac{P \times H}{1000}
$$

Onde:

- $P$ = potência média do aparelho em watts
- $H$ = quantidade de horas de funcionamento por ano

### Exemplo

Considere um aparelho com potência média de:

$$
P = 150\,W
$$

e utilização durante:

$$
H = 1333{,}3\,h/ano
$$

Então:

$$
E_{\text{ano}} =
\frac{150 \times 1333{,}3}{1000}
$$

$$
E_{\text{ano}} \approx 200\,kWh/ano
$$

---

## Modelo com múltiplos modos de operação

Para aparelhos que possuem diferentes níveis de consumo, podemos
modelar cada estado separadamente:

$$
E_{\text{ano}} =
\frac{
P_{\text{ativo}}H_{\text{ativo}}
+
P_{\text{standby}}H_{\text{standby}}
+
P_{\text{off}}H_{\text{off}}
}{1000}
$$

As horas devem satisfazer:

$$
H_{\text{ativo}}
+
H_{\text{standby}}
+
H_{\text{off}}
=
8760
$$

pois um ano possui aproximadamente:

$$
365 \times 24 = 8760\,h
$$

---

## Estimativa de horas equivalentes de utilização

Quando o consumo anual e a potência média já são conhecidos, podemos
obter uma estimativa das horas equivalentes de funcionamento:

$$
H_{\text{equiv}} =
\frac{1000E_{\text{ano}}}{P}
$$

Por exemplo, para:

$$
E_{\text{ano}} = 200\,kWh/ano
$$

e:

$$
P = 150\,W
$$

temos:

$$
H_{\text{equiv}} =
\frac{1000 \times 200}{150}
$$

$$
H_{\text{equiv}} \approx 1333{,}3\,h/ano
$$

Convertendo para uma média diária:

$$
H_{\text{dia}} =
\frac{H_{\text{equiv}}}{365}
$$

$$
H_{\text{dia}} \approx 3{,}65\,h/dia
$$

> **Observação:** $H_{\text{equiv}}$ representa horas equivalentes de
> operação na potência média considerada. Ela não necessariamente
> corresponde ao número real de horas em que o aparelho permaneceu
> ligado, especialmente em equipamentos cuja potência varia durante
> o funcionamento.
