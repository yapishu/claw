// claw-ui.js: renders the Providers, Access, and Context sections.
// MCP (Endpoint / Upstreams) and OAuth are owned by mcp-ui.js.

(function () {
  'use strict';

  var state = {
    config: null,
    channels: [],
    cron: [],
    context: {},
    activeCtxField: null
  };

  // ---------------------------------------------------------------
  // helpers

  function $(id) { return document.getElementById(id); }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function toast(msg, kind) {
    var el = $('toast');
    if (!el) return;
    el.textContent = msg;
    el.className = 'toast is-visible' + (kind ? ' toast-' + kind : '');
    clearTimeout(toast._t);
    toast._t = setTimeout(function () { el.className = 'toast'; }, 2500);
  }

  // ---------------------------------------------------------------
  // providers tab

  function renderActiveProvider() {
    var c = state.config || {};
    var dp = c['default-provider'] || 'openrouter';
    var local = c['local-llm-url'] || 'http://localhost:8080';
    var overrides = Object.keys(c['conv-providers'] || {}).length;

    var strip = $('masthead-provider');
    if (strip) {
      strip.textContent = dp;
      strip.className = 'status-value status-provider ' + (dp === 'maroon' ? 'is-local' : 'is-remote');
    }
    var detail = $('masthead-provider-detail');
    if (detail) {
      detail.textContent = dp === 'maroon'
        ? 'local · ' + local
        : 'remote · openrouter';
      if (overrides > 0) detail.textContent += ' · ' + overrides + ' override' + (overrides === 1 ? '' : 's');
    }
  }

  function renderConvProviders() {
    var el = $('conv-providers-list');
    if (!el) return;
    var entries = Object.entries((state.config || {})['conv-providers'] || {});
    if (!entries.length) {
      el.innerHTML = '<div class="empty"><span class="empty-glyph">◇</span><span>No per-conversation overrides. All conversations use the default.</span></div>';
      return;
    }
    el.innerHTML = entries.map(function (kv) {
      var k = kv[0], p = kv[1];
      return (
        '<div class="kv-row">' +
          '<code class="kv-key">' + esc(k) + '</code>' +
          '<span class="kv-arrow">→</span>' +
          '<span class="badge ' + (p === 'maroon' ? 'enabled' : 'openapi') + '">' + esc(p) + '</span>' +
          '<button type="button" class="row-btn danger" data-conv-key="' + esc(k) + '">×</button>' +
        '</div>'
      );
    }).join('');
    el.querySelectorAll('[data-conv-key]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        ClawAPI.clearConvProvider(btn.getAttribute('data-conv-key'))
          .then(function () { toast('override cleared'); return loadConfig(); });
      });
    });
  }

  function loadConfig() {
    return ClawAPI.getConfig().then(function (c) {
      state.config = c;
      // masthead
      var ship = $('stat-ship'); if (ship) ship.textContent = c.ship || '—';
      var foot = $('foot-ship'); if (foot) foot.textContent = c.ship || '—';
      var model = $('masthead-model'); if (model) model.textContent = c.model || '—';
      // form fields
      $('cfg-openrouter-key') && ($('cfg-openrouter-key').value = '');
      $('cfg-model').value = c.model || '';
      $('cfg-brave-key').value = '';
      $('cfg-default-provider').value = c['default-provider'] || 'openrouter';
      $('cfg-local-url').value = c['local-llm-url'] || '';
      $('cfg-max-response').value = (c['max-response-tokens'] == null ? 1024 : c['max-response-tokens']);
      $('cfg-max-context').value = (c['max-context-tokens'] == null ? 0 : c['max-context-tokens']);
      renderActiveProvider();
      renderConvProviders();
      renderWhitelist();
    });
  }

  function bindProvidersTab() {
    $('btn-set-openrouter').addEventListener('click', function () {
      var k = $('cfg-openrouter-key').value.trim();
      if (!k) return;
      ClawAPI.setKey(k).then(function () {
        $('cfg-openrouter-key').value = '';
        toast('openrouter key set');
      });
    });
    $('btn-set-model').addEventListener('click', function () {
      var m = $('cfg-model').value.trim();
      if (!m) return;
      ClawAPI.setModel(m).then(function () { toast('model: ' + m); loadConfig(); });
    });
    $('btn-set-brave').addEventListener('click', function () {
      var k = $('cfg-brave-key').value.trim();
      if (!k) return;
      ClawAPI.setBraveKey(k).then(function () {
        $('cfg-brave-key').value = '';
        toast('brave key set');
      });
    });
    $('cfg-default-provider').addEventListener('change', function () {
      ClawAPI.setDefaultProvider(this.value).then(function () { toast('default: ' + $('cfg-default-provider').value); loadConfig(); });
    });
    $('btn-set-local-url').addEventListener('click', function () {
      var u = $('cfg-local-url').value.trim();
      if (!u) return;
      ClawAPI.setLocalLlmUrl(u).then(function () { toast('local url set'); loadConfig(); });
    });
    $('btn-set-max-response').addEventListener('click', function () {
      var n = parseInt($('cfg-max-response').value, 10);
      if (!(n > 0)) return;
      ClawAPI.setMaxResponse(n).then(function () { toast('max reply: ' + n); });
    });
    $('btn-set-max-context').addEventListener('click', function () {
      var n = parseInt($('cfg-max-context').value, 10);
      if (!(n >= 0)) return;
      ClawAPI.setMaxContext(n).then(function () {
        toast(n === 0 ? 'max context: heuristic' : 'max context: ' + n);
      });
    });
    $('btn-add-conv-provider').addEventListener('click', function () {
      var k = $('new-conv-key').value.trim();
      var p = $('new-conv-provider').value;
      if (!k) return;
      ClawAPI.setConvProvider(k, p).then(function () {
        $('new-conv-key').value = '';
        toast('override added');
        loadConfig();
      });
    });
  }

  // ---------------------------------------------------------------
  // access tab (whitelist + channel perms)

  function renderWhitelist() {
    var el = $('whitelist-list');
    if (!el) return;
    var wl = (state.config || {}).whitelist || {};
    var entries = Object.entries(wl);
    if (!entries.length) {
      el.innerHTML = '<div class="empty"><span class="empty-glyph">◇</span><span>No ships whitelisted.</span></div>';
      return;
    }
    el.innerHTML = entries.map(function (kv) {
      var ship = kv[0], role = kv[1];
      return (
        '<div class="kv-row">' +
          '<code class="kv-key">' + esc(ship) + '</code>' +
          '<span class="badge ' + (role === 'owner' ? 'enabled' : 'openapi') + '">' + esc(role) + '</span>' +
          '<button type="button" class="row-btn danger" data-ship="' + esc(ship) + '">×</button>' +
        '</div>'
      );
    }).join('');
    el.querySelectorAll('[data-ship]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        ClawAPI.delShip(btn.getAttribute('data-ship'))
          .then(function () { toast('ship removed'); return loadConfig(); });
      });
    });
  }

  function renderChannels() {
    var el = $('channel-list');
    if (!el) return;
    var filter = ($('chan-filter').value || '').toLowerCase();
    var list = state.channels.filter(function (c) {
      return c.nest.toLowerCase().indexOf(filter) >= 0
          || (c.title || '').toLowerCase().indexOf(filter) >= 0
          || (c.gtitle || '').toLowerCase().indexOf(filter) >= 0;
    });
    if (!list.length) {
      el.innerHTML = '<div class="empty"><span class="empty-glyph">◇</span><span>No channels' + (filter ? ' matching filter.' : '.') + '</span></div>';
      return;
    }
    el.innerHTML = list.map(function (c) {
      var open = c.perm === 'open';
      return (
        '<div class="kv-row">' +
          '<div class="kv-title-wrap">' +
            '<div class="kv-title">' + esc(c.title || c.nest) + (c.gtitle ? ' <span class="kv-sub">in ' + esc(c.gtitle) + '</span>' : '') + '</div>' +
            '<code class="kv-sub kv-mono">' + esc(c.nest) + '</code>' +
          '</div>' +
          '<button type="button" class="badge ' + (open ? 'enabled' : 'disabled') + '" data-chan="' + esc(c.nest) + '" data-next="' + (open ? 'whitelist' : 'open') + '">' + (open ? 'open' : 'whitelist') + '</button>' +
        '</div>'
      );
    }).join('');
    el.querySelectorAll('[data-chan]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var nest = btn.getAttribute('data-chan');
        var next = btn.getAttribute('data-next');
        ClawAPI.setChannelPerm(nest, next).then(function () {
          var ch = state.channels.find(function (x) { return x.nest === nest; });
          if (ch) ch.perm = next;
          toast(nest.split('/').pop() + ' → ' + next);
          renderChannels();
        });
      });
    });
  }

  function loadChannels() {
    return ClawAPI.getChannelPerms().then(function (perms) {
      state.channels = Object.entries(perms || {}).map(function (kv) {
        return { nest: kv[0], title: kv[0], gtitle: '', perm: kv[1] };
      });
      return fetch('/~/scry/groups/groups/light.json', { credentials: 'include' })
        .then(function (r) { return r.ok ? r.json() : {}; })
        .catch(function () { return {}; });
    }).then(function (groups) {
      var seen = new Set(state.channels.map(function (c) { return c.nest; }));
      Object.entries(groups || {}).forEach(function (kv) {
        var flag = kv[0], group = kv[1];
        var gtitle = (group && group.meta && group.meta.title) || flag;
        var chans = (group && group.channels) || {};
        Object.entries(chans).forEach(function (cv) {
          var nest = cv[0], ch = cv[1];
          if (nest.indexOf('chat/') !== 0) return;
          var title = (ch && ch.meta && ch.meta.title) || nest;
          if (seen.has(nest)) {
            var existing = state.channels.find(function (x) { return x.nest === nest; });
            if (existing) { existing.title = title; existing.gtitle = gtitle; }
          } else {
            state.channels.push({ nest: nest, title: title, gtitle: gtitle, perm: 'whitelist' });
          }
        });
      });
      renderChannels();
    });
  }

  function bindAccessTab() {
    $('btn-add-ship').addEventListener('click', function () {
      var s = $('new-ship').value.trim();
      var r = $('new-role').value;
      if (!s) return;
      ClawAPI.addShip(s, r).then(function () {
        $('new-ship').value = '';
        toast('ship added');
        loadConfig();
      });
    });
    $('chan-filter').addEventListener('input', renderChannels);
  }

  // ---------------------------------------------------------------
  // context tab (context files + cron)

  function renderContext() {
    var el = $('ctx-tabs');
    if (!el) return;
    var keys = Object.keys(state.context);
    if (!state.activeCtxField && keys.length) state.activeCtxField = keys[0];
    el.innerHTML = keys.map(function (k) {
      return '<button type="button" class="ctx-pill' + (k === state.activeCtxField ? ' is-active' : '') + '" data-field="' + esc(k) + '">' + esc(k) + '</button>';
    }).join('');
    el.querySelectorAll('[data-field]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        state.activeCtxField = btn.getAttribute('data-field');
        renderContext();
      });
    });
    var ed = $('ctx-editor');
    if (ed) ed.value = state.activeCtxField ? (state.context[state.activeCtxField] || '') : '';
  }

  function loadContext() {
    return ClawAPI.getContext().then(function (c) {
      state.context = c || {};
      renderContext();
    });
  }

  function renderCron() {
    var el = $('cron-list');
    if (!el) return;
    if (!state.cron.length) {
      el.innerHTML = '<div class="empty"><span class="empty-glyph">◇</span><span>No scheduled tasks.</span></div>';
      return;
    }
    el.innerHTML = state.cron.map(function (j) {
      return (
        '<div class="kv-row">' +
          '<div class="kv-title-wrap">' +
            '<code class="kv-sub kv-mono kv-saffron">' + esc(j.schedule || '?') + '</code>' +
            '<div class="kv-title">' + esc(j.prompt || '') + '</div>' +
          '</div>' +
          '<button type="button" class="row-btn danger" data-cron="' + esc(j.id) + '">×</button>' +
        '</div>'
      );
    }).join('');
    el.querySelectorAll('[data-cron]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var id = parseInt(btn.getAttribute('data-cron'), 10);
        ClawAPI.removeCron(id).then(function () { toast('task removed'); loadCron(); });
      });
    });
  }

  function loadCron() {
    return ClawAPI.getCronJobs().then(function (jobs) {
      state.cron = jobs || [];
      renderCron();
    });
  }

  function bindContextTab() {
    $('btn-save-ctx').addEventListener('click', function () {
      if (!state.activeCtxField) return;
      var content = $('ctx-editor').value;
      ClawAPI.setContext(state.activeCtxField, content).then(function () {
        state.context[state.activeCtxField] = content;
        toast(state.activeCtxField + ' saved');
      });
    });
    $('btn-delete-ctx').addEventListener('click', function () {
      if (!state.activeCtxField) return;
      ClawAPI.delContext(state.activeCtxField).then(function () {
        delete state.context[state.activeCtxField];
        state.activeCtxField = Object.keys(state.context)[0] || null;
        renderContext();
        toast('field deleted');
      });
    });
    $('btn-add-ctx').addEventListener('click', function () {
      var k = $('new-ctx-key').value.trim();
      if (!k) return;
      ClawAPI.setContext(k, '').then(function () {
        state.context[k] = '';
        state.activeCtxField = k;
        $('new-ctx-key').value = '';
        renderContext();
      });
    });
    $('btn-add-cron').addEventListener('click', function () {
      var s = $('cron-schedule').value.trim();
      var p = $('cron-prompt').value.trim();
      if (!s || !p) { toast('need schedule + prompt', 'err'); return; }
      if (s.split(/\s+/).length !== 5) { toast('need 5 fields: min hr dom mon dow', 'err'); return; }
      ClawAPI.addCron(s, p).then(function () {
        $('cron-schedule').value = '';
        $('cron-prompt').value = '';
        toast('task scheduled');
        loadCron();
      });
    });
  }

  // ---------------------------------------------------------------
  // init

  document.addEventListener('DOMContentLoaded', function () {
    bindProvidersTab();
    bindAccessTab();
    bindContextTab();
    loadConfig();
    loadChannels();
    loadCron();
    loadContext();
  });
})();
