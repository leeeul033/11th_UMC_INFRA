#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/umc-boot.log) 2>&1

dnf install -y docker
systemctl enable --now docker

mkdir -p /opt/umc

cat > /opt/umc/swap.sh <<'SWAP'
#!/bin/bash
set -euo pipefail

REGION=ap-southeast-2

p() {
  aws ssm get-parameter --region "$REGION" \
    --name "/umc/app/$1" --with-decryption \
    --query Parameter.Value --output text
}

IMAGE=$(p image)

aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "${IMAGE%%/*}"

docker pull "$IMAGE"

docker rm -f app >/dev/null 2>&1 || true

docker run -d --name app --restart unless-stopped \
  -p 3000:3000 \
  "$IMAGE"
SWAP

chmod +x /opt/umc/swap.sh
/opt/umc/swap.sh

# 3. 관측 수집기 — 2주차 3.3

p() {
  aws ssm get-parameter \
    --region ap-southeast-2 \
    --name "/umc/app/$1" \
    --with-decryption \
    --query Parameter.Value \
    --output text
}

# 1. SSM에서 Grafana 접속 정보 가져오기

GC_FLEET_URL=$(p gc-fleet-url)
GC_FLEET_USER=$(p gc-fleet-user)
GC_TOKEN=$(p gc-token)
GC_PROM_URL=$(p gc-prom-url)
GC_PROM_USER=$(p gc-prom-user)

export GC_FLEET_URL GC_FLEET_USER GC_TOKEN
export GC_PROM_URL GC_PROM_USER
export GCLOUD_RW_API_KEY="$GC_TOKEN"

# 2. Alloy 설정 파일 생성

mkdir -p /opt/alloy /var/lib/alloy

cat > /opt/alloy/config.alloy <<'ALLOY'
logging { level = "info" }

remotecfg {
  url = sys.env("GC_FLEET_URL")
  basic_auth {
    username = sys.env("GC_FLEET_USER")
    password = sys.env("GC_TOKEN")
  }
  id             = constants.hostname
  poll_frequency = "5m"
}
ALLOY

# 3. Alloy 컨테이너 실행

docker run -d --name alloy --restart unless-stopped \
  --network host --pid host \
  -v /:/rootfs:ro \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /opt/alloy/config.alloy:/etc/alloy/config.alloy:ro \
  -v /var/lib/alloy:/var/lib/alloy \
  -e GC_FLEET_URL -e GC_FLEET_USER -e GC_TOKEN \
  -e GC_PROM_URL -e GC_PROM_USER \
  -e GCLOUD_RW_API_KEY \
  grafana/alloy:v1.20.1 run \
  --storage.path=/var/lib/alloy \
  /etc/alloy/config.alloy
