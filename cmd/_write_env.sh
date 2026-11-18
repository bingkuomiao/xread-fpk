#!/bin/bash
# 被 install_callback / config_callback / upgrade_callback 引用。
# 把向导值落盘到 TRIM_PKGETC/xread.env，供 cmd/main 每次启动时读取。
# 值一律做白名单过滤，避免 source 时发生命令注入。

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
PKGETC="${TRIM_PKGETC:-/var/apps/xread/etc}"
ENV_FILE="${PKGETC}/xread.env"
mkdir -p "$PKGETC"

clean() { printf '%s' "$1" | tr -cd 'A-Za-z0-9_.:/=+\-'; }
bool()  { case "$1" in true|false) printf '%s' "$1";; *) printf '%s' "$2";; esac; }
num()   { case "$1" in ''|*[!0-9]*) printf '%s' "$2";; *) printf '%s' "$1";; esac; }
level() { case "$1" in info|debug|warn|error|trace) printf '%s' "$1";; *) printf '%s' info;; esac; }
# 批量缓存并发数限制在 1-32，非法值回退 4
concurrency() {
    local v
    v=$(num "$1" 4)
    if [ "$v" -lt 1 ] || [ "$v" -gt 32 ] 2>/dev/null; then v=4; fi
    printf '%s' "$v"
}
# 书源测试单请求超时（秒）限制在 1-120，非法值回退 120
test_source_timeout() {
    local v
    v=$(num "$1" 120)
    if [ "$v" -lt 1 ] || [ "$v" -gt 120 ] 2>/dev/null; then v=120; fi
    printf '%s' "$v"
}

LOG_LEVEL_V=$(clean "$(level "${wizard_log_level:-info}")")
SECURE_V=$(clean "$(bool "${wizard_secure:-true}" true)")
PUBLIC_READ_V=$(clean "$(bool "${wizard_public_read:-false}" false)")
INVITE_CODE_V=$(clean "${wizard_invite_code:-}")
USER_LIMIT_V=$(clean "$(num "${wizard_user_limit:-5}" 5)")
TIMEOUT_V=$(clean "$(num "${wizard_timeout:-30}" 30)")
CACHE_CONCURRENCY_V=$(concurrency "${wizard_cache_concurrency:-4}")
TEST_SOURCE_TIMEOUT_V=$(test_source_timeout "${wizard_test_source_timeout:-60}")

{
    echo "LOG_LEVEL=\"${LOG_LEVEL_V}\""
    echo "SECURE=\"${SECURE_V}\""
    echo "PUBLIC_READ=\"${PUBLIC_READ_V}\""
    echo "INVITE_CODE=\"${INVITE_CODE_V}\""
    echo "USER_LIMIT=\"${USER_LIMIT_V}\""
    echo "REQUEST_TIMEOUT_SECS=\"${TIMEOUT_V}\""
    echo "CACHE_CONCURRENCY=\"${CACHE_CONCURRENCY_V}\""
    echo "TEST_SOURCE_TIMEOUT_SECS=\"${TEST_SOURCE_TIMEOUT_V}\""
} > "$ENV_FILE"
