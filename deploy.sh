#!/usr/bin/env bash
set -euo pipefail

export AWS_REGION=ap-southeast-2
export AWS_DEFAULT_REGION=ap-southeast-2

SHA=$(git rev-parse --short HEAD)

ECR=$(aws ecr describe-repositories \
  --repository-names umc-app \
  --query 'repositories[0].repositoryUri' \
  --output text)

TG=$(aws elbv2 describe-target-groups \
  --names umc-app-tg \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

echo "배포 이미지: ${ECR}:${SHA}"

# 1. ARM64 이미지 빌드 및 ECR 업로드
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "${ECR%%/*}"

docker buildx build \
  --builder umc-arm-builder \
  --platform linux/arm64 \
  --provenance=false \
  -t "${ECR}:${SHA}" \
  --push .

# 2. 앞으로 사용할 이미지 태그 등록
aws ssm put-parameter \
  --name /umc/app/image \
  --type String \
  --value "${ECR}:${SHA}" \
  --overwrite >/dev/null

# 3. 정상 타겟이 2대인지 검사
HEALTHY=$(aws elbv2 describe-target-health \
  --target-group-arn "$TG" \
  --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
  --output text)

if [ "$HEALTHY" != "2" ]; then
  echo "오류: 정상 타겟이 2대가 아닙니다. 현재: $HEALTHY"
  exit 1
fi

# 4. ASG 인스턴스 목록 가져오기
IDS=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names umc-asg \
  --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
  --output text)

if [ "$(echo "$IDS" | wc -w)" -ne 2 ]; then
  echo "오류: InService 인스턴스가 2대가 아닙니다."
  exit 1
fi

# 5. 한 대씩 Rolling 배포
for ID in $IDS; do
  echo "===== 배포 시작: $ID ====="

  # 트래픽 제외 및 기존 요청 종료 대기
  aws elbv2 deregister-targets \
    --target-group-arn "$TG" \
    --targets Id="$ID"

  aws elbv2 wait target-deregistered \
    --target-group-arn "$TG" \
    --targets Id="$ID"

  # EC2 내부 컨테이너 교체
  CID=$(aws ssm send-command \
    --instance-ids "$ID" \
    --document-name AWS-RunShellScript \
    --parameters 'commands=["bash /opt/umc/swap.sh"]' \
    --query 'Command.CommandId' \
    --output text)

  STATUS="Pending"

  for ATTEMPT in $(seq 1 60); do
    STATUS=$(aws ssm list-command-invocations \
      --command-id "$CID" \
      --query 'CommandInvocations[0].Status' \
      --output text)

    case "$STATUS" in
      Success)
        break
        ;;
      Pending|InProgress|Delayed|None)
        sleep 5
        ;;
      *)
        break
        ;;
    esac
  done

  if [ "$STATUS" != "Success" ]; then
    echo "배포 실패: $ID / 상태: $STATUS"

    aws ssm list-command-invocations \
      --command-id "$CID" \
      --details \
      --query 'CommandInvocations[0].CommandPlugins[0].Output' \
      --output text

    exit 1
  fi

  # 다시 트래픽에 연결
  aws elbv2 register-targets \
    --target-group-arn "$TG" \
    --targets Id="$ID"

  aws elbv2 wait target-in-service \
    --target-group-arn "$TG" \
    --targets Id="$ID"

  echo "===== 배포 완료: $ID ====="
done

echo "PASS: Rolling deployment completed"
