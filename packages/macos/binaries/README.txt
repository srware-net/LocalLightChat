Put prebuilt macOS executables (arm64, x86_64, or universal2) here before running ../build_app.sh.

Required:
  nginx-universal2
  php-fpm-universal2

Optional (missing defaults are skipped):
  ragd-universal2
  mcp_server-universal2
  llc-mcp-gateway-universal2

Alternatively edit NGINX_PATH, PHP_FPM_PATH, RAGD_PATH, MCP_SERVER_PATH,
and MCP_GATEWAY_PATH near the top of ../build_app.sh to use absolute paths.

Thin single-arch executables are accepted. Missing slices produce warnings.
Set APP_ARCH near the top of build_app.sh to arm64, x86_64, auto, or universal2.
No actual executables are bundled in this source package.
