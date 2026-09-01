const state = {
    userId: localStorage.getItem('amparesUserId') || '',
    products: [],
    lastProductId: '',
};

const loginSection = document.getElementById('login-section');
const registrySection = document.getElementById('registry-section');
const loginForm = document.getElementById('login-form');
const registryForm = document.getElementById('registry-form');
const productSelect = document.getElementById('product-select');
const manualProductIdInput = document.getElementById('manual-product-id');
const currentUserId = document.getElementById('current-user-id');
const loginMessage = document.getElementById('login-message');
const registryMessage = document.getElementById('registry-message');
const results = document.getElementById('results');
const calculateButton = document.getElementById('calculate-button');
const logoutButton = document.getElementById('logout-button');

loginForm.addEventListener('submit', handleLogin);
registryForm.addEventListener('submit', handleRegistrySubmit);
calculateButton.addEventListener('click', calculateResults);
logoutButton.addEventListener('click', clearSession);

if (state.userId) {
    showRegistryScreen();
    loadProducts();
}

async function handleLogin(event) {
    event.preventDefault();
    setMessage(loginMessage, 'Entrando...', '');

    const formData = new FormData(loginForm);
    const userId = String(formData.get('userId')).trim();

    try {
        await request('/auth/login', {
            method: 'POST',
            body: { id: userId },
        });

        state.userId = userId;
        localStorage.setItem('amparesUserId', userId);
        setMessage(loginMessage, '', '');
        showRegistryScreen();
        await loadProducts();
    } catch (error) {
        setMessage(loginMessage, `Falha no login: ${error.message}`, 'error');
    }
}

async function loadProducts() {
    replaceOptions(productSelect, [{ value: '', text: 'Carregando produtos...' }]);

    try {
        const data = await request('/products?size=1000', { method: 'GET' });
        state.products = normalizeProducts(data);
        renderProducts();
    } catch (error) {
        state.products = [];
        replaceOptions(productSelect, [{ value: '', text: 'Não foi possível carregar' }]);
        setMessage(
            registryMessage,
            `Não consegui carregar /products. Se souber o UUID, informe manualmente. Detalhe: ${error.message}`,
            'error'
        );
    }
}

function renderProducts() {
    if (state.products.length === 0) {
        replaceOptions(productSelect, [{ value: '', text: 'Nenhum produto encontrado' }]);
        return;
    }

    replaceOptions(productSelect, [
        { value: '', text: 'Selecione um produto' },
        ...state.products.map((product) => ({
            value: product.id,
            text: formatProduct(product),
        })),
    ]);
}

async function handleRegistrySubmit(event) {
    event.preventDefault();
    setMessage(registryMessage, 'Registrando produto...', '');

    const formData = new FormData(registryForm);
    const productId = getSelectedProductId(formData);

    if (!productId) {
        setMessage(registryMessage, 'Selecione um produto ou informe o UUID manualmente.', 'error');
        return;
    }

    const payload = {
        user: absoluteUrl(`/users/${state.userId}`),
        product: absoluteUrl(`/products/${productId}`),
        quantity: numberFromForm(formData, 'quantity'),
        avgActiveHours: numberFromForm(formData, 'avgActiveHours'),
    };
    const hoursStandby = optionalNumberFromForm(formData, 'hoursStandby');

    if (hoursStandby !== null) {
        payload.hoursStandby = hoursStandby;
    }

    try {
        await request('/registryUserProducts', {
            method: 'POST',
            body: payload,
        });

        state.lastProductId = productId;
        manualProductIdInput.value = '';
        setMessage(registryMessage, 'Produto registrado. Calculando resultado...', 'success');
        await calculateResults();
    } catch (error) {
        setMessage(registryMessage, `Falha ao registrar produto: ${error.message}`, 'error');
    }
}

async function calculateResults() {
    if (!state.userId) {
        return;
    }

    showTextResult('Calculando...');

    const selectedProductId = state.lastProductId || productSelect.value || manualProductIdInput.value.trim();
    const calls = [
        ['Consumo total anual', postMetric('/api/metrics/users/total-energy')],
        ['Consumo médio anual', postMetric('/api/metrics/users/average-energy')],
        ['Produto de maior consumo', postMetric('/api/metrics/users/most-consumer-product')],
        ['Média anual em standby', postMetric('/api/metrics/users/standby-consumption-avg')],
    ];

    if (selectedProductId) {
        calls.push([
            'Standby anual do produto selecionado',
            request('/api/metrics/users/standby-consumption-by-product', {
                method: 'POST',
                body: {
                    userId: Number(state.userId),
                    productId: selectedProductId,
                },
            }),
        ]);
    }

    const settled = await Promise.allSettled(calls.map(([, promise]) => promise));
    const list = document.createElement('ul');

    calls.forEach(([label], index) => {
        list.appendChild(metricListItem(label, settled[index]));
    });

    results.replaceChildren(list);
}

function postMetric(path) {
    return request(path, {
        method: 'POST',
        body: { userId: Number(state.userId) },
    });
}

async function request(path, options = {}) {
    const init = {
        method: options.method || 'GET',
        credentials: 'include',
        headers: {
            Accept: 'application/json',
            ...(options.body ? { 'Content-Type': 'application/json' } : {}),
        },
    };

    if (options.body) {
        init.body = JSON.stringify(options.body);
    }

    const response = await fetch(path, init);
    const contentType = response.headers.get('content-type') || '';
    const hasJson = contentType.includes('application/json') || contentType.includes('application/hal+json');
    const data = hasJson ? await response.json() : await response.text();

    if (!response.ok) {
        const message = typeof data === 'string' && data.trim()
            ? data.trim()
            : `${response.status} ${response.statusText}`;
        throw new Error(message);
    }

    return data;
}

function normalizeProducts(data) {
    const products = data?._embedded?.products || data?.content || (Array.isArray(data) ? data : []);

    return products
        .map((product) => ({
            ...product,
            id: product.id || extractIdFromSelfLink(product),
        }))
        .filter((product) => product.id);
}

function extractIdFromSelfLink(resource) {
    const href = resource?._links?.self?.href;

    if (!href) {
        return '';
    }

    return href.substring(href.lastIndexOf('/') + 1);
}

function formatProduct(product) {
    const parts = [product.name, product.brand, product.model].filter(Boolean).join(' - ');
    const power = product.avgPowerW ? ` (${product.avgPowerW} W)` : '';

    return `${parts || product.id}${power}`;
}

function metricListItem(label, settled) {
    const item = document.createElement('li');
    const strong = document.createElement('strong');
    strong.textContent = `${label}: `;
    item.appendChild(strong);

    if (settled.status === 'rejected') {
        item.append(`erro (${settled.reason.message})`);
        return item;
    }

    const value = settled.value;

    if (value && typeof value === 'object') {
        item.append(formatProduct(value));
        return item;
    }

    item.append(`${value} kWh`);
    return item;
}

function replaceOptions(select, options) {
    select.replaceChildren(
        ...options.map((optionData) => {
            const option = document.createElement('option');
            option.value = optionData.value;
            option.textContent = optionData.text;
            return option;
        })
    );
}

function getSelectedProductId(formData) {
    return String(formData.get('manualProductId')).trim() || String(formData.get('productId')).trim();
}

function numberFromForm(formData, field) {
    return Number(String(formData.get(field)).replace(',', '.'));
}

function optionalNumberFromForm(formData, field) {
    const value = String(formData.get(field)).trim();

    if (!value) {
        return null;
    }

    return Number(value.replace(',', '.'));
}

function absoluteUrl(path) {
    return `${window.location.origin}${path}`;
}

function showRegistryScreen() {
    currentUserId.textContent = state.userId;
    loginSection.hidden = true;
    registrySection.hidden = false;
}

async function clearSession() {
    setMessage(registryMessage, 'Limpando sessão...', '');

    try {
        await request('/auth/logout', { method: 'POST' });
        resetSessionState();
        setMessage(loginMessage, 'Sessão limpa. Faça login novamente.', 'success');
    } catch (error) {
        setMessage(registryMessage, `Falha ao limpar sessão: ${error.message}`, 'error');
    }
}

function resetSessionState() {
    state.userId = '';
    state.products = [];
    state.lastProductId = '';
    localStorage.removeItem('amparesUserId');
    loginSection.hidden = false;
    registrySection.hidden = true;
    showTextResult('Nenhum resultado calculado ainda.');
}

function showTextResult(text) {
    const paragraph = document.createElement('p');
    paragraph.textContent = text;
    results.replaceChildren(paragraph);
}

function setMessage(element, text, type) {
    element.textContent = text;
    element.className = `message ${type || ''}`.trim();
}
