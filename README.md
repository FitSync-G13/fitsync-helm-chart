# FitSync Helm Chart

This directory contains the Helm chart for deploying FitSync microservices to Kubernetes with Istio service mesh.

## Quick Start

### 1. Get ECR Registry URL
```bash
./get-ecr-url.sh
```

### 2. Configure Values
```bash
# Copy and edit the development values file
cp values-dev.yaml values-dev-local.yaml
# Edit values-dev-local.yaml with your actual:
# - ECR registry URL
# - Database URLs
# - Redis URL
# - JWT secrets
```

### 3. Clean Up Sample App
```bash
./cleanup.sh
```

### 4. Deploy FitSync
```bash
./deploy.sh dev  # Uses values-dev.yaml
```

## Directory Structure

```
fitsync-helm-chart/
├── fitsync/                    # Helm chart
│   ├── Chart.yaml             # Chart metadata
│   ├── values.yaml            # Default values
│   ├── templates/             # Kubernetes manifests
│   │   ├── user-service.yaml
│   │   ├── training-service.yaml
│   │   ├── schedule-service.yaml
│   │   ├── progress-service.yaml
│   │   ├── notification-service.yaml
│   │   ├── api-gateway.yaml
│   │   ├── virtualservice.yaml
│   │   ├── destinationrule.yaml
│   │   └── peerauthentication.yaml
│   └── README.md              # Chart documentation
├── values-dev.yaml            # Development values template
├── deploy.sh                  # Deployment script
├── cleanup.sh                 # Cleanup script
├── get-ecr-url.sh            # ECR helper script
└── README.md                  # This file
```

## Services Deployed

| Service | Port | Purpose |
|---------|------|---------|
| user-service | 3001 | User management and authentication |
| training-service | 3002 | Training programs and exercises |
| schedule-service | 8003 | Scheduling and calendar management |
| progress-service | 8004 | Progress tracking and analytics |
| notification-service | 3005 | Email and push notifications |
| api-gateway | 4000 | API Gateway (exposed via Istio) |

## Istio Integration

- **VirtualService**: Routes traffic from Istio Gateway to API Gateway
- **DestinationRule**: Configures mTLS for all services
- **PeerAuthentication**: Enforces STRICT mTLS mode
- Compatible with existing Istio Gateway (development-gateway, staging-gateway, production-gateway)

## Configuration

### Required Environment Variables

```yaml
env:
  # Database URLs (required)
  USER_DATABASE_URL: "postgresql://..."
  TRAINING_DATABASE_URL: "postgresql://..."
  SCHEDULE_DATABASE_URL: "postgresql://..."
  PROGRESS_DATABASE_URL: "postgresql://..."
  
  # Redis (required)
  REDIS_HOST: "your-redis-host"
  REDIS_PORT: "6379"
  
  # JWT Secrets (required)
  JWT_SECRET: "your-production-secret"
  JWT_REFRESH_SECRET: "your-refresh-secret"
```

### ECR Configuration

```yaml
global:
  imageRegistry: "123456789012.dkr.ecr.us-east-2.amazonaws.com"
  imageTag: "latest"
```

## Deployment Environments

### Development
```bash
./deploy.sh dev
```
- Uses `values-dev.yaml`
- Routes to `development-gateway`
- Smaller resource limits

### Staging
```bash
./deploy.sh stage
```
- Uses `values-stage.yaml` (create from template)
- Routes to `staging-gateway`

### Production
```bash
./deploy.sh prod
```
- Uses `values-prod.yaml` (create from template)
- Routes to `production-gateway`
- Higher resource limits and replicas

## Testing

### Local Port Forward
```bash
kubectl port-forward svc/api-gateway 4000:4000
curl http://localhost:4000/health
```

### Via Istio Gateway
```bash
curl https://dev.fitsync.online/api/health
```

## Troubleshooting

### Check Deployment Status
```bash
kubectl get pods
kubectl get svc
kubectl get virtualservice
kubectl get destinationrule
```

### Check Logs
```bash
kubectl logs -l app=api-gateway
kubectl logs -l app=user-service
```

### Check Istio Configuration
```bash
istioctl proxy-status
istioctl proxy-config cluster <pod-name>
```

## Scaling

```bash
# Scale API Gateway
helm upgrade fitsync ./fitsync -f values-dev.yaml --set services.apiGateway.replicas=3

# Scale all services
helm upgrade fitsync ./fitsync -f values-prod.yaml
```

## Security Features

- **mTLS**: All service-to-service communication encrypted
- **JWT Authentication**: Stateless authentication between services
- **Network Policies**: Istio enforces traffic policies
- **Image Security**: ECR vulnerability scanning
- **Secrets Management**: Environment variables for sensitive data

## Monitoring Integration

The chart is ready for integration with:
- **Prometheus**: Metrics collection
- **Grafana**: Visualization
- **Jaeger**: Distributed tracing
- **Kiali**: Service mesh observability

## Next Steps

1. **Configure Database URLs**: Update values file with actual database connections
2. **Configure Redis**: Update values file with Redis connection details
3. **Set JWT Secrets**: Use strong, unique secrets for production
4. **Deploy to Dev**: Test the deployment in development environment
5. **Set up Monitoring**: Integrate with Prometheus/Grafana
6. **CI/CD Integration**: Add to GitHub Actions workflow
