#!/bin/bash

# Get ECR Registry URL from Terraform output

set -e

TERRAFORM_DIR="../fitsync-aws-terraform-modules/live/shared"

echo "🔍 Getting ECR registry URL from Terraform..."

if [ ! -d "$TERRAFORM_DIR" ]; then
    echo "❌ Terraform directory not found: $TERRAFORM_DIR"
    exit 1
fi

cd "$TERRAFORM_DIR"

# Get the repository URLs
REPO_URLS=$(terraform output -raw repository_urls 2>/dev/null || echo "")

if [ -z "$REPO_URLS" ]; then
    echo "❌ Could not get repository URLs from Terraform output"
    echo "Make sure you have deployed the shared infrastructure first:"
    echo "cd $TERRAFORM_DIR && terraform apply"
    exit 1
fi

# Extract the registry URL (everything before the first repository name)
FIRST_URL=$(echo "$REPO_URLS" | cut -d',' -f1)
REGISTRY_URL=$(echo "$FIRST_URL" | sed 's|/fitsync-.*||')

echo "✅ ECR Registry URL: $REGISTRY_URL"
echo ""
echo "📝 Update your values file with:"
echo "global:"
echo "  imageRegistry: \"$REGISTRY_URL\""
echo ""
echo "🔗 Available repositories:"
echo "$REPO_URLS" | tr ',' '\n' | sed 's|.*/||'
