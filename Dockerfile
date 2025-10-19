# ========================================
# 第一阶段：构建阶段
# ========================================
FROM node:22-alpine AS builder

WORKDIR /app

# ⚠️⚠️⚠️ 关键步骤：必须在 npm install 之前安装这些依赖 ⚠️⚠️⚠️
# 这些是编译 bcrypt 等原生模块必需的
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    gcc \
    libc-dev \
    linux-headers

# 复制依赖配置文件
COPY package*.json ./
COPY prisma ./prisma/

# 安装所有依赖（包括开发依赖）
RUN npm install

# 复制整个项目
COPY . .

# 生成 Prisma 客户端
RUN npx prisma generate

# 构建项目
RUN npm run build

# ========================================
# 第二阶段：生产阶段
# ========================================
FROM node:22-alpine AS stage-1

WORKDIR /app

# 安装运行时依赖
RUN apk add --no-cache openssl libstdc++

# 从构建阶段复制编译好的文件
COPY --from=builder /app/.output /app/.output
COPY --from=builder /app/prisma /app/prisma
COPY --from=builder /app/start.sh /app/start.sh
COPY --from=builder /app/config.json /app/config.json

# 复制 version 文件（如果存在）
COPY --from=builder /app/version /app/version

# 初始化 package.json
RUN npm init -y

# 安装 Prisma CLI（用于运行迁移）
RUN npm install prisma@latest

# 给启动脚本执行权限
RUN chmod +x /app/start.sh

# 创建数据目录
RUN mkdir -p /app/data

# 设置环境变量
ENV NODE_ENV=production \
    DATABASE_URL="file:/app/data/db.sqlite" \
    UPLOAD_DIR="/app/data/upload" \
    CONFIG_FILE="/app/data/config.json"

# 暴露端口
EXPOSE 3000

# 启动命令
CMD ["/app/start.sh"]