#!/bin/bash

# Fetch values from AWS Secrets Manager and Terraform for testing

set -e

ENVIRONMENT=${1:-development}
AWS_REGION=${2:-us-east-2}
PROJECT_NAME="fitsync"

echo "🔍 Fetching values for environment: $ENVIRONMENT"
echo "📍 AWS Region: $AWS_REGION"

# Get ECR Registry URL from Terraform
echo ""
echo "📦 Getting ECR Registry URL..."
TERRAFORM_DIR="../fitsync-aws-terraform-modules/live/shared"

if [ ! -d "$TERRAFORM_DIR" ]; then
    echo "❌ Terraform directory not found: $TERRAFORM_DIR"
    exit 1
fi

cd "$TERRAFORM_DIR"
REPO_URLS=$(terraform output -raw repository_urls 2>/dev/null || echo "")

if [ -z "$REPO_URLS" ]; then
    echo "❌ Could not get repository URLs from Terraform output"
    exit 1
fi

# Extract registry URL
FIRST_URL=$(echo "$REPO_URLS" | cut -d',' -f1)
ECR_REGISTRY=$(echo "$FIRST_URL" | sed 's|/fitsync-.*||')

echo "✅ ECR Registry: $ECR_REGISTRY"

# Go back to helm chart directory
cd - > /dev/null

# Get Database URLs from AWS Secrets Manager
echo ""
echo "🔐 Getting database URLs from AWS Secrets Manager..."

# Database services
SERVICES=("user" "training" "schedule" "progress")

# Function to get secret value
get_secret() {
    local secret_name="$1"
    aws secretsmanager get-secret-value \
        --secret-id "$secret_name" \
        --region "$AWS_REGION" \
        --query 'SecretString' \
        --output text 2>/dev/null || echo ""
}

# Get database URLs (using actual secret names from database setup)
USER_DB_URL=$(get_secret "${PROJECT_NAME}/${ENVIRONMENT}/userdb-db-url")
TRAINING_DB_URL=$(get_secret "${PROJECT_NAME}/${ENVIRONMENT}/trainingdb-db-url")
SCHEDULE_DB_URL=$(get_secret "${PROJECT_NAME}/${ENVIRONMENT}/scheduledb-db-url")
PROGRESS_DB_URL=$(get_secret "${PROJECT_NAME}/${ENVIRONMENT}/progressdb-db-url")
REDIS_URL=$(get_secret "${PROJECT_NAME}/${ENVIRONMENT}/redis-url")

# Check if we got all the values
if [ -z "$USER_DB_URL" ] || [ -z "$TRAINING_DB_URL" ] || [ -z "$SCHEDULE_DB_URL" ] || [ -z "$PROGRESS_DB_URL" ] || [ -z "$REDIS_URL" ]; then
    echo "❌ Could not retrieve all database URLs from Secrets Manager"
    echo "Expected secrets:"
    echo "  - ${PROJECT_NAME}/${ENVIRONMENT}/userdb-db-url"
    echo "  - ${PROJECT_NAME}/${ENVIRONMENT}/trainingdb-db-url"
    echo "  - ${PROJECT_NAME}/${ENVIRONMENT}/scheduledb-db-url"
    echo "  - ${PROJECT_NAME}/${ENVIRONMENT}/progressdb-db-url"
    echo "  - ${PROJECT_NAME}/${ENVIRONMENT}/redis-url"
    echo ""
    echo "Available secrets:"
    aws secretsmanager list-secrets --region "$AWS_REGION" --query 'SecretList[?contains(Name, `fitsync`)].Name' --output table
    exit 1
fi

# Extract Redis URL directly (no need to parse host/port)
REDIS_URL_VALUE="$REDIS_URL"

echo "✅ Retrieved all database URLs"

# Create values.yaml for testing
echo ""
echo "📝 Creating values-test.yaml..."

cat > values-test.yaml << EOF
# Generated values for testing - DO NOT COMMIT
# Generated on: $(date)
# Environment: $ENVIRONMENT

global:
  imageRegistry: "$ECR_REGISTRY"
  imageTag: "latest"
  imagePullPolicy: Always

env:
  # JWT Configuration
  JWT_SECRET: "test-jwt-secret-change-for-production"
  JWT_REFRESH_SECRET: "test-refresh-secret-change-for-production"
  JWT_EXPIRY: "15m"
  JWT_REFRESH_EXPIRY: "7d"
  
  # Database URLs (from AWS Secrets Manager)
  USER_DATABASE_URL: "$USER_DB_URL"
  TRAINING_DATABASE_URL: "$TRAINING_DB_URL"
  SCHEDULE_DATABASE_URL: "$SCHEDULE_DB_URL"
  PROGRESS_DATABASE_URL: "$PROGRESS_DB_URL"
  
  # Redis Configuration (from AWS Secrets Manager)
  REDIS_URL: "$REDIS_URL_VALUE"
  
  # SMTP Configuration (for notification service)
  SMTP_HOST: "smtp.gmail.com"
  SMTP_PORT: "587"
  SMTP_USER: "noreply@fitsync.com"
  SMTP_PASSWORD: "test-smtp-password"
  
  # Rate Limiting
  RATE_LIMIT_WINDOW_MS: "900000"
  RATE_LIMIT_MAX_REQUESTS: "100"

# Istio configuration for $ENVIRONMENT
istio:
  gateway:
    name: "${ENVIRONMENT}-gateway"
    namespace: "istio-system"
  
  virtualService:
    name: "fitsync-api"
    hosts:
      - "*"

# Resource limits for testing
services:
  userService:
    replicas: 1
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "256Mi"
        cpu: "250m"
  
  trainingService:
    replicas: 1
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "256Mi"
        cpu: "250m"
  
  scheduleService:
    replicas: 1
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "256Mi"
        cpu: "250m"
  
  progressService:
    replicas: 1
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "256Mi"
        cpu: "250m"
  
  notificationService:
    replicas: 1
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "256Mi"
        cpu: "250m"
  
  apiGateway:
    replicas: 1
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "256Mi"
        cpu: "250m"

# mTLS configuration
security:
  mtls:
    mode: STRICT
EOF

echo "✅ Created values-test.yaml"
echo ""
echo "📊 Summary:"
echo "  ECR Registry: $ECR_REGISTRY"
echo "  Redis URL: $REDIS_URL_VALUE"
echo "  Gateway: ${ENVIRONMENT}-gateway"
echo ""
echo "🚀 Ready to deploy:"
echo "  ./deploy.sh test  # Uses values-test.yaml"
echo ""
echo "⚠️  Remember: values-test.yaml contains secrets - do not commit!"
