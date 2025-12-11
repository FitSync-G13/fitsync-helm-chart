# Quick Test Deployment Guide

## 🚀 Ready to Deploy FitSync to Dev Cluster

The `values-test.yaml` file has been generated with:
- ✅ **ECR Registry**: `074094370475.dkr.ecr.us-east-2.amazonaws.com`
- ✅ **Database URLs**: Retrieved from AWS Secrets Manager
- ✅ **Redis URL**: Retrieved from AWS Secrets Manager
- ✅ **Gateway**: `development-gateway` (matches your dev environment)

## Prerequisites

1. **kubectl** configured for your dev cluster
2. **helm** installed
3. **Sample app removed** (if deployed)

## Deployment Steps

### 1. Clean Up Sample App
```bash
./cleanup.sh
```

### 2. Deploy FitSync
```bash
./deploy.sh test
```

### 3. Monitor Deployment
```bash
# Watch pods starting
kubectl get pods -w

# Check logs if issues
kubectl logs -l app=api-gateway
kubectl logs -l app=user-service
```

### 4. Test the Deployment

#### Port Forward Test
```bash
kubectl port-forward svc/api-gateway 4000:4000
curl http://localhost:4000/health
```

#### Via Istio Gateway
```bash
curl https://dev.fitsync.online/api/health
```

## Expected Services

| Service | Port | Status |
|---------|------|--------|
| user-service | 3001 | Internal |
| training-service | 3002 | Internal |
| schedule-service | 8003 | Internal |
| progress-service | 8004 | Internal |
| notification-service | 3005 | Internal |
| api-gateway | 4000 | Exposed via Istio |

## Troubleshooting

### Image Pull Issues
```bash
# Check ECR authentication
aws ecr get-login-token --region us-east-2

# Verify images exist
aws ecr describe-images --repository-name fitsync-api-gateway --region us-east-2
```

### Database Connection Issues
```bash
# Check if database URLs are correct
kubectl exec -it <pod-name> -- env | grep DATABASE_URL

# Test database connectivity from pod
kubectl exec -it <pod-name> -- nc -zv fitsync-db.dev-api.fitsync.online 5432
```

### Istio Issues
```bash
# Check VirtualService
kubectl get virtualservice fitsync-api -o yaml

# Check Gateway exists
kubectl get gateway development-gateway -n istio-system

# Check mTLS status
istioctl proxy-status
```

## Security Notes

⚠️ **Important**: `values-test.yaml` contains real database credentials and is excluded from git via `.gitignore`

## Next Steps

After successful testing:
1. **Production Deployment**: Create proper secrets management for production
2. **CI/CD Integration**: Add Helm deployment to GitHub Actions
3. **Monitoring**: Set up Prometheus/Grafana for observability
4. **Scaling**: Adjust replicas based on load testing

## Rollback

If something goes wrong:
```bash
# Uninstall FitSync
helm uninstall fitsync

# Redeploy sample app (if needed)
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/bookinfo/platform/kube/bookinfo.yaml
```
