#!/bin/bash

# FitSync Cleanup Script - Removes sample app and prepares for FitSync deployment

set -e

echo "🧹 Cleaning up sample applications..."

# Remove Bookinfo sample app (if exists)
echo "Removing Bookinfo sample app..."
kubectl delete virtualservice bookinfo 2>/dev/null || echo "VirtualService bookinfo not found"
kubectl delete destinationrule productpage details ratings reviews 2>/dev/null || echo "DestinationRules not found"
kubectl delete service productpage details ratings reviews 2>/dev/null || echo "Services not found"
kubectl delete deployment productpage-v1 details-v1 ratings-v1 reviews-v1 reviews-v2 reviews-v3 2>/dev/null || echo "Deployments not found"

# Remove any existing FitSync deployment
echo "Removing existing FitSync deployment (if any)..."
helm uninstall fitsync 2>/dev/null || echo "FitSync release not found"

echo "✅ Cleanup completed!"
echo ""
echo "🚀 Ready to deploy FitSync:"
echo "./deploy.sh dev"
