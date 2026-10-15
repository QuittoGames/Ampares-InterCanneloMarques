/**
 * units.js — módulo central de formatação de unidades do frontend.
 *
 * Único lugar onde unidades de grandezas são escritas para exibição:
 * potência em W, voltagem/tensão em V, energia em kWh, horas em h/dia,
 * custo em R$ (pt-BR, vírgula decimal).
 *
 * Regras de voltagem (espelha energy_collector/collector/voltage.py):
 * - NUNCA converter tensão (110 V não vira 127 V; sem fator algum);
 * - NUNCA inferir tensão ausente (unknown/null → omite);
 * - unidade sempre "V" maiúsculo; valores exibidos como inteiros.
 *
 * Carregado no index.html ANTES de app.js. Sem bundler/ES modules:
 * expõe `window.Units` (padrão vanilla do projeto).
 */
(function (global) {
    'use strict';

    /**
     * Parse tolerante de base numérica: aceita number | string numérica
     * com ponto ("150.00"), vírgula pt-BR ("62,50") ou milhar pt-BR
     * com decimal ("1.032,5" → 1032.5: '.' de milhar removido, ',' → '.').
     * Inválido/ausente → null.
     */
    function parseNumber(value) {
        if (value === null || value === undefined) {
            return null;
        }

        if (typeof value === 'number') {
            return Number.isFinite(value) ? value : null;
        }

        const text = String(value).trim();

        if (!text) {
            return null;
        }

        // pt-BR com milhar e decimal ('1.032,5'): remove '.' e troca ',' por '.'.
        // Caso contrário, troca apenas a vírgula decimal ('62,50').
        const normalized = text.includes('.') && text.includes(',')
            ? text.replace(/\./g, '').replace(',', '.')
            : text.replace(',', '.');

        const parsed = Number(normalized);
        return Number.isFinite(parsed) ? parsed : null;
    }

    /**
     * Base numérica pt-BR.
     * @returns {'150' | '62,5' | ''} '' quando valor inválido/ausente.
     */
    function formatNumberPtBR(value, options) {
        const maxFractionDigits = (options && options.maxFractionDigits !== undefined)
            ? options.maxFractionDigits
            : 3;
        const parsed = parseNumber(value);

        if (parsed === null) {
            return '';
        }

        return new Intl.NumberFormat('pt-BR', { maximumFractionDigits: maxFractionDigits }).format(parsed);
    }

    /**
     * Potência em W. `formatPowerW(150)` → '150 W'; `formatPowerW('62.50')` →
     * '62,5 W'; null/undefined/ausente/0/negativo → '' (omite — comportamento
     * atual de ocultar potência zero/ausente preservado; negativo é inválido).
     */
    function formatPowerW(value) {
        const parsed = parseNumber(value);

        if (parsed === null || parsed <= 0) {
            return '';
        }

        const formatted = formatNumberPtBR(parsed, { maxFractionDigits: 2 });
        return formatted ? `${formatted} W` : '';
    }

    /**
     * Inteiro para exibição de tensão (sem agrupamento, sem conversão).
     */
    function formatVoltageInteger(value) {
        return String(Math.round(value));
    }

    /**
     * Voltagem/tensão em V — nunca convertida, nunca inferida.
     *
     * Aceita:
     * - number | string numérica → valor monovolt declarado (127 → '127 V');
     * - payload { kind, minV, maxV, raw } (espelha as colunas voltage_*
     *   de product_source_observation) | null → ''.
     *
     * Semântica (collector/voltage.py):
     * - monovolt 127/127 → '127 V'; 110/110 → '110 V' (NUNCA vira 127);
     * - bivolt 110/220 → '110/220 V'; bivolt com números incompletos ou
     *   sem números → 'Bivolt' (preserva o fato bivolt; `raw` NUNCA é exibido);
     *   bivolt completo com par igual → '110 V';
     * - range 100/240 → '100-240 V';
     * - unknown | entrada nula → '' (omite; nunca inferir por país/categoria).
     */
    function formatVoltage(voltage) {
        if (voltage === null || voltage === undefined) {
            return '';
        }

        if (typeof voltage === 'number' || typeof voltage === 'string') {
            const single = parseNumber(voltage);
            return single !== null ? `${formatVoltageInteger(single)} V` : '';
        }

        if (typeof voltage !== 'object') {
            return '';
        }

        const kind = typeof voltage.kind === 'string' ? voltage.kind.trim().toLowerCase() : '';
        const min = parseNumber(voltage.minV);
        const max = parseNumber(voltage.maxV);

        if (kind === 'monovolt') {
            const declared = min !== null ? min : max;
            return declared !== null ? `${formatVoltageInteger(declared)} V` : '';
        }

        if (kind === 'bivolt') {
            if (min !== null && max !== null) {
                return min === max
                    ? `${formatVoltageInteger(min)} V`
                    : `${formatVoltageInteger(min)}/${formatVoltageInteger(max)} V`;
            }

            // Números incompletos (um dos dois) ou ausentes: preserva o fato
            // bivolt e não expõe `raw` (texto arbitrário do backend) na UI.
            return 'Bivolt';
        }

        if (kind === 'range') {
            if (min !== null && max !== null) {
                return `${formatVoltageInteger(min)}-${formatVoltageInteger(max)} V`;
            }

            const single = min !== null ? min : max;
            return single !== null ? `${formatVoltageInteger(single)} V` : '';
        }

        // unknown / não classificado / ausente → omite (nunca inferir).
        return '';
    }

    /**
     * Lista de tensões declaradas (ex.: [127, 220]) → '127/220 V';
     * [127] → '127 V'. Inteiros ordenados e sem duplicata; conversão e
     * inferência proibidas (mesmas regras de formatVoltage). Ausente/vazia
     * → '' (omite).
     */
    function formatVoltages(values) {
        if (!Array.isArray(values) || values.length === 0) {
            return '';
        }

        const integers = [...new Set(
            values
                .map(parseNumber)
                .filter((parsed) => parsed !== null)
                .map((parsed) => Math.round(parsed)),
        )].sort((a, b) => a - b);

        return integers.length > 0 ? `${integers.join('/')} V` : '';
    }

    /**
     * Energia em kWh com 3 casas decimais (pt-BR):
     * `formatEnergyKwh(1.032, 'dia')` → '1,032 kWh/dia';
     * `formatEnergyKwh(value, 'ano')` → '… kWh/ano'. Ausente → ''.
     */
    function formatEnergyKwh(value, period) {
        const formatted = formatNumberPtBR(value, { maxFractionDigits: 3 });

        if (!formatted) {
            return '';
        }

        const suffix = period === 'dia' || period === 'ano' ? ` kWh/${period}` : ' kWh';
        return `${formatted}${suffix}`;
    }

    /**
     * Horas por dia com 1 casa decimal quando fracionário:
     * 8 → '8 h/dia'; 8.5 → '8,5 h/dia'. Ausente (null/undefined) → ''.
     * Zero declarado é exibido ('0 h/dia') — só ausência omite.
     */
    function formatHoursPerDay(value) {
        const parsed = parseNumber(value);

        if (parsed === null) {
            return '';
        }

        const formatted = formatNumberPtBR(parsed, { maxFractionDigits: 1 });
        return formatted ? `${formatted} h/dia` : '';
    }

    /** Custo BRL — idêntico ao Intl pt-BR BRL do app (2 casas, R$). Ausente → ''. */
    function formatBrl(value) {
        const parsed = parseNumber(value);

        if (parsed === null) {
            return '';
        }

        return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(parsed);
    }

    const Units = Object.freeze({
        formatNumberPtBR,
        formatPowerW,
        formatVoltage,
        formatVoltages,
        formatEnergyKwh,
        formatHoursPerDay,
        formatBrl,
    });

    global.Units = Units;

    // Smoke test real: scripts/unit_tests/units_smoke_test.js (node puro, sem
    // dependências). O guard abaixo é o que permite carregar o módulo no Node.
    if (typeof module !== 'undefined' && module.exports) {
        module.exports = Units;
    }
})(typeof window !== 'undefined' ? window : globalThis);
