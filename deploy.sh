#!/bin/bash

# FitSync Helm Chart Deployment Script

set -e

ENVIRONMENT=${1:-dev}
CHART_DIR="./fitsync"
VALUES_FILE="values-${ENVIRONMENT}.yaml"

echo "🚀 Deploying FitSync to ${ENVIRONMENT} environment..."

# Check if values file exists
if [ ! -f "$VALUES_FILE" ]; then
    echo "❌ Values file $VALUES_FILE not found!"
    echo "Available values files:"
    ls -la values-*.yaml 2>/dev/null || echo "No values files found"
    
    if [ "$ENVIRONMENT" = "test" ]; then
        echo ""
        echo "💡 To create values-test.yaml, run:"
        echo "   ./fetch-values.sh development"
    fi
    exit 1
fi

# Check if helm chart exists
if [ ! -d "$CHART_DIR" ]; then
    echo "❌ Helm chart directory $CHART_DIR not found!"
    exit 1
fi

# Validate the chart
echo "🔍 Validating Helm chart..."
helm lint "$CHART_DIR"

# Check if release already exists
if helm list | grep -q "^fitsync"; then
    echo "📦 Upgrading existing FitSync release..."
    helm upgrade fitsync "$CHART_DIR" -f "$VALUES_FILE"
else
    echo "📦 Installing new FitSync release..."
    helm install fitsync "$CHART_DIR" -f "$VALUES_FILE"
fi

echo "✅ Deployment completed!"

# Show status
echo ""
echo "📊 Deployment Status:"
kubectl get pods -l app.kubernetes.io/instance=fitsync

echo ""
echo "🌐 Services:"
kubectl get svc -l app.kubernetes.io/instance=fitsync

echo ""
echo "🔗 Istio Resources:"
kubectl get virtualservice fitsync-api 2>/dev/null || echo "VirtualService not found"
kubectl get destinationrule -l app.kubernetes.io/instance=fitsync 2>/dev/null || echo "DestinationRules not found"

echo ""
echo "🎯 To test the deployment:"
echo "kubectl port-forward svc/api-gateway 4000:4000"
echo "curl http://localhost:4000/health"

if [ "$ENVIRONMENT" = "test" ]; then
    echo ""
    echo "⚠️  Using test values with real secrets - monitor for any issues"
fi
