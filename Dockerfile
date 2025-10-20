# 构建阶段
FROM node:22-alpine AS builder

WORKDIR /app

# 安装编译依赖（合并到一个 RUN 减少层数）
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    gcc \
    libc-dev \
    linux-headers && \
    rm -rf /var/cache/apk/*

# 先复制依赖文件（利用 Docker 缓存）
COPY package*.json ./
COPY prisma ./prisma/

# 设置 npm 配置（优化安装速度）
RUN npm config set registry https://registry.npmmirror.com && \
    npm install --legacy-peer-deps --no-audit --prefer-offline

# 生成 Prisma 客户端
RUN npx prisma generate

# 复制源代码（最后复制，避免代码改动导致前面的缓存失效）
COPY . .

# 构建项目
RUN npm run build

# 生产阶段
FROM node:22-alpine

WORKDIR /app

# 只安装运行时依赖
RUN apk add --no-cache openssl libstdc++ && \
    rm -rf /var/cache/apk/*

# 从构建阶段复制必要文件
COPY --from=builder /app/.output /app/.output
COPY --from=builder /app/prisma /app/prisma
COPY --from=builder /app/start.sh /app/start.sh
COPY --from=builder /app/config.json /app/config.json

# 复制 version 文件（如果存在）
COPY --from=builder /app/version /app/version 2>/dev/null || true

# 初始化并安装 Prisma
RUN npm init -y && \
    npm install prisma@latest --save-dev && \
    chmod +x /app/start.sh

# 创建数据目录
RUN mkdir -p /app/data

# 环境变量
ENV NODE_ENV=production \
    DATABASE_URL="file:/app/data/db.sqlite" \
    UPLOAD_DIR="/app/data/upload" \
    CONFIG_FILE="/app/data/config.json"

EXPOSE 3000

VOLUME ["/app/data"]

CMD ["/app/start.sh"]
