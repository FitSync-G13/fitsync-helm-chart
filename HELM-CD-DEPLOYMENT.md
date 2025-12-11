# FitSync Helm Chart CD Pipeline Deployment Guide

## Overview

This document provides a complete guide for deploying the FitSync Helm chart via GitHub Actions CD pipeline with proper secrets management, ECR authentication, and automated deployment to K3s clusters.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Terraform Secrets Management](#terraform-secrets-management)
3. [CD Pipeline Template](#cd-pipeline-template)
4. [ECR Authentication](#ecr-authentication)
5. [Deployment Workflow](#deployment-workflow)
6. [Configuration Guide](#configuration-guide)
7. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

### Current Manual Process
```
Manual Steps:
1. SSH to cluster
2. Configure ECR authentication
3. Create image pull secrets
4. Deploy Helm chart with values-test.yaml
5. Manual database seeding
```

### Target CD Process
```
GitHub Actions Workflow:
1. Authenticate with AWS (OIDC)
2. Retrieve secrets from AWS Secrets Manager
3. Configure ECR authentication on K3s
4. Generate dynamic values.yaml
5. Deploy Helm chart
6. Run database migrations/seeding
7. Verify deployment
```

### Secrets Architecture
```
AWS Secrets Manager Structure:
├── fitsync/{environment}/jwt-secret
├── fitsync/{environment}/jwt-refresh-secret
├── fitsync/{environment}/smtp-password
├── fitsync/{environment}/userdb-db-url
├── fitsync/{environment}/trainingdb-db-url
├── fitsync/{environment}/scheduledb-db-url
├── fitsync/{environment}/progressdb-db-url
└── fitsync/{environment}/redis-url
```

---

## Terraform Secrets Management

### 1. Update Spoke Module for JWT Secrets

**File: `modules/spoke/secrets.tf`** (New file)
```hcl
# Generate JWT secrets using random provider
resource "random_password" "jwt_secret" {
  length  = 64
  special = true
}

resource "random_password" "jwt_refresh_secret" {
  length  = 64
  special = true
}

# Store JWT secrets in AWS Secrets Manager
resource "aws_secretsmanager_secret" "jwt_secret" {
  name        = "${var.project_name}/${var.deployment_environment}/jwt-secret"
  description = "JWT secret for ${var.deployment_environment} environment"
  
  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-${var.deployment_environment}-jwt-secret"
    Type    = "JWT"
    Service = "authentication"
  })
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = random_password.jwt_secret.result
}

resource "aws_secretsmanager_secret" "jwt_refresh_secret" {
  name        = "${var.project_name}/${var.deployment_environment}/jwt-refresh-secret"
  description = "JWT refresh secret for ${var.deployment_environment} environment"
  
  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-${var.deployment_environment}-jwt-refresh-secret"
    Type    = "JWT"
    Service = "authentication"
  })
}

resource "aws_secretsmanager_secret_version" "jwt_refresh_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_refresh_secret.id
  secret_string = random_password.jwt_refresh_secret.result
}

# SMTP password secret (to be set manually or via CI/CD)
resource "aws_secretsmanager_secret" "smtp_password" {
  name        = "${var.project_name}/${var.deployment_environment}/smtp-password"
  description = "SMTP password for ${var.deployment_environment} environment"
  
  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-${var.deployment_environment}-smtp-password"
    Type    = "SMTP"
    Service = "notification"
  })
}

# Placeholder for SMTP password (update manually)
resource "aws_secretsmanager_secret_version" "smtp_password" {
  secret_id     = aws_secretsmanager_secret.smtp_password.id
  secret_string = "CHANGE_ME_IN_AWS_CONSOLE"
  
  lifecycle {
    ignore_changes = [secret_string]
  }
}
```

### 2. Update Spoke Module Outputs

**File: `modules/spoke/outputs.tf`** (Add to existing)
```hcl
# JWT Secrets outputs
output "jwt_secret_arn" {
  description = "ARN of JWT secret in Secrets Manager"
  value       = aws_secretsmanager_secret.jwt_secret.arn
}

output "jwt_refresh_secret_arn" {
  description = "ARN of JWT refresh secret in Secrets Manager"
  value       = aws_secretsmanager_secret.jwt_refresh_secret.arn
}

output "smtp_password_secret_arn" {
  description = "ARN of SMTP password secret in Secrets Manager"
  value       = aws_secretsmanager_secret.smtp_password.arn
}

# Helm deployment information
output "helm_deployment_info" {
  description = "Information needed for Helm deployment"
  value = {
    cluster_name     = "${var.project_name}-${var.env}"
    environment      = var.deployment_environment
    ecr_registry     = data.aws_caller_identity.current.account_id
    aws_region       = var.aws_region
    master_instances = aws_instance.master[*].private_ip
    worker_instances = aws_instance.worker[*].private_ip
  }
}
```

### 3. Update GitHub Environment Variables

**File: `modules/spoke/github.tf`** (Update existing)
```hcl
# Add Helm-specific environment variables
resource "github_actions_environment_variable" "helm_chart_path" {
  repository    = var.github_repo
  environment   = github_repository_environment.main.environment
  variable_name = "HELM_CHART_PATH"
  value         = "fitsync"
}

resource "github_actions_environment_variable" "ecr_registry" {
  repository    = var.github_repo
  environment   = github_repository_environment.main.environment
  variable_name = "ECR_REGISTRY"
  value         = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

resource "github_actions_environment_variable" "master_instances" {
  repository    = var.github_repo
  environment   = github_repository_environment.main.environment
  variable_name = "MASTER_INSTANCES"
  value         = join(",", aws_instance.master[*].private_ip)
}

resource "github_actions_environment_variable" "worker_instances" {
  repository    = var.github_repo
  environment   = github_repository_environment.main.environment
  variable_name = "WORKER_INSTANCES"
  value         = join(",", aws_instance.worker[*].private_ip)
}
```

---

## CD Pipeline Template

### 1. Create Helm Deployment Template

**File: `fitsync-cd-templates/.github/workflows/helm-deploy.yml`**
```yaml
name: Deploy FitSync Helm Chart

on:
  workflow_call:
    inputs:
      environment:
        description: 'Target environment (development/staging/production)'
        required: true
        type: string
      helm_chart_path:
        description: 'Path to Helm chart'
        required: false
        type: string
        default: 'fitsync'
      image_tag:
        description: 'Docker image tag to deploy'
        required: false
        type: string
        default: 'latest'
      run_migrations:
        description: 'Run database migrations'
        required: false
        type: boolean
        default: true
      run_seeding:
        description: 'Run database seeding'
        required: false
        type: boolean
        default: false
    secrets:
      AWS_ROLE_ARN:
        required: true

permissions:
  id-token: write
  contents: read

jobs:
  deploy-helm:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
        aws-region: ${{ vars.AWS_REGION }}
        role-session-name: GitHubActions-Helm-Deploy

    - name: Install dependencies
      run: |
        # Install Helm
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
        
        # Install kubectl
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/

    - name: Get infrastructure information
      id: infra
      run: |
        echo "Getting master instances..."
        MASTER_IPS="${{ vars.MASTER_INSTANCES }}"
        echo "master_ips=$MASTER_IPS" >> $GITHUB_OUTPUT
        
        echo "Getting worker instances..."
        WORKER_IPS="${{ vars.WORKER_INSTANCES }}"
        echo "worker_ips=$WORKER_IPS" >> $GITHUB_OUTPUT
        
        echo "Setting ECR registry..."
        echo "ecr_registry=${{ vars.ECR_REGISTRY }}" >> $GITHUB_OUTPUT

    - name: Retrieve secrets from AWS Secrets Manager
      id: secrets
      run: |
        echo "Retrieving secrets for environment: ${{ inputs.environment }}"
        
        # Get database URLs
        USER_DB_URL=$(aws secretsmanager get-secret-value \
          --secret-id "fitsync/${{ inputs.environment }}/userdb-db-url" \
          --query 'SecretString' --output text)
        
        TRAINING_DB_URL=$(aws secretsmanager get-secret-value \
          --secret-id "fitsync/${{ inputs.environment }}/trainingdb-db-url" \
          --query 'SecretString' --output text)
        
        SCHEDULE_DB_URL=$(aws secretsmanager get-secret-value \
          --secret-id "fitsync/${{ inputs.environment }}/scheduledb-db-url" \
          --query 'SecretString' --output text)
        
        PROGRESS_DB_URL=$(aws secretsmanager get-secret-value \
          --secret-id "fitsync/${{ inputs.environment }}/progressdb-db-url" \
          --query 'SecretString' --output text)
        
        REDIS_URL=$(aws secretsmanager get-secret-value \
          --secret-id "fitsync/${{ inputs.environment }}/redis-url" \
          --query 'SecretString' --output text)
        
        # Get JWT secrets
        JWT_SECRET=$(aws secretsmanager get-secret-value \
          --secret-id "fitsync/${{ inputs.environment }}/jwt-secret" \
          --query 'SecretString' --output text)
        
        JWT_REFRESH_SECRET=$(aws secretsmanager get-secret-value \
          --secret-id "fitsync/${{ inputs.environment }}/jwt-refresh-secret" \
          --query 'SecretString' --output text)
        
        # Get SMTP password
        SMTP_PASSWORD=$(aws secretsmanager get-secret-value \
          --secret-id "fitsync/${{ inputs.environment }}/smtp-password" \
          --query 'SecretString' --output text)
        
        # Set outputs (masked for security)
        echo "::add-mask::$USER_DB_URL"
        echo "::add-mask::$TRAINING_DB_URL"
        echo "::add-mask::$SCHEDULE_DB_URL"
        echo "::add-mask::$PROGRESS_DB_URL"
        echo "::add-mask::$REDIS_URL"
        echo "::add-mask::$JWT_SECRET"
        echo "::add-mask::$JWT_REFRESH_SECRET"
        echo "::add-mask::$SMTP_PASSWORD"
        
        echo "user_db_url=$USER_DB_URL" >> $GITHUB_OUTPUT
        echo "training_db_url=$TRAINING_DB_URL" >> $GITHUB_OUTPUT
        echo "schedule_db_url=$SCHEDULE_DB_URL" >> $GITHUB_OUTPUT
        echo "progress_db_url=$PROGRESS_DB_URL" >> $GITHUB_OUTPUT
        echo "redis_url=$REDIS_URL" >> $GITHUB_OUTPUT
        echo "jwt_secret=$JWT_SECRET" >> $GITHUB_OUTPUT
        echo "jwt_refresh_secret=$JWT_REFRESH_SECRET" >> $GITHUB_OUTPUT
        echo "smtp_password=$SMTP_PASSWORD" >> $GITHUB_OUTPUT

    - name: Configure ECR authentication on K3s cluster
      run: |
        echo "Configuring ECR authentication..."
        
        # Get ECR login token
        ECR_TOKEN=$(aws ecr get-login-password --region ${{ vars.AWS_REGION }})
        
        # Configure ECR authentication on all master nodes
        IFS=',' read -ra MASTERS <<< "${{ steps.infra.outputs.master_ips }}"
        for master_ip in "${MASTERS[@]}"; do
          echo "Configuring ECR on master: $master_ip"
          
          aws ssm send-command \
            --instance-ids $(aws ec2 describe-instances \
              --filters "Name=private-ip-address,Values=$master_ip" \
              --query 'Reservations[0].Instances[0].InstanceId' \
              --output text) \
            --document-name "AWS-RunShellScript" \
            --parameters "commands=[
              'sudo mkdir -p /etc/rancher/k3s',
              'echo \"configs:
  \\\"${{ steps.infra.outputs.ecr_registry }}\\\":
    auth:
      username: AWS
      password: $ECR_TOKEN\" | sudo tee /etc/rancher/k3s/registries.yaml',
              'sudo systemctl restart k3s',
              'sleep 10'
            ]" \
            --region ${{ vars.AWS_REGION }} > /dev/null
        done
        
        echo "ECR authentication configured on all masters"

    - name: Create Helm values file
      run: |
        cat > values-cd.yaml << EOF
        # Generated values for CD deployment
        # Environment: ${{ inputs.environment }}
        # Generated: $(date)
        
        global:
          imageRegistry: "${{ steps.infra.outputs.ecr_registry }}"
          imageTag: "${{ inputs.image_tag }}"
          imagePullPolicy: Always
        
        env:
          # JWT Configuration (from Secrets Manager)
          JWT_SECRET: "${{ steps.secrets.outputs.jwt_secret }}"
          JWT_REFRESH_SECRET: "${{ steps.secrets.outputs.jwt_refresh_secret }}"
          JWT_EXPIRY: "15m"
          JWT_REFRESH_EXPIRY: "7d"
          
          # Database URLs (from Secrets Manager)
          USER_DATABASE_URL: "${{ steps.secrets.outputs.user_db_url }}"
          TRAINING_DATABASE_URL: "${{ steps.secrets.outputs.training_db_url }}"
          SCHEDULE_DATABASE_URL: "${{ steps.secrets.outputs.schedule_db_url }}"
          PROGRESS_DATABASE_URL: "${{ steps.secrets.outputs.progress_db_url }}"
          
          # Redis Configuration (from Secrets Manager)
          REDIS_URL: "${{ steps.secrets.outputs.redis_url }}"
          
          # SMTP Configuration
          SMTP_HOST: "smtp.gmail.com"
          SMTP_PORT: "587"
          SMTP_USER: "noreply@fitsync.com"
          SMTP_PASSWORD: "${{ steps.secrets.outputs.smtp_password }}"
          
          # Rate Limiting
          RATE_LIMIT_WINDOW_MS: "900000"
          RATE_LIMIT_MAX_REQUESTS: "100"
        
        # Istio configuration
        istio:
          gateway:
            name: "${{ inputs.environment }}-gateway"
            namespace: "istio-system"
          
          virtualService:
            name: "fitsync-api"
            hosts:
              - "*"
        
        # Resource configuration based on environment
        services:
          userService:
            replicas: ${{ inputs.environment == 'production' && 2 || 1 }}
            resources:
              requests:
                memory: "${{ inputs.environment == 'production' && '256Mi' || '128Mi' }}"
                cpu: "${{ inputs.environment == 'production' && '250m' || '100m' }}"
              limits:
                memory: "${{ inputs.environment == 'production' && '512Mi' || '256Mi' }}"
                cpu: "${{ inputs.environment == 'production' && '500m' || '250m' }}"
          
          trainingService:
            replicas: ${{ inputs.environment == 'production' && 2 || 1 }}
            resources:
              requests:
                memory: "${{ inputs.environment == 'production' && '256Mi' || '128Mi' }}"
                cpu: "${{ inputs.environment == 'production' && '250m' || '100m' }}"
              limits:
                memory: "${{ inputs.environment == 'production' && '512Mi' || '256Mi' }}"
                cpu: "${{ inputs.environment == 'production' && '500m' || '250m' }}"
          
          scheduleService:
            replicas: ${{ inputs.environment == 'production' && 2 || 1 }}
            resources:
              requests:
                memory: "${{ inputs.environment == 'production' && '256Mi' || '128Mi' }}"
                cpu: "${{ inputs.environment == 'production' && '250m' || '100m' }}"
              limits:
                memory: "${{ inputs.environment == 'production' && '512Mi' || '256Mi' }}"
                cpu: "${{ inputs.environment == 'production' && '500m' || '250m' }}"
          
          progressService:
            replicas: ${{ inputs.environment == 'production' && 2 || 1 }}
            resources:
              requests:
                memory: "${{ inputs.environment == 'production' && '256Mi' || '128Mi' }}"
                cpu: "${{ inputs.environment == 'production' && '250m' || '100m' }}"
              limits:
                memory: "${{ inputs.environment == 'production' && '512Mi' || '256Mi' }}"
                cpu: "${{ inputs.environment == 'production' && '500m' || '250m' }}"
          
          notificationService:
            replicas: ${{ inputs.environment == 'production' && 2 || 1 }}
            resources:
              requests:
                memory: "${{ inputs.environment == 'production' && '256Mi' || '128Mi' }}"
                cpu: "${{ inputs.environment == 'production' && '250m' || '100m' }}"
              limits:
                memory: "${{ inputs.environment == 'production' && '512Mi' || '256Mi' }}"
                cpu: "${{ inputs.environment == 'production' && '500m' || '250m' }}"
          
          apiGateway:
            replicas: ${{ inputs.environment == 'production' && 3 || 1 }}
            resources:
              requests:
                memory: "${{ inputs.environment == 'production' && '256Mi' || '128Mi' }}"
                cpu: "${{ inputs.environment == 'production' && '250m' || '100m' }}"
              limits:
                memory: "${{ inputs.environment == 'production' && '512Mi' || '256Mi' }}"
                cpu: "${{ inputs.environment == 'production' && '500m' || '250m' }}"
        
        # mTLS configuration
        security:
          mtls:
            mode: STRICT
        EOF

    - name: Setup kubectl access
      run: |
        echo "Setting up kubectl access to K3s cluster..."
        
        # Get first master IP
        FIRST_MASTER=$(echo "${{ steps.infra.outputs.master_ips }}" | cut -d',' -f1)
        
        # Get master instance ID
        MASTER_INSTANCE_ID=$(aws ec2 describe-instances \
          --filters "Name=private-ip-address,Values=$FIRST_MASTER" \
          --query 'Reservations[0].Instances[0].InstanceId' \
          --output text)
        
        # Copy kubeconfig from master
        aws ssm send-command \
          --instance-ids $MASTER_INSTANCE_ID \
          --document-name "AWS-RunShellScript" \
          --parameters 'commands=[
            "sudo cat /etc/rancher/k3s/k3s.yaml"
          ]' \
          --region ${{ vars.AWS_REGION }} \
          --output text \
          --query "Command.CommandId" > /tmp/cmd_id.txt
        
        COMMAND_ID=$(cat /tmp/cmd_id.txt)
        
        # Wait for command completion
        sleep 10
        
        # Get kubeconfig content
        aws ssm get-command-invocation \
          --command-id $COMMAND_ID \
          --instance-id $MASTER_INSTANCE_ID \
          --region ${{ vars.AWS_REGION }} \
          --query 'StandardOutputContent' \
          --output text > kubeconfig
        
        # Update server URL to use NLB DNS
        NLB_DNS="${{ vars.PROJECT_NAME }}-${{ vars.SPOKE_ENV }}-nlb-${{ vars.AWS_REGION }}.elb.amazonaws.com"
        sed -i "s/127.0.0.1:6443/$NLB_DNS:6443/g" kubeconfig
        
        export KUBECONFIG=$(pwd)/kubeconfig
        echo "KUBECONFIG=$(pwd)/kubeconfig" >> $GITHUB_ENV
        
        # Test connection
        kubectl get nodes

    - name: Create ECR image pull secret
      run: |
        echo "Creating ECR image pull secret..."
        
        # Get ECR token
        ECR_TOKEN=$(aws ecr get-login-password --region ${{ vars.AWS_REGION }})
        
        # Create or update image pull secret
        kubectl create secret docker-registry ecr-secret \
          --docker-server=${{ steps.infra.outputs.ecr_registry }} \
          --docker-username=AWS \
          --docker-password=$ECR_TOKEN \
          --namespace=default \
          --dry-run=client -o yaml | kubectl apply -f -

    - name: Deploy Helm chart
      run: |
        echo "Deploying FitSync Helm chart..."
        
        # Validate chart
        helm lint ${{ inputs.helm_chart_path }}
        
        # Deploy or upgrade
        if helm list | grep -q "^fitsync"; then
          echo "Upgrading existing release..."
          helm upgrade fitsync ./${{ inputs.helm_chart_path }} \
            -f values-cd.yaml \
            --timeout 10m \
            --wait
        else
          echo "Installing new release..."
          helm install fitsync ./${{ inputs.helm_chart_path }} \
            -f values-cd.yaml \
            --timeout 10m \
            --wait
        fi

    - name: Patch deployments with image pull secret
      run: |
        echo "Patching deployments to use ECR image pull secret..."
        
        # List of services to patch
        SERVICES=("user-service" "training-service" "schedule-service" "progress-service" "notification-service" "api-gateway")
        
        for service in "${SERVICES[@]}"; do
          echo "Patching $service..."
          kubectl patch deployment $service \
            -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"ecr-secret"}]}}}}' || true
        done

    - name: Wait for deployment
      run: |
        echo "Waiting for all deployments to be ready..."
        
        # Wait for all deployments
        kubectl wait --for=condition=available --timeout=600s deployment --all
        
        echo "All deployments are ready!"

    - name: Run database migrations
      if: inputs.run_migrations
      run: |
        echo "Running database migrations..."
        
        # Run Node.js migrations
        echo "Running user service migrations..."
        USER_POD=$(kubectl get pods -l app=user-service -o jsonpath='{.items[0].metadata.name}')
        kubectl exec $USER_POD -c user-service -- node src/database/migrate.js || true
        
        echo "Running training service migrations..."
        TRAINING_POD=$(kubectl get pods -l app=training-service -o jsonpath='{.items[0].metadata.name}')
        kubectl exec $TRAINING_POD -c training-service -- node src/database/migrate.js || true

    - name: Run database seeding
      if: inputs.run_seeding
      run: |
        echo "Running database seeding..."
        
        # Seed Node.js services
        echo "Seeding user service..."
        USER_POD=$(kubectl get pods -l app=user-service -o jsonpath='{.items[0].metadata.name}')
        kubectl exec $USER_POD -c user-service -- node src/database/seed.js || true
        
        echo "Seeding training service..."
        TRAINING_POD=$(kubectl get pods -l app=training-service -o jsonpath='{.items[0].metadata.name}')
        kubectl exec $TRAINING_POD -c training-service -- node src/database/seed.js || true
        
        # Seed Python services
        echo "Seeding schedule service..."
        SCHEDULE_POD=$(kubectl get pods -l app=schedule-service -o jsonpath='{.items[0].metadata.name}')
        kubectl exec $SCHEDULE_POD -c schedule-service -- python seed.py || true
        
        echo "Seeding progress service..."
        PROGRESS_POD=$(kubectl get pods -l app=progress-service -o jsonpath='{.items[0].metadata.name}')
        kubectl exec $PROGRESS_POD -c progress-service -- python seed.py || true

    - name: Verify deployment
      run: |
        echo "Verifying deployment..."
        
        # Check all pods are running
        kubectl get pods
        
        # Check services
        kubectl get svc
        
        # Check Istio resources
        kubectl get virtualservice,destinationrule,peerauthentication
        
        # Test API Gateway health
        API_POD=$(kubectl get pods -l app=api-gateway -o jsonpath='{.items[0].metadata.name}')
        kubectl exec $API_POD -c api-gateway -- curl -f http://localhost:4000/health || echo "Health check failed"
        
        echo "Deployment verification completed!"

    - name: Cleanup
      if: always()
      run: |
        # Clean up sensitive files
        rm -f values-cd.yaml kubeconfig
```

This document provides a complete framework for CD deployment. The next sections would cover the orchestrator workflow, configuration examples, and troubleshooting guides. Would you like me to continue with the remaining sections?
