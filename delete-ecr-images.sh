#!/bin/bash

# Delete all images from FitSync ECR repositories

set -e

AWS_REGION="us-east-2"
PROJECT_NAME="fitsync"

# List of all microservices
SERVICES=(
  "user-service"
  "training-service"
  "schedule-service"
  "progress-service"
  "notification-service"
  "api-gateway"
  "frontend"
)

echo "🗑️  Deleting all images from FitSync ECR repositories..."

for service in "${SERVICES[@]}"; do
  REPO_NAME="${PROJECT_NAME}-${service}"
  
  echo "Processing repository: $REPO_NAME"
  
  # Get all image tags
  IMAGE_TAGS=$(aws ecr list-images \
    --repository-name "$REPO_NAME" \
    --region "$AWS_REGION" \
    --query 'imageIds[*].imageTag' \
    --output text 2>/dev/null || echo "")
  
  if [ -z "$IMAGE_TAGS" ] || [ "$IMAGE_TAGS" = "None" ]; then
    echo "  ℹ️  No images found in $REPO_NAME"
    continue
  fi
  
  # Convert space-separated tags to array
  IFS=' ' read -ra TAGS <<< "$IMAGE_TAGS"
  
  echo "  🗑️  Deleting ${#TAGS[@]} images from $REPO_NAME"
  
  # Delete images in batches (AWS CLI limit is 100 per call)
  for ((i=0; i<${#TAGS[@]}; i+=100)); do
    BATCH_TAGS=("${TAGS[@]:i:100}")
    
    # Build imageIds JSON for batch delete
    IMAGE_IDS=""
    for tag in "${BATCH_TAGS[@]}"; do
      if [ -n "$IMAGE_IDS" ]; then
        IMAGE_IDS="$IMAGE_IDS,"
      fi
      IMAGE_IDS="$IMAGE_IDS{\"imageTag\":\"$tag\"}"
    done
    
    # Delete batch
    aws ecr batch-delete-image \
      --repository-name "$REPO_NAME" \
      --region "$AWS_REGION" \
      --image-ids "[$IMAGE_IDS]" \
      --output text > /dev/null
    
    echo "    ✅ Deleted batch of ${#BATCH_TAGS[@]} images"
  done
  
  echo "  ✅ All images deleted from $REPO_NAME"
done

echo ""
echo "🎉 All ECR images deleted successfully!"
echo ""
echo "📊 Repository status:"
for service in "${SERVICES[@]}"; do
  REPO_NAME="${PROJECT_NAME}-${service}"
  COUNT=$(aws ecr list-images \
    --repository-name "$REPO_NAME" \
    --region "$AWS_REGION" \
    --query 'length(imageIds)' \
    --output text 2>/dev/null || echo "0")
  echo "  $REPO_NAME: $COUNT images"
done
