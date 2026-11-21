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
USERDATAcat > userdata.sh <<'USERDATA'
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
