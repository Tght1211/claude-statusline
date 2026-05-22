const $ = sel => document.querySelector(sel);
const $$ = sel => document.querySelectorAll(sel);

function formatCost(v) {
    const n = v || 0;
    if (n >= 10000) return '$' + (n / 1000).toFixed(1) + 'k';
    if (n >= 1000) return '$' + (n / 1000).toFixed(2) + 'k';
    return '$' + n.toFixed(2);
}

function formatTokens(v) {
    if (!v) return '0';
    if (v >= 1e9) return (v / 1e9).toFixed(2) + 'B';
    if (v >= 1e6) return (v / 1e6).toFixed(1) + 'M';
    if (v >= 1e3) return (v / 1e3).toFixed(0) + 'K';
    return String(v);
}

function shortModel(m) { return m.replace('claude-', '').replace(/-202\d+.*$/, ''); }
function shortPath(p) { if (!p) return '—'; return p.split('/').slice(-2).join('/'); }

function relativeTime(iso) {
    if (!iso) return '';
    const diff = Date.now() - new Date(iso).getTime();
    const mins = Math.floor(diff / 60000);
    if (mins < 1) return '刚刚';
    if (mins < 60) return mins + '分钟前';
    const hrs = Math.floor(mins / 60);
    if (hrs < 24) return hrs + '小时前';
    return Math.floor(hrs / 24) + '天前';
}

function costLevel(cost) {
    if (cost >= 10) return 'high';
    if (cost >= 3) return 'medium';
    return 'low';
}

function getFilters() {
    const from = $('#filter-from').value;
    const to = $('#filter-to').value;
    const p = new URLSearchParams();
    if (from) p.set('from', from);
    if (to) p.set('to', to);
    return p.toString() ? '?' + p : '';
}

async function api(path) { return (await fetch(path)).json(); }

// Tabs
$$('.tab').forEach(tab => {
    tab.addEventListener('click', () => {
        $$('.tab').forEach(t => t.classList.remove('active'));
        $$('.tab-content').forEach(t => t.classList.remove('active'));
        tab.classList.add('active');
        $(`#tab-${tab.dataset.tab}`).classList.add('active');
        loadTab(tab.dataset.tab);
    });
});

$('#btn-filter').addEventListener('click', () => loadTab(getActiveTab()));
$('#btn-reset').addEventListener('click', () => { $('#filter-from').value = ''; $('#filter-to').value = ''; loadTab(getActiveTab()); });
function getActiveTab() { return $('.tab.active').dataset.tab; }

// ===== View Toggle =====
$$('.view-toggle').forEach(toggle => {
    toggle.querySelectorAll('.toggle-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            toggle.querySelectorAll('.toggle-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            const section = toggle.closest('.overview-chart-section');
            section.querySelectorAll('.chart-view').forEach(v => v.classList.remove('active'));
            section.querySelector(`#view-${btn.dataset.view}`).classList.add('active');
        });
    });
});

// ===== Tooltip =====
let tooltip = null;
function initTooltip() {
    if (tooltip) return;
    tooltip = document.createElement('div');
    tooltip.className = 'heatmap-tooltip';
    document.body.appendChild(tooltip);
}

function showTooltip(e, text) {
    initTooltip();
    tooltip.textContent = text;
    tooltip.style.display = 'block';
    tooltip.style.left = e.clientX + 10 + 'px';
    tooltip.style.top = e.clientY - 30 + 'px';
}

function hideTooltip() { if (tooltip) tooltip.style.display = 'none'; }

// ===== Year Heatmap (365 days, token-based) =====
const MONTH_NAMES = ['1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月'];

function renderYearHeatmap(dailyData) {
    const el = document.getElementById('heatmap-year');
    const monthsEl = document.getElementById('heatmap-months');
    el.innerHTML = '';
    monthsEl.innerHTML = '';

    const valueMap = {};
    const costMap = {};
    dailyData.forEach(d => { valueMap[d.date] = d.tokens; costMap[d.date] = d.cost; });

    const days = [];
    const now = new Date();
    for (let i = 364; i >= 0; i--) {
        const d = new Date(now);
        d.setDate(d.getDate() - i);
        days.push(d.toISOString().slice(0, 10));
    }

    const values = days.map(d => valueMap[d] || 0).filter(v => v > 0);
    values.sort((a, b) => a - b);
    const q1 = values[Math.floor(values.length * 0.25)] || 1;
    const q2 = values[Math.floor(values.length * 0.5)] || 2;
    const q3 = values[Math.floor(values.length * 0.75)] || 3;

    function getLevel(v) {
        if (v <= 0) return 0;
        if (v <= q1) return 1;
        if (v <= q2) return 2;
        if (v <= q3) return 3;
        return 4;
    }

    const firstDate = new Date(days[0]);
    const startDow = (firstDate.getDay() + 6) % 7;

    const padded = [];
    for (let i = 0; i < startDow; i++) padded.push(null);
    days.forEach(d => padded.push(d));

    const weeks = [];
    for (let i = 0; i < padded.length; i += 7) {
        weeks.push(padded.slice(i, i + 7));
    }

    // Month labels
    let lastMonth = -1;
    const weekWidth = 100 / weeks.length;
    weeks.forEach((week, wi) => {
        const firstDay = week.find(d => d !== null);
        if (firstDay) {
            const m = parseInt(firstDay.slice(5, 7)) - 1;
            if (m !== lastMonth) {
                const span = document.createElement('span');
                span.textContent = MONTH_NAMES[m];
                span.style.position = 'absolute';
                span.style.left = (wi * weekWidth) + '%';
                monthsEl.appendChild(span);
                lastMonth = m;
            }
        }
    });

    // Render cells
    weeks.forEach(week => {
        const weekEl = document.createElement('div');
        weekEl.className = 'heatmap-week';
        for (let dow = 0; dow < 7; dow++) {
            const date = week[dow];
            const cell = document.createElement('div');
            cell.className = 'heatmap-cell';
            if (date) {
                const val = valueMap[date] || 0;
                const cost = costMap[date] || 0;
                cell.setAttribute('data-level', getLevel(val));
                cell.addEventListener('mouseenter', e => {
                    showTooltip(e, `${date}  ${formatTokens(val)} tokens · ${formatCost(cost)}`);
                });
                cell.addEventListener('mouseleave', hideTooltip);
            } else {
                cell.setAttribute('data-level', '0');
                cell.style.visibility = 'hidden';
            }
            weekEl.appendChild(cell);
        }
        el.appendChild(weekEl);
    });
}

// ===== Month Dual-Line Chart (interactive crosshair) =====
function renderMonthChart(dailyData) {
    const container = document.getElementById('month-chart');
    const today = new Date();
    const year = today.getFullYear();
    const month = today.getMonth();
    const daysInMonth = new Date(year, month + 1, 0).getDate();

    const valueMap = {};
    dailyData.forEach(d => { valueMap[d.date] = d; });

    const data = [];
    for (let i = 1; i <= daysInMonth; i++) {
        const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(i).padStart(2, '0')}`;
        const entry = valueMap[dateStr] || {};
        data.push({ date: dateStr, day: i, cost: entry.cost || 0, tokens: entry.tokens || 0 });
    }

    const maxCost = Math.max(...data.map(d => d.cost), 0.01);
    const maxTokens = Math.max(...data.map(d => d.tokens), 1);

    const W = container.clientWidth || 800;
    const H = 240;
    const padL = 55, padR = 55, padT = 24, padB = 32;
    const chartW = W - padL - padR;
    const chartH = H - padT - padB;

    const yMin = padT;
    const yMax = padT + chartH;
    function clampY(y) { return Math.max(yMin, Math.min(yMax, y)); }

    function smoothPath(pts) {
        if (pts.length < 2) return '';
        let path = `M ${pts[0].x} ${pts[0].y}`;
        for (let i = 0; i < pts.length - 1; i++) {
            const p0 = pts[Math.max(0, i - 1)];
            const p1 = pts[i];
            const p2 = pts[i + 1];
            const p3 = pts[Math.min(pts.length - 1, i + 2)];
            const cp1x = p1.x + (p2.x - p0.x) / 6;
            const cp1y = clampY(p1.y + (p2.y - p0.y) / 6);
            const cp2x = p2.x - (p3.x - p1.x) / 6;
            const cp2y = clampY(p2.y - (p3.y - p1.y) / 6);
            path += ` C ${cp1x} ${cp1y}, ${cp2x} ${cp2y}, ${p2.x} ${p2.y}`;
        }
        return path;
    }

    const costPts = data.map((d, i) => ({
        x: padL + (i / (daysInMonth - 1)) * chartW,
        y: padT + chartH - (d.cost / maxCost) * chartH
    }));

    const tokenPts = data.map((d, i) => ({
        x: padL + (i / (daysInMonth - 1)) * chartW,
        y: padT + chartH - (d.tokens / maxTokens) * chartH
    }));

    let svg = `<svg viewBox="0 0 ${W} ${H}" width="100%" height="100%" id="month-svg">`;

    // Grid
    for (let i = 0; i <= 4; i++) {
        const y = padT + (chartH / 4) * i;
        svg += `<line x1="${padL}" y1="${y}" x2="${W - padR}" y2="${y}" stroke="#f0f0f3" stroke-width="1"/>`;
        svg += `<text x="${padL - 8}" y="${y + 4}" fill="#9e9eab" font-size="10" text-anchor="end" font-family="-apple-system,sans-serif">${formatCost(maxCost * (1 - i / 4))}</text>`;
        svg += `<text x="${W - padR + 8}" y="${y + 4}" fill="#9e9eab" font-size="10" text-anchor="start" font-family="-apple-system,sans-serif">${formatTokens(maxTokens * (1 - i / 4))}</text>`;
    }

    // X labels
    for (let i = 0; i < daysInMonth; i += 5) {
        const x = padL + (i / (daysInMonth - 1)) * chartW;
        svg += `<text x="${x}" y="${H - 8}" fill="#9e9eab" font-size="10" text-anchor="middle" font-family="-apple-system,sans-serif">${data[i].day}日</text>`;
    }

    // Areas
    const costPath = smoothPath(costPts);
    const tokenPath = smoothPath(tokenPts);
    svg += `<path d="${costPath} L ${costPts[costPts.length-1].x} ${padT+chartH} L ${costPts[0].x} ${padT+chartH} Z" fill="#2563eb" opacity="0.06"/>`;
    svg += `<path d="${tokenPath} L ${tokenPts[tokenPts.length-1].x} ${padT+chartH} L ${tokenPts[0].x} ${padT+chartH} Z" fill="#10b981" opacity="0.06"/>`;

    // Lines
    svg += `<path d="${costPath}" fill="none" stroke="#2563eb" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>`;
    svg += `<path d="${tokenPath}" fill="none" stroke="#10b981" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>`;

    // Crosshair group (hidden by default)
    svg += `<g id="crosshair" style="display:none">`;
    svg += `<line id="cross-line" x1="0" y1="${padT}" x2="0" y2="${padT + chartH}" stroke="#d0d0d6" stroke-width="1" stroke-dasharray="3,3"/>`;
    svg += `<circle id="cross-dot-cost" r="4" fill="#2563eb" stroke="#fff" stroke-width="2"/>`;
    svg += `<circle id="cross-dot-token" r="4" fill="#10b981" stroke="#fff" stroke-width="2"/>`;
    svg += `</g>`;

    // Invisible overlay for mouse events
    svg += `<rect id="chart-overlay" x="${padL}" y="${padT}" width="${chartW}" height="${chartH}" fill="transparent" cursor="crosshair"/>`;

    svg += '</svg>';

    // Floating info panel
    const panelHtml = `<div id="chart-info-panel" class="chart-info-panel" style="display:none">
        <div class="chart-info-date" id="info-date"></div>
        <div class="chart-info-row"><span class="chart-info-dot" style="background:#2563eb"></span><span class="chart-info-label">花费</span><span class="chart-info-value" id="info-cost"></span></div>
        <div class="chart-info-row"><span class="chart-info-dot" style="background:#10b981"></span><span class="chart-info-label">Token</span><span class="chart-info-value" id="info-token"></span></div>
    </div>`;

    container.innerHTML = svg + panelHtml;

    // Interactive crosshair logic
    const svgEl = container.querySelector('#month-svg');
    const overlay = container.querySelector('#chart-overlay');
    const crosshair = container.querySelector('#crosshair');
    const crossLine = container.querySelector('#cross-line');
    const dotCost = container.querySelector('#cross-dot-cost');
    const dotToken = container.querySelector('#cross-dot-token');
    const panel = container.querySelector('#chart-info-panel');
    const infoDate = container.querySelector('#info-date');
    const infoCost = container.querySelector('#info-cost');
    const infoToken = container.querySelector('#info-token');

    function handleMove(e) {
        const rect = svgEl.getBoundingClientRect();
        const scaleX = W / rect.width;
        const mouseX = (e.clientX - rect.left) * scaleX;

        // Find nearest data index
        const idx = Math.round(((mouseX - padL) / chartW) * (daysInMonth - 1));
        const clampIdx = Math.max(0, Math.min(daysInMonth - 1, idx));
        const d = data[clampIdx];
        const cp = costPts[clampIdx];
        const tp = tokenPts[clampIdx];

        crosshair.style.display = '';
        crossLine.setAttribute('x1', cp.x);
        crossLine.setAttribute('x2', cp.x);
        dotCost.setAttribute('cx', cp.x);
        dotCost.setAttribute('cy', cp.y);
        dotToken.setAttribute('cx', tp.x);
        dotToken.setAttribute('cy', tp.y);

        infoDate.textContent = d.date;
        infoCost.textContent = formatCost(d.cost);
        infoToken.textContent = formatTokens(d.tokens);
        panel.style.display = '';

        // Position panel near cursor
        const containerRect = container.getBoundingClientRect();
        const panelX = e.clientX - containerRect.left + 16;
        const panelY = e.clientY - containerRect.top - 40;
        const panelW = panel.offsetWidth;
        // flip to left if near right edge
        if (panelX + panelW > containerRect.width - 10) {
            panel.style.left = (panelX - panelW - 32) + 'px';
        } else {
            panel.style.left = panelX + 'px';
        }
        panel.style.top = Math.max(0, panelY) + 'px';
    }

    function handleLeave() {
        crosshair.style.display = 'none';
        panel.style.display = 'none';
    }

    overlay.addEventListener('mousemove', handleMove);
    overlay.addEventListener('mouseleave', handleLeave);
}

// ===== Overview =====
async function loadOverview() {
    const data = await api('/api/overview');

    $('#cost-today').textContent = formatCost(data.today);
    $('#cost-week').textContent = formatCost(data.week);
    $('#cost-month').textContent = formatCost(data.month);
    $('#cost-total').textContent = formatCost(data.total);

    renderYearHeatmap(data.daily);
    renderMonthChart(data.daily);
}

// ===== Models =====
const MODEL_COLORS = ['#2563eb', '#10b981', '#f59e0b', '#ec4899', '#8b5cf6', '#06b6d4', '#ef4444'];

async function loadModels() {
    const data = await api('/api/usage/by-model' + getFilters());
    const container = $('#models-content');
    if (!data.length) { container.innerHTML = '<div class="empty-state">暂无数据</div>'; return; }

    const totalCost = data.reduce((s, r) => s + r.cost, 0);
    const maxCost = data[0].cost;

    let stackedBar = '<div class="model-stack">';
    data.forEach((r, i) => {
        const pct = (r.cost / totalCost * 100).toFixed(1);
        stackedBar += `<div class="model-stack-segment" style="width:${pct}%;background:${MODEL_COLORS[i % MODEL_COLORS.length]}" title="${shortModel(r.model)}: ${pct}%"></div>`;
    });
    stackedBar += '</div>';

    let rows = '';
    data.forEach((r, i) => {
        const pct = (r.cost / totalCost * 100).toFixed(1);
        const barWidth = (r.cost / maxCost * 100).toFixed(0);
        const color = MODEL_COLORS[i % MODEL_COLORS.length];
        rows += `
        <div class="model-row">
            <div class="model-rank" style="color:${color}">#${i + 1}</div>
            <div class="model-info">
                <div class="model-name">${shortModel(r.model)}</div>
                <div class="model-bar-track"><div class="model-bar-fill" style="width:${barWidth}%;background:${color}"></div></div>
            </div>
            <div class="model-stats">
                <div class="model-stat"><span class="model-stat-value">${formatCost(r.cost)}</span><span class="model-stat-label">${pct}%</span></div>
                <div class="model-stat"><span class="model-stat-value">${r.count.toLocaleString()}</span><span class="model-stat-label">请求</span></div>
                <div class="model-stat"><span class="model-stat-value">${formatTokens(r.tokens)}</span><span class="model-stat-label">tokens</span></div>
            </div>
        </div>`;
    });

    container.innerHTML = `
        <div class="model-total"><span class="model-total-label">总花费</span><span class="model-total-value">${formatCost(totalCost)}</span></div>
        ${stackedBar}
        <div class="model-list">${rows}</div>
    `;
}

// ===== Sessions =====
async function loadSessions() {
    const data = await api('/api/usage/by-session' + getFilters());
    const container = $('#sessions-content');
    if (!data.length) { container.innerHTML = '<div class="empty-state">暂无会话</div>'; return; }

    const groups = {};
    data.forEach(r => {
        const date = r.first_ts ? r.first_ts.slice(0, 10) : '未知';
        if (!groups[date]) groups[date] = [];
        groups[date].push(r);
    });

    let html = '';
    for (const [date, sessions] of Object.entries(groups)) {
        const dayCost = sessions.reduce((s, r) => s + r.cost, 0);
        html += `<div class="session-group"><div class="session-date-header"><span class="session-date">${date}</span><span class="session-date-cost">${formatCost(dayCost)}</span></div>`;
        sessions.forEach(r => {
            const level = costLevel(r.cost);
            html += `
            <div class="session-row">
                <div class="session-project"><span class="session-dot" data-level="${level}"></span><span class="session-name">${shortPath(r.cwd)}</span></div>
                <div class="session-meta">
                    <span class="session-time">${relativeTime(r.first_ts)}</span>
                    <span class="session-badge">${r.count} 请求</span>
                    <span class="session-cost" data-level="${level}">${formatCost(r.cost)}</span>
                    <span class="session-tokens">${formatTokens(r.tokens)}</span>
                </div>
            </div>`;
        });
        html += '</div>';
    }
    container.innerHTML = html;
}

// ===== Providers =====
async function loadProviders() {
    const data = await api('/api/providers');
    const container = $('#providers-content');
    if (!data.length) { container.innerHTML = '<div class="empty-state">暂无供应商</div>'; return; }

    container.innerHTML = data.map((p, i) => {
        const color = MODEL_COLORS[i % MODEL_COLORS.length];
        return `
        <div class="prov-card">
            <div class="prov-header">
                <div class="prov-icon" style="background:${color}">${(p.name || p.id).charAt(0).toUpperCase()}</div>
                <div class="prov-title"><h4>${p.name || p.id}</h4><span class="prov-version">v${p.version || '1.0.0'}</span></div>
                <div class="prov-status">${p.hasConfig ? '<span class="status-connected">已连接</span>' : '<span class="status-disconnected">未配置</span>'}</div>
            </div>
            <p class="prov-desc">${p.description || '暂无描述'}</p>
            <div class="prov-meta">
                <div class="prov-tags">${(p.match || []).map(m => `<span class="prov-tag">${m}</span>`).join('')}</div>
                <div class="prov-info"><span>缓存: ${p.cacheTtl || 120}s</span>${p.modelMap ? `<span>模型映射: ${Object.keys(p.modelMap).length}</span>` : ''}</div>
            </div>
            <div class="prov-actions">
                <button class="prov-btn-config" onclick="editProvider('${p.id}')">配置</button>
                <button class="prov-btn-remove" onclick="deleteProvider('${p.id}')">删除</button>
            </div>
        </div>`;
    }).join('');
}

window.editProvider = async id => {
    const data = await api(`/api/providers/${id}`);
    $('#modal-title').textContent = (data.manifest.name || id) + ' — 配置';
    $('#modal-config').value = JSON.stringify(data.config, null, 2);
    $('#provider-modal').classList.remove('hidden');
    $('#modal-save').onclick = async () => {
        try {
            await fetch(`/api/providers/${id}/config`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(JSON.parse($('#modal-config').value)) });
            $('#provider-modal').classList.add('hidden');
            loadProviders();
        } catch (e) { alert('JSON 格式错误: ' + e.message); }
    };
};

window.deleteProvider = async id => {
    if (!confirm(`确认删除供应商 "${id}"？`)) return;
    await fetch(`/api/providers/${id}?confirm=true`, { method: 'DELETE' });
    loadProviders();
};

$('#modal-cancel').addEventListener('click', () => $('#provider-modal').classList.add('hidden'));

$('#btn-add-provider').addEventListener('click', () => {
    const id = prompt('供应商 ID (小写字母-短横线):');
    if (!id) return;
    const name = prompt('显示名称:', id);
    const match = prompt('URL 匹配模式 (逗号分隔):', '');
    fetch('/api/providers', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id, name, match: match ? match.split(',').map(s => s.trim()) : [] }) }).then(() => loadProviders());
});

function loadTab(tab) {
    ({ overview: loadOverview, models: loadModels, sessions: loadSessions, providers: loadProviders })[tab]();
}

loadOverview();
