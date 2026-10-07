#!/bin/bash
# agentmemory 部署脚本 - 使用 --network host 模式
# 适用于 NAS 或 Linux 服务器

set -e

DATA_DIR="/vol1/1000/agentmemory-data"

# 1. 确保数据目录存在
mkdir -p "$DATA_DIR"

# 2. 生成或读取 secret
if [ -f "$DATA_DIR/.secret" ]; then
  SECRET=$(cat "$DATA_DIR/.secret")
  echo "使用已有 Secret"
else
  SECRET=$(openssl rand -hex 32)
  echo "$SECRET" > "$DATA_DIR/.secret"
  chmod 600 "$DATA_DIR/.secret"
  echo "已生成新 Secret: $SECRET"
fi

# 3. 构建自定义镜像（带 curl）
echo "构建自定义镜像..."
docker build -t agentmemory-custom -f "$(dirname "$0")/Dockerfile.agentmemory" "$(dirname "$0")"

# 4. 停止并删除旧容器
docker stop agentmemory 2>/dev/null || true
docker rm agentmemory 2>/dev/null || true

# 5. 启动容器（host 网络模式）
echo "正在启动 agentmemory 容器..."
docker run -d \
  --name agentmemory \
  --restart unless-stopped \
  --network host \
  -v "$DATA_DIR:/home/node/.agentmemory" \
  -e AGENTMEMORY_SECRET="$SECRET" \
  -e EMBEDDING_PROVIDER=local \
  -e EMBEDDING_MODEL=Xenova/all-MiniLM-L6-v2 \
  -e III_TELEMETRY_ENABLED=false \
  -e AGENTMEMORY_CAPTURE_FILTER="password,token,secret,key,credential" \
  -e HOME=/home/node \
  --ulimit nofile=10240:10240 \
  agentmemory-custom

echo "容器已启动，等待初始化..."

# 6. 等待并验证
for i in $(seq 1 30); do
  sleep 10
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $SECRET" http://127.0.0.1:3111/agentmemory/status 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ]; then
    echo "✅ agentmemory 服务已就绪！"
    break
  fi
  echo "等待中... ($i/30) HTTP状态: $STATUS"
done

echo ""
echo "=== 部署完成 ==="
echo "Secret: $SECRET"
echo "Viewer: http://<YOUR_NAS_IP>:3113"
echo "API: http://<YOUR_NAS_IP>:3111"
echo ""
echo "查看日志: docker logs -f agentmemory"
