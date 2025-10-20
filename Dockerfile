# 构建阶段
FROM node:18-alpine AS builder

WORKDIR /app

# 安装构建依赖（用于编译原生模块）
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    gcc \
    libc-dev \
    linux-headers

# 复制 package 文件
COPY package*.json ./
COPY prisma ./prisma/

# 设置 npm 使用预编译二进制（加速）
ENV npm_config_build_from_source=false \
    npm_config_prefer_offline=true

# 安装依赖
RUN npm ci --prefer-offline --no-audit

# 生成 Prisma 客户端
RUN npx prisma generate

# 复制源代码
COPY . .

# 构建应用
RUN npm run build

# 生产阶段 - 使用更小的基础镜像
FROM node:18-alpine

WORKDIR /app

# 只安装运行时库
RUN apk add --no-cache \
    openssl \
    libstdc++ \
    tini

# 创建非 root 用户（安全最佳实践）
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# 复制 package 文件
COPY --chown=nodejs:nodejs package*.json ./

# 只安装生产依赖，优先使用预编译
ENV NODE_ENV=production \
    npm_config_build_from_source=false
RUN npm ci --only=production --prefer-offline --no-audit && \
    npm cache clean --force

# 从构建阶段复制文件
COPY --from=builder --chown=nodejs:nodejs /app/.output /app/.output
COPY --from=builder --chown=nodejs:nodejs /app/prisma /app/prisma
COPY --from=builder --chown=nodejs:nodejs /app/node_modules/.prisma /app/node_modules/.prisma
COPY --from=builder --chown=nodejs:nodejs /app/public /app/public

# 复制启动脚本和配置
COPY --chown=nodejs:nodejs start.sh /app/start.sh
COPY --chown=nodejs:nodejs config.json /app/config.json

RUN chmod +x /app/start.sh

# 创建数据目录
RUN mkdir -p /app/data && chown nodejs:nodejs /app/data

# 切换到非 root 用户
USER nodejs

# 环境变量
ENV NODE_ENV=production \
    PORT=3000 \
    DATABASE_URL="file:/app/data/db.sqlite" \
    UPLOAD_DIR="/app/data/upload" \
    CONFIG_FILE="/app/data/config.json"

# 暴露端口
EXPOSE 3000

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# 使用 tini 作为 init 进程（处理信号）
ENTRYPOINT ["/sbin/tini", "--"]

# 启动命令
CMD ["/app/start.sh"]