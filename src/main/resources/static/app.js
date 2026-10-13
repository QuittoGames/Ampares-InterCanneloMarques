const state = {
    userId: localStorage.getItem('amparesUserId') || '',
    products: [],
    userProducts: [],
    lastProductId: '',
};

/** Formatação monetária BRL (R$) — usada nos custos do ResultDTO. */
const brlFormatter = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });

const loginSection = document.getElementById('login-section');
const registrySection = document.getElementById('registry-section');
const loginForm = document.getElementById('login-form');
const registryForm = document.getElementById('registry-form');
const productSelect = document.getElementById('product-select');
const userProducts = document.getElementById('user-products');
const manualProductIdInput = document.getElementById('manual-product-id');
const currentUserId = document.getElementById('current-user-id');
const loginMessage = document.getElementById('login-message');
const registryMessage = document.getElementById('registry-message');
const results = document.getElementById('results');
const calculateButton = document.getElementById('calculate-button');
const logoutButton = document.getElementById('logout-button');
const userIdInput = document.getElementById('user-id');
const idRow = document.getElementById('user-id-row');
const authIdToggle = document.getElementById('auth-id-toggle');

loginForm.addEventListener('submit', handleLogin);
registryForm.addEventListener('submit', handleRegistrySubmit);
calculateButton.addEventListener('click', calculateResults);
logoutButton.addEventListener('click', clearSession);
authIdToggle.addEventListener('click', () => setIdRowVisible(idRow.hidden));
document.addEventListener('keydown', handleAuthKeydown);

if (state.userId) {
    // Sessão salva: revalida no backend ANTES de entrar. O POST /auth/login
    // também CRIA o usuário quando ainda não existe (ids de sessões antigas),
    // garantindo cookie e usuário no banco. Falhou → volta para o login.
    request('/auth/login', {
        method: 'POST',
        body: { id: state.userId },
    })
        .then(() => {
            showRegistryScreen();
            return loadProducts();
        })
        .catch(() => {
            resetSessionState();
            setMessage(loginMessage, 'Sessão expirada. Toque em Começar agora.', 'error');
        });
}

async function handleLogin(event) {
    event.preventDefault();

    const formData = new FormData(loginForm);
    const typedUserId = String(formData.get('userId') ?? '').trim();
    let userId = typedUserId;

    if (!idRow.hidden) {
        // Área manual revelada: exige um ID digitado — não submete vazio.
        if (!userId) {
            setMessage(loginMessage, 'Digite seu ID ou feche a área manual tocando na logo.', 'error');
            return;
        }
    } else {
        // Fluxo de feira (1 toque): input oculto → gera ID aleatório e loga.
        userId = String(generateRandomUserId());
        userIdInput.value = userId;
        console.log(`ID aleatório gerado: ${userId}`);
    }

    setMessage(loginMessage, 'Entrando...', '');

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

/** Revela/oculta a linha do input manual de ID e sincroniza o aria-expanded. */
function setIdRowVisible(visible) {
    idRow.hidden = !visible;
    authIdToggle.setAttribute('aria-expanded', String(visible));

    if (visible) {
        userIdInput.focus();
    } else {
        authIdToggle.focus();
    }
}

/** Esc com a área manual visível a oculta (de qualquer ponto do login) e devolve foco à logo. */
function handleAuthKeydown(event) {
    if (event.key === 'Escape' && !loginSection.hidden && !idRow.hidden) {
        event.preventDefault();
        setIdRowVisible(false);
    }
}

/** Inteiro positivo aleatório seguro (crypto.getRandomValues). */
function generateRandomUserId() {
    const MIN = 1000000;
    const MAX = 9999999;
    const range = MAX - MIN + 1;
    const [value] = crypto.getRandomValues(new Uint32Array(1));
    return MIN + (value % range);
}

async function loadProducts() {
    replaceOptions(productSelect, [{ value: '', text: 'Carregando produtos...' }]);
    showUserProductsMessage('Carregando seus produtos...');

    try {
        const globalProducts = await request('/products?size=1000', { method: 'GET' });
        state.products = normalizeProducts(globalProducts);
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

    await loadUserProducts();
}

async function loadUserProducts() {
    try {
        const data = await request(`/registryUserProducts/user/${encodeURIComponent(state.userId)}`, {
            method: 'GET',
        });
        state.userProducts = Array.isArray(data) ? data : [];
        renderUserProducts();
    } catch (error) {
        state.userProducts = [];
        showUserProductsMessage('Você ainda não possui produtos registrados.');
    }
}

/** Renderiza o <select> de produtos. Sem argumento, mostra a lista completa carregada. */
function renderProducts(products = state.products) {
    if (products.length === 0) {
        replaceOptions(productSelect, [{ value: '', text: 'Nenhum produto encontrado' }]);
        return;
    }

    replaceOptions(productSelect, [
        { value: '', text: 'Selecione um produto' },
        ...products.map((product) => ({
            value: product.id,
            text: formatProduct(product),
        })),
    ]);
}

function renderUserProducts() {
    if (state.userProducts.length === 0) {
        showUserProductsMessage('Você ainda não possui produtos registrados.');
        return;
    }

    const list = document.createElement('ul');
    list.className = 'results__list';

    state.userProducts.forEach((registry) => {
        const item = document.createElement('li');
        item.className = 'results__item';
        item.textContent = formatRegistryDetails(registry);
        list.appendChild(item);
    });

    userProducts.replaceChildren(list);
}

/** Detalhes de um registro de produto no mesmo formato da lista "Produtos em uso". */
function formatRegistryDetails(registry) {
    const product = registry.product || {};

    return [
        formatProduct(product),
        `Quantidade: ${registry.quantity ?? 0}`,
        registry.avgActiveHours !== null && registry.avgActiveHours !== undefined
            ? `Ativo: ${registry.avgActiveHours} h/dia`
            : '',
        registry.hoursStandby !== null && registry.hoursStandby !== undefined
            ? `Standby: ${registry.hoursStandby} h/dia`
            : '',
    ].filter(Boolean).join(' · ');
}

function showUserProductsMessage(text) {
    const paragraph = document.createElement('p');
    paragraph.className = 'results__empty';
    paragraph.textContent = text;
    userProducts.replaceChildren(paragraph);
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
        userId: Number(state.userId),
        productId: productId,
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
        await loadUserProducts();
        setMessage(registryMessage, 'Produto registrado. Calculando resultado...', 'success');
        await calculateResults();
    } catch (error) {
        setMessage(registryMessage, `Falha ao registrar produto: ${error.message}`, 'error');
    }
}

/**
 * Calcula o resultado com UMA chamada ao endpoint geral
 * POST /api/metrics/users/calculate (ResultDTO).
 *
 * Unidades reais (ConsumeMetricsService#calculate): avgDailyKwh = média de
 * consumo diário por associação válida (kWh/dia); avgUseInYear = média de consumo
 * anual em kWh/ano; totalDailyKwh/totalAnnualKwh = totais do usuário em
 * kWh/dia e kWh/ano; dailyCost/annualCost = gasto em R$/dia e R$/ano
 * (custo = kWh × tarifa, arredondado no backend com 2 casas HALF_UP).
 */
async function calculateResults() {
    if (!state.userId) {
        return;
    }

    showTextResult('Calculando...');

    try {
        const result = await request('/api/metrics/users/calculate', {
            method: 'POST',
            body: { userId: Number(state.userId) },
        });
        renderCalculationResult(result);
    } catch (error) {
        if (error.status === 404) {
            showTextResult('Nenhum consumo calculado — registre um produto.');
        } else {
            showTextResult(`Falha ao calcular: ${error.message}`);
        }
    }
}

function renderCalculationResult(result) {
    const list = document.createElement('ul');
    list.className = 'results__list';

    list.appendChild(metricRow('Consumo médio diário', `${result.avgDailyKwh} kWh/dia`));
    list.appendChild(metricRow('Consumo médio anual', `${result.avgUseInYear} kWh/ano`));

    if (result.dailyCost != null && result.annualCost != null) {
        list.appendChild(metricRow('Gasto por dia', brlFormatter.format(result.dailyCost)));
        list.appendChild(metricRow('Gasto por ano', brlFormatter.format(result.annualCost)));
    }

    (result.productsList || []).forEach((registry) => {
        list.appendChild(metricRow('Produto', formatRegistryDetails(registry)));
    });

    results.replaceChildren(list);
}

function metricRow(label, value) {
    const item = document.createElement('li');
    item.className = 'results__item';

    const labelEl = document.createElement('span');
    labelEl.className = 'results__label';
    labelEl.textContent = label;

    const valueEl = document.createElement('span');
    valueEl.className = 'results__value results__value--accent';
    valueEl.textContent = value;

    item.append(labelEl, valueEl);
    return item;
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
        // Erros Spring vêm como JSON { timestamp, status, error, message, path }.
        // Prefere a mensagem real do backend em vez do genérico "500 ...".
        const message = (typeof data === 'object' && data?.message)
            || (typeof data === 'string' && data.trim() ? data.trim() : null)
            || `${response.status} ${response.statusText}`;
        const error = new Error(message);
        error.status = response.status;
        throw error;
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
    state.userProducts = [];
    state.lastProductId = '';
    localStorage.removeItem('amparesUserId');
    loginSection.hidden = false;
    registrySection.hidden = true;
    showTextResult('Nenhum resultado calculado ainda.');
}

function showTextResult(text) {
    const paragraph = document.createElement('p');
    paragraph.className = 'results__empty';
    paragraph.textContent = text;
    results.replaceChildren(paragraph);
}

function setMessage(element, text, type) {
    element.textContent = text;
    const base = element.id === 'login-message' ? 'auth__message' : 'message';
    element.className = type ? `${base} ${base}--${type}` : base;
}
