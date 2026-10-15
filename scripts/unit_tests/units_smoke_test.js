'use strict';

/**
 * Smoke test do units.js — frontend (src/main/resources/static/units.js).
 *
 * Node puro, sem dependências, sem package.json.
 * Executar: node scripts/unit_tests/units_smoke_test.js
 * Sai com exit code 1 se algum caso falhar.
 */

const Units = require('../../src/main/resources/static/units.js');

let passed = 0;
let failed = 0;
const failures = [];

function check(label, actual, expected) {
    if (Object.is(actual, expected)) {
        passed += 1;
        return;
    }

    failed += 1;
    failures.push(`${label}\n    esperado: ${JSON.stringify(expected)}\n    obtido:  ${JSON.stringify(actual)}`);
}

// --- formatPowerW -----------------------------------------------------------
check('formatPowerW(150)', Units.formatPowerW(150), '150 W');
check("formatPowerW('62.50')", Units.formatPowerW('62.50'), '62,5 W');
check('formatPowerW(null)', Units.formatPowerW(null), '');
check('formatPowerW(0)', Units.formatPowerW(0), '');
check('formatPowerW(-5) [negativo omite]', Units.formatPowerW(-5), '');
check("formatPowerW('1.032,5') [milhar pt-BR]", Units.formatPowerW('1.032,5'), '1.032,5 W');

// --- formatVoltage ----------------------------------------------------------
check('formatVoltage(127)', Units.formatVoltage(127), '127 V');
check(
    'formatVoltage(monovolt 110/110) [nunca vira 127]',
    Units.formatVoltage({ kind: 'monovolt', minV: 110, maxV: 110 }),
    '110 V'
);
check(
    'formatVoltage(bivolt 110-220)',
    Units.formatVoltage({ kind: 'bivolt', minV: 110, maxV: 220 }),
    '110/220 V'
);
check(
    'formatVoltage(bivolt com 1 número) [preserva fato bivolt]',
    Units.formatVoltage({ kind: 'bivolt', minV: 110, maxV: null }),
    'Bivolt'
);
check(
    "formatVoltage(bivolt sem números, raw='Sim') [raw nunca exibido]",
    Units.formatVoltage({ kind: 'bivolt', minV: null, maxV: null, raw: 'Sim' }),
    'Bivolt'
);
check(
    'formatVoltage(range 100-240)',
    Units.formatVoltage({ kind: 'range', minV: 100, maxV: 240 }),
    '100-240 V'
);
check('formatVoltage({kind:unknown})', Units.formatVoltage({ kind: 'unknown' }), '');
check('formatVoltage(null)', Units.formatVoltage(null), '');
check("formatVoltage('127 V') [string não numérica]", Units.formatVoltage('127 V'), '');

// --- formatVoltages (lista de tensões declaradas do produto) ----------------
// Contrato real: backend envia JSON array via List<Integer> ([127, 220]).
check("formatVoltages(['127','220']) [strings numéricas]", Units.formatVoltages(['127', '220']), '127/220 V');
check('formatVoltages([127, 220]) [array ordena e deduplica]', Units.formatVoltages([220, 127, 220]), '127/220 V');
check('formatVoltages([127]) [monovolt único]', Units.formatVoltages([127]), '127 V');
check("formatVoltages(['127.00']) [decimal vira inteiro]", Units.formatVoltages(['127.00']), '127 V');
check('formatVoltages([]) [vazio omite]', Units.formatVoltages([]), '');
check('formatVoltages(null) [ausente omite]', Units.formatVoltages(null), '');
check("formatVoltages(['n/a']) [não numérico omite]", Units.formatVoltages(['n/a']), '');

// --- formatEnergyKwh --------------------------------------------------------
check(
    "formatEnergyKwh('1,5', 'dia') [vírgula pt-BR]",
    Units.formatEnergyKwh('1,5', 'dia'),
    '1,5 kWh/dia'
);
check(
    "formatEnergyKwh(1032.5, 'dia')",
    Units.formatEnergyKwh(1032.5, 'dia'),
    '1.032,5 kWh/dia'
);
check(
    "formatEnergyKwh('1.032,5', 'ano') [milhar+decimal pt-BR]",
    Units.formatEnergyKwh('1.032,5', 'ano'),
    '1.032,5 kWh/ano'
);
check("formatEnergyKwh(null, 'dia')", Units.formatEnergyKwh(null, 'dia'), '');

// --- formatHoursPerDay ------------------------------------------------------
check('formatHoursPerDay(8)', Units.formatHoursPerDay(8), '8 h/dia');
check('formatHoursPerDay(8.5)', Units.formatHoursPerDay(8.5), '8,5 h/dia');
check('formatHoursPerDay(null)', Units.formatHoursPerDay(null), '');
check('formatHoursPerDay(0) [zero declarado exibido]', Units.formatHoursPerDay(0), '0 h/dia');

// --- formatBrl vs Intl ------------------------------------------------------
const brlExpected = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(1234.56);
check('formatBrl(1234.56) === Intl pt-BR BRL', Units.formatBrl(1234.56), brlExpected);
check('formatBrl(1234.56) não vazio', Units.formatBrl(1234.56) !== '', true);
check('formatBrl(null)', Units.formatBrl(null), '');

// --- formatNumberPtBR -------------------------------------------------------
check("formatNumberPtBR('62,50')", Units.formatNumberPtBR('62,50'), '62,5');

// --- Resultado --------------------------------------------------------------
const total = passed + failed;

if (failures.length > 0) {
    console.log('FALHAS:\n');
    failures.forEach((failure) => console.log(`  ✗ ${failure}\n`));
}

console.log(`units_smoke_test: ${passed}/${total} casos passaram${failed ? ` (${failed} falharam)` : ''}`);

if (failed > 0) {
    process.exitCode = 1;
}
