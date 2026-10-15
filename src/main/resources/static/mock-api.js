/**
 * mock-api.js — backend falso para o test.html rodar via Live Server, sem Spring.
 *
 * Carregado somente pelo test.html, ANTES de app.js. Intercepta window.fetch e
 * responde os endpoints que o app usa, com dados em memória:
 *
 *   POST /auth/login                        → ok (não valida ID)
 *   POST /auth/logout                       → ok + limpa registros (nova sessão)
 *   GET  /products?size=1000                → lista fixa de produtos
 *   GET  /registryUserProducts/user/{id}    → registros em memória
 *   POST /registryUserProducts              → grava em memória
 *   POST /api/metrics/users/calculate       → ResultDTO calculado (404 se vazio)
 *
 * Regra de consumo do mock (aproximação do backend, para o CP visual):
 *   kWh/dia = (quantidade × potência ativa × h ativas + quantidade × potência
 *             standby × h standby) / 1000
 *   custo   = kWh × tarifa (R$/kWh, constante abaixo), arredondado em 2 casas.
 *
 * Para desligar o mock e falar com um backend real: `?api=real` na URL do test.html.
 */
(function (global) {
    'use strict';

    if (new URLSearchParams(global.location.search).get('api') === 'real') {
        console.info('[mock-api] desativado (?api=real) — fetch passa adiante.');
        return;
    }

    const TARIFF_BRL_PER_KWH = 0.95;
    const LATENCY_MS = 150;

    /** Produtos simulados — mesmos campos que o app lê (name/brand/model/avgPowerW). */
    const products = [
        { id: 'mock-0001', name: 'Geladeira', brand: 'Electrolux', model: 'DM85X', avgPowerW: 120, avgStandbyPowerW: 2 },
        { id: 'mock-0002', name: 'Ar-condicionado', brand: 'Springer Midea', model: '12k BTUs', avgPowerW: 1300 },
        { id: 'mock-0003', name: 'Televisão', brand: 'LG', model: '55UR78', avgPowerW: 150, avgStandbyPowerW: 1 },
        { id: 'mock-0004', name: 'Computador', brand: 'Dell', model: 'Inspiron 15', avgPowerW: 300, avgStandbyPowerW: 3 },
        { id: 'mock-0005', name: 'Ventilador', brand: 'Mondial', model: 'AFN-40-G', avgPowerW: 75 },
        { id: 'mock-0006', name: 'Micro-ondas', brand: 'Philco', model: 'PME25', avgPowerW: 1400 },
    ];

    /** Registros "do usuário" em memória (perdem-se ao fechar a aba). */
    const userProducts = [];

    global.fetch = function mockFetch(input, init) {
        const url = new URL(typeof input === 'string' ? input : input.url, global.location.origin);
        const method = String((init && init.method) || (input && input.method) || 'GET').toUpperCase();
        const body = init && init.body ? JSON.parse(init.body) : null;

        return new Promise((resolve) => {
            setTimeout(() => resolve(route(url, method, body)), LATENCY_MS);
        });
    };

    function route(url, method, body) {
        const path = url.pathname;

        if (path === '/auth/login' && method === 'POST') {
            return json({ status: 'ok', userId: body && body.id });
        }

        if (path === '/auth/logout' && method === 'POST') {
            userProducts.length = 0;
            return json({ status: 'ok' });
        }

        if (path === '/products' && method === 'GET') {
            // normalizeProducts() aceita array simples (sem HAL).
            return json(products);
        }

        const userProductsMatch = path.match(/^\/registryUserProducts\/user\/[^/]+$/);
        if (userProductsMatch && method === 'GET') {
            return json(userProducts);
        }

        if (path === '/registryUserProducts' && method === 'POST') {
            return registerProduct(body);
        }

        if (path === '/api/metrics/users/calculate' && method === 'POST') {
            return calculateMetrics();
        }

        return json({ message: `mock-api: rota não implementada — ${method} ${path}` }, 404);
    }

    function registerProduct(payload) {
        if (!payload || !payload.productId) {
            return json({ message: 'mock-api: productId ausente.' }, 400);
        }

        const product = products.find((candidate) => candidate.id === String(payload.productId));

        if (!product) {
            return json({ message: `mock-api: produto não encontrado — ${payload.productId}` }, 404);
        }

        userProducts.push({
            quantity: Number(payload.quantity) || 1,
            avgActiveHours: Number(payload.avgActiveHours) || 0,
            hoursStandby: payload.hoursStandby != null ? Number(payload.hoursStandby) : null,
            product,
        });

        return json({ status: 'registered' }, 201);
    }

    /** ResultDTO simulado — mesmos campos que o app lê do backend real. */
    function calculateMetrics() {
        if (userProducts.length === 0) {
            return json({ message: 'Nenhum registro para calcular.' }, 404);
        }

        let totalDailyKwh = 0;

        const productsList = userProducts.map((registry) => {
            const activeKwh = (registry.quantity * registry.product.avgPowerW * registry.avgActiveHours) / 1000;
            const standbyKwh =
                (registry.quantity * (registry.product.avgStandbyPowerW || 0) * (registry.hoursStandby || 0)) / 1000;

            totalDailyKwh += activeKwh + standbyKwh;

            return { ...registry };
        });

        const avgDailyKwh = totalDailyKwh / userProducts.length;

        return json({
            avgDailyKwh: round(avgDailyKwh, 3),
            avgUseInYear: round(avgDailyKwh * 365, 3),
            totalDailyKwh: round(totalDailyKwh, 3),
            totalAnnualKwh: round(totalDailyKwh * 365, 3),
            dailyCost: round(totalDailyKwh * TARIFF_BRL_PER_KWH, 2),
            annualCost: round(totalDailyKwh * 365 * TARIFF_BRL_PER_KWH, 2),
            productsList,
        });
    }

    function round(value, decimals) {
        const factor = 10 ** decimals;
        return Math.round(value * factor) / factor;
    }

    function json(body, status) {
        return new Response(JSON.stringify(body), {
            status: status || 200,
            headers: { 'Content-Type': 'application/json' },
        });
    }

    console.info('[mock-api] ativo — dados em memória, sem backend. ?api=real desliga.');
})(window);
