// PM2 Ecosystem - MCP Servers & Infrastructure
// Restart all: pm2 start ecosystem.config.js
// Port map:
//   18082  better-ccflare-rs  (Anthropic API proxy)
//    4801  pal-mcp            (PAL oracle, SSE)
//    4802  google-workspace   (streamable-http)
//    4803  slack-mcp          (supergateway-rs)
//    4804  sentry-mcp         (supergateway-rs)
//    4805  hubspot-mcp        (supergateway-rs)
//    4806  zendesk-mcp        (supergateway-rs)
//    4807  apify-mcp          (supergateway-rs)
//    4808  atlassian-mcp      (supergateway-rs)
//    8765  mcp-agent-mail     (agent coordination)

const SUPERGATEWAY = "/c/work/supergateway-rs/target/release/supergateway-rs";
const LOG_DIR = "/c/users/oystein/.config/pm2/logs";

function supergatewayApp(name, stdioBin, port) {
  return {
    name,
    script: SUPERGATEWAY,
    args: `--stdio ${stdioBin} --outputTransport streamableHttp --stateful --sessionTimeout 300000 --port ${port}`,
    interpreter: "none",
    autorestart: true,
    max_restarts: 10,
    min_uptime: "10s",
    restart_delay: 5000,
    max_memory_restart: "32M",
    error_file: `${LOG_DIR}/${name}-error.log`,
    out_file: `${LOG_DIR}/${name}-out.log`,
    merge_logs: true,
  };
}

module.exports = {
  apps: [
    // ── Anthropic API Proxy ─────────────────────────────────────
    {
      name: "better-ccflare-rs",
      cwd: "/c/WORK/better-ccflare/better-ccflare-rs",
      script: "target/release/better-ccflare",
      args: "--serve --port 4810",
      interpreter: "none",
      autorestart: true,
      max_restarts: 10,
      min_uptime: "10s",
      restart_delay: 5000,
      max_memory_restart: "512M",
      error_file: `${LOG_DIR}/better-ccflare-rs-error.log`,
      out_file: `${LOG_DIR}/better-ccflare-rs-out.log`,
      merge_logs: true,
    },

    // ── PAL MCP (SSE transport) ─────────────────────────────────
    {
      name: "pal-mcp",
      cwd: "/c/WORK/pal-mcp-server",
      script: "server.py",
      interpreter: "/c/WORK/pal-mcp-server/.pal_venv/bin/python",
      env: { MCP_TRANSPORT: "sse", MCP_PORT: "4801" },
      autorestart: true,
      max_restarts: 10,
      min_uptime: "10s",
      restart_delay: 5000,
      max_memory_restart: "1G",
      error_file: `${LOG_DIR}/pal-mcp-error.log`,
      out_file: `${LOG_DIR}/pal-mcp-out.log`,
      merge_logs: true,
    },

    // ── Google Workspace MCP (native streamable-http) ───────────
    {
      name: "google-workspace-mcp",
      script: "/c/users/oystein/.local/bin/uvx",
      args: "workspace-mcp --transport streamable-http --single-user",
      interpreter: "none",
      env: {
        WORKSPACE_MCP_PORT: "4802",
        DISPLAY: ":0",
        OAUTHLIB_INSECURE_TRANSPORT: "1",
        GOOGLE_OAUTH_CLIENT_ID: process.env.GOOGLE_OAUTH_CLIENT_ID,
        GOOGLE_OAUTH_CLIENT_SECRET: process.env.GOOGLE_OAUTH_CLIENT_SECRET,
      },
      autorestart: true,
      max_restarts: 10,
      min_uptime: "10s",
      restart_delay: 5000,
      max_memory_restart: "512M",
      error_file: `${LOG_DIR}/google-workspace-error.log`,
      out_file: `${LOG_DIR}/google-workspace-out.log`,
      merge_logs: true,
    },

    // ── supergateway-rs MCP servers ─────────────────────────────
    supergatewayApp("slack-mcp",     "/c/users/oystein/bin/slack-mcp",   4803),
    supergatewayApp("sentry-mcp",    "/c/users/oystein/bin/sentry-mcp",  4804),
    supergatewayApp("hubspot-mcp",   "/c/users/oystein/bin/hubspot-mcp", 4805),
    supergatewayApp("zendesk-mcp",   "/c/users/oystein/bin/zendesk-mcp", 4806),
    supergatewayApp("apify-mcp",     "/c/users/oystein/bin/apify-mcp",   4807),
    supergatewayApp("atlassian-mcp", "npx -y mcp-remote https://mcp.atlassian.com/v1/mcp", 4808),

    // ── MCP Agent Mail (agent coordination) ─────────────────────
    {
      name: "mcp-agent-mail",
      cwd: "/c/users/oystein/mcp_agent_mail",
      script: "scripts/run_server_with_token.sh",
      args: "--port 8765",
      interpreter: "bash",
      env: {
        HTTP_BEARER_TOKEN: "459f9002c2f4ca0b206a9579e0d40e8d6124f3ab162c52f73251d4e42a015dfc",
      },
      autorestart: true,
      max_restarts: 10,
      min_uptime: "10s",
      restart_delay: 5000,
      max_memory_restart: "512M",
      error_file: `${LOG_DIR}/mcp-agent-mail-error.log`,
      out_file: `${LOG_DIR}/mcp-agent-mail-out.log`,
      merge_logs: true,
    },
  ],
};
