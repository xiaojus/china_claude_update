#!/bin/bash
# ==============================================================================
# Claude Code 国内直连升级客户端- macOS / Linux
# ==============================================================================

set -e

# === 【配置区】在这里填入你部署好的 Cloudflare Worker 地址 ===
API_URL="https://claude-api.lmin.site/"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}✨ 欢迎使用 Claude Code 国内直连升级助手 ✨${NC}"
echo -e "${BLUE}====================================================${NC}"

# 1. 环境嗅探
OS=$(uname -s)
ARCH=$(uname -m)

PLATFORM_OS=""
PLATFORM_ARCH=""

case "$OS" in
    Darwin)
        PLATFORM_OS="darwin"
        ;;
    Linux)
        PLATFORM_OS="linux"
        ;;
    *)
        echo -e "${RED}❌ 不支持的操作系统: $OS${NC}"
        exit 1
        ;;
esac

case "$ARCH" in
    x86_64|amd64)
        PLATFORM_ARCH="x64"
        ;;
    arm64|aarch64)
        PLATFORM_ARCH="arm64"
        ;;
    *)
        echo -e "${RED}❌ 不支持的架构: $ARCH${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}✓ 环境检测通过: ${PLATFORM_OS}-${PLATFORM_ARCH}${NC}"

# 2. 身份验证
echo ""
if [ -t 0 ]; then
    read -p "$(echo -e ${YELLOW}"🔑 请输入您的授权激活码 (CDK) 并按回车: "${NC})" CONFIRM_KEY
elif (true < /dev/tty) 2>/dev/null; then
    read -p "$(echo -e ${YELLOW}"🔑 请输入您的授权激活码 (CDK) 并按回车: "${NC})" CONFIRM_KEY < /dev/tty
else
    read -p "$(echo -e ${YELLOW}"🔑 请输入您的授权激活码 (CDK) 并按回车: "${NC})" CONFIRM_KEY
fi

if [ -z "$CONFIRM_KEY" ]; then
    echo -e "${RED}❌ 激活码不能为空，已取消安装。${NC}"
    exit 1
fi

# 3. 确定目标路径
if command -v claude >/dev/null 2>&1; then
    TARGET_PATH=$(command -v claude)
    echo -e "\n${YELLOW}🎯 侦测到已存在 Claude 环境，准备执行升级与覆盖...${NC}"
else
    TARGET_PATH="$HOME/.local/bin/claude"
    echo -e "\n${YELLOW}🎯 准备执行全新安装，目标路径: $TARGET_PATH${NC}"
fi

# 4. 云端鉴权与元数据解析
echo -e "${YELLOW}🔍 正在连接云端服务器验证授权并匹配加速节点...${NC}"

# 调用 API 获取解析结果 (使用 jq 提取字段或使用 grep+awk 纯原生提取)
REQUEST_URL="$API_URL/?key=$CONFIRM_KEY&os=$PLATFORM_OS&arch=$PLATFORM_ARCH"

if ! HTTP_RESPONSE=$(curl -sS -w "\n%{http_code}" "$REQUEST_URL"); then
    echo -e "${RED}❌ 连接云端验证服务器失败，请检查网络或 DNS 解析。${NC}"
    exit 1
fi
HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed '$d')
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tail -n1)

if [ "$HTTP_STATUS" -ne 200 ]; then
    echo -e "${RED}❌ 云端服务器返回异常状态码: $HTTP_STATUS${NC}"
    echo -e "${RED}响应内容: $HTTP_BODY${NC}"
    exit 1
fi

# 简单解析 JSON 中的 success, message, version, tarball
SUCCESS=$(echo "$HTTP_BODY" | grep -o '"success":\(true\|false\)' | cut -d':' -f2)
MESSAGE=$(echo "$HTTP_BODY" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)

if [ "$SUCCESS" != "true" ]; then
    echo -e "${RED}$MESSAGE${NC}"
    exit 1
fi

echo -e "${GREEN}$MESSAGE${NC}"

REMOTE_VERSION=$(echo "$HTTP_BODY" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
TARBALL_URL=$(echo "$HTTP_BODY" | grep -o '"tarball":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TARBALL_URL" ]; then
    echo -e "${RED}❌ 服务器未返回有效的加速节点链接。${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 云端分配最新版本为 v$REMOTE_VERSION${NC}"

# 5. 本地版本比对拦截
if [ -f "$TARGET_PATH" ]; then
    LOCAL_VERSION=$("$TARGET_PATH" --version 2>/dev/null || true)
    # 提取版本号 (例如 v2.1.179 中的 2.1.179)
    LOCAL_VERSION=$(echo "$LOCAL_VERSION" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    
    if [ "$LOCAL_VERSION" = "$REMOTE_VERSION" ]; then
        echo -e "${BLUE}====================================================${NC}"
        echo -e "${GREEN}✨ 检测到当前已是最新版本 v$LOCAL_VERSION，无需重复升级！${NC}"
        exit 0
    fi
fi

# 6. 下载与解压
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

echo -e "${YELLOW}📥 正在通过骨干网高速下载原生二进制包...${NC}"
curl -# -L -o "payload.tgz" "$TARBALL_URL"

echo -e "${YELLOW}📦 正在执行解压与二进制提取...${NC}"
tar -zxf payload.tgz

if [ ! -f "package/claude" ]; then
    echo -e "${RED}❌ 解压失败或产物结构异常: 未找到 package/claude${NC}"
    rm -rf "$TMP_DIR"
    exit 1
fi

# 7. 核心安装逻辑
echo -e "${YELLOW}🚀 正在执行二进制文件安装与权限配置...${NC}"
mkdir -p "$(dirname "$TARGET_PATH")"
cp "package/claude" "$TARGET_PATH"
chmod +x "$TARGET_PATH"
echo -e "${GREEN}✓ 二进制文件已成功安装到: $TARGET_PATH${NC}"

# 8. 环境变量配置
if [[ ":$PATH:" != *":$(dirname "$TARGET_PATH"):"* ]]; then
    SHELL_PROFILE=""
    if [ -n "$ZSHRC" ] || [ -f "$HOME/.zshrc" ]; then
        SHELL_PROFILE="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        SHELL_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        SHELL_PROFILE="$HOME/.bash_profile"
    elif [ -f "$HOME/.profile" ]; then
        SHELL_PROFILE="$HOME/.profile"
    fi

    if [ -n "$SHELL_PROFILE" ]; then
        echo "" >> "$SHELL_PROFILE"
        echo 'export PATH="$PATH:$HOME/.local/bin"' >> "$SHELL_PROFILE"
        echo -e "${YELLOW}⚠️ 已将 ~/.local/bin 添加到您的 $SHELL_PROFILE 中，请运行 'source $SHELL_PROFILE' 或重启终端使其生效。${NC}"
    else
        echo -e "${YELLOW}⚠️ 请手动将 ~/.local/bin 添加到您的 PATH 环境变量中。${NC}"
    fi
fi

# 9. 尝试后台执行官方终端集成 (失败时静默跳过)
echo -e "${YELLOW}🔄 正在后台配置官方终端集成与 Shell 补全...${NC}"
"$TARGET_PATH" install --force >/dev/null 2>&1 &

cd "$HOME"
rm -rf "$TMP_DIR"

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}🎉 部署完成！国内直连体验已就绪。${NC}"
