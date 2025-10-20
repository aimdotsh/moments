# ========================================
# 构建阶段
# ========================================
FROM node:22-alpine AS builder

WORKDIR /app

# 安装编译依赖（用于 bcrypt 等原生模块）
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    gcc \
    libc-dev \
    linux-headers

# 复制依赖文件
COPY package*.json ./
COPY prisma ./prisma/

# 安装依赖
RUN npm install

# 复制源代码
COPY . .

# 生成 Prisma 客户端
RUN npx prisma generate

# 构建项目
RUN npm run build

# 确保必要文件存在（避免后续复制失败）
RUN touch /app/version

# ========================================
# 生产阶段
# ========================================
FROM node:22-alpine

WORKDIR /app

# 安装运行时依赖
RUN apk add --no-cache openssl libstdc++

# 从构建阶段复制文件
COPY --from=builder /app/.output /app/.output
COPY --from=builder /app/prisma /app/prisma
COPY --from=builder /app/start.sh /app/start.sh
COPY --from=builder /app/config.json /app/config.json
COPY --from=builder /app/version /app/version

# 初始化并安装 Prisma
RUN npm init -y && \
    npm install prisma@latest

# 设置权限
RUN chmod +x /app/start.sh

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