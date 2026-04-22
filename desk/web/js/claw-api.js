// claw-api.js: claw-specific endpoints (provider config, whitelist,
// channel perms, cron, context files).  MCP and OAuth are handled by
// mcp-api.js (McpProxyAPI + OAuthAPI globals).
window.ClawAPI = {
  base: '/apps/claw/api',

  async get(path) {
    var res = await fetch(this.base + path, { credentials: 'include' });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    return res.json();
  },

  async post(body) {
    var res = await fetch(this.base + '/action', {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    return res.json();
  },

  getConfig:  function() { return this.get('/config'); },
  getContext: function() { return this.get('/context'); },
  getChannelPerms: function() { return this.get('/channel-perms'); },
  getCronJobs:     function() { return this.get('/cron-jobs'); },

  setKey:       function(k) { return this.post({ action: 'set-key', key: k }); },
  setModel:     function(m) { return this.post({ action: 'set-model', model: m }); },
  setBraveKey:  function(k) { return this.post({ action: 'set-brave-key', key: k }); },

  setDefaultProvider:  function(p) { return this.post({ action: 'set-default-provider', provider: p }); },
  setLocalLlmUrl:      function(u) { return this.post({ action: 'set-local-llm-url', url: u }); },
  setMaxResponse:      function(n) { return this.post({ action: 'set-max-response-tokens', tokens: n }); },
  setMaxContext:       function(n) { return this.post({ action: 'set-max-context-tokens', tokens: n }); },
  setConvProvider:     function(k, p) { return this.post({ action: 'set-conv-provider', 'conv-key': k, provider: p }); },
  clearConvProvider:   function(k) { return this.post({ action: 'clear-conv-provider', 'conv-key': k }); },

  addShip:    function(ship, role) { return this.post({ action: 'add-ship', ship: ship, role: role }); },
  delShip:    function(ship) { return this.post({ action: 'del-ship', ship: ship }); },

  setChannelPerm: function(nest, perm) { return this.post({ action: 'set-channel-perm', channel: nest, perm: perm }); },

  addCron:    function(schedule, prompt) { return this.post({ action: 'cron-add', schedule: schedule, prompt: prompt }); },
  removeCron: function(id) { return this.post({ action: 'cron-remove', 'cron-id': id }); },

  setContext: function(field, content) { return this.post({ action: 'set-context', field: field, content: content }); },
  delContext: function(field) { return this.post({ action: 'del-context', field: field }); }
};
