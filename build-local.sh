#!/bin/bash

# Use this script to build and import Docker images into a local k3s cluster (for development/testing)

set -e # Stop on error

echo "🏗️  Building and Importing FitSync images to k3s..."

# Function to build and import
build_and_import() {
    local service_name=$1
    local dir_path=$2
    local image_tag="fitsync/$service_name:latest"

    echo "------------------------------------------------"
    echo "🔹 Processing $service_name..."
    
    # 1. Build
    docker build -t $image_tag $dir_path
    
    # 2. Import to k3s (requires sudo usually)
    echo "   Importing to k3s..."
    docker save $image_tag | 
    
    echo "✅ $service_name ready!"
}

# Build Backend Services
build_and_import "user-service" "./services/user-service"
build_and_import "training-service" "./services/training-service"
build_and_import "schedule-service" "./services/schedule-service"
build_and_import "progress-service" "./services/progress-service"
build_and_import "notification-service" "./services/notification-service"
build_and_import "api-gateway" "./services/api-gateway"

# Build Frontend
build_and_import "frontend" "./frontend"

echo "------------------------------------------------"
echo "🎉 All images imported to k3s successfully!"