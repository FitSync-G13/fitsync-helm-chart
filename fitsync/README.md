# FitSync Microservices Helm Chart

This Helm chart deploys the FitSync microservices architecture to a Kubernetes cluster with Istio service mesh.

## Architecture

The chart deploys the following microservices:
- **user-service** (Port 3001) - User management and authentication
- **training-service** (Port 3002) - Training programs and exercises
- **schedule-service** (Port 8003) - Scheduling and calendar management
- **progress-service** (Port 8004) - Progress tracking and analytics
- **notification-service** (Port 3005) - Email and push notifications
- **api-gateway** (Port 4000) - API Gateway (exposed via Istio)

## Prerequisites

1. **Kubernetes cluster** with Istio installed
2. **Istio Gateway** deployed (e.g., `development-gateway`)
3. **ECR access** configured for pulling images
4. **Database URLs** for each service
5. **Redis URL** for caching and sessions

## Configuration

### Required Values

Before deploying, update `values.yaml` with:

```yaml
global:
  imageRegistry: "YOUR_ECR_REGISTRY_URL"  # e.g., 123456789012.dkr.ecr.us-east-2.amazonaws.com

env:
  # Database URLs (required)
  USER_DATABASE_URL: "postgresql://user:pass@host:port/userdb"
  TRAINING_DATABASE_URL: "postgresql://user:pass@host:port/trainingdb"
  SCHEDULE_DATABASE_URL: "postgresql://user:pass@host:port/scheduledb"
  PROGRESS_DATABASE_URL: "postgresql://user:pass@host:port/progressdb"
  
  # Redis (required)
  REDIS_HOST: "your-redis-host"
  REDIS_PORT: "6379"
  
  # JWT Secrets (required)
  JWT_SECRET: "your-production-jwt-secret"
  JWT_REFRESH_SECRET: "your-production-refresh-secret"
  
  # SMTP (optional - for notifications)
  SMTP_PASSWORD: "your-smtp-password"

istio:
  gateway:
    name: "development-gateway"  # Match your environment gateway
```

## Deployment

### 1. Remove Sample App (if deployed)
```bash
kubectl delete virtualservice bookinfo
kubectl delete destinationrule productpage details ratings reviews
kubectl delete service productpage details ratings reviews
kubectl delete deployment productpage-v1 details-v1 ratings-v1 reviews-v1 reviews-v2 reviews-v3
```

### 2. Deploy FitSync
```bash
# Install the chart
helm install fitsync ./fitsync

# Or upgrade if already installed
helm upgrade fitsync ./fitsync
```

### 3. Verify Deployment
```bash
# Check pods
kubectl get pods

# Check services
kubectl get svc

# Check Istio resources
kubectl get virtualservice
kubectl get destinationrule
kubectl get peerauthentication
```

## Testing

### 1. Check API Gateway Health
```bash
# Port forward to test locally
kubectl port-forward svc/api-gateway 4000:4000

# Test health endpoint
curl http://localhost:4000/health
```

### 2. Test via Istio Gateway
```bash
# Test through the gateway (replace with your domain)
curl https://dev.fitsync.online/api/health
```

## Istio Integration

### mTLS Configuration
- **PeerAuthentication**: Enforces STRICT mTLS for all services
- **DestinationRule**: Configures ISTIO_MUTUAL TLS for service-to-service communication
- **VirtualService**: Routes traffic from Istio Gateway to API Gateway

### Traffic Flow
```
Internet → Cloudflare → ALB → Istio Gateway → VirtualService → API Gateway → Microservices
```

## Scaling

```bash
# Scale individual services
helm upgrade fitsync ./fitsync --set services.apiGateway.replicas=3
helm upgrade fitsync ./fitsync --set services.userService.replicas=2
```

## Troubleshooting

### 1. Image Pull Errors
```bash
# Check ECR authentication
aws ecr get-login-token --region us-east-2

# Verify image exists
aws ecr describe-images --repository-name fitsync-api-gateway
```

### 2. Service Communication Issues
```bash
# Check mTLS status
istioctl proxy-status

# Check service mesh configuration
istioctl proxy-config cluster <pod-name>
```

### 3. Database Connection Issues
```bash
# Check environment variables
kubectl exec -it <pod-name> -- env | grep DATABASE_URL

# Test database connectivity
kubectl exec -it <pod-name> -- nc -zv <db-host> <db-port>
```

## Environment-Specific Values

### Development
```yaml
istio:
  gateway:
    name: "development-gateway"
```

### Staging
```yaml
istio:
  gateway:
    name: "staging-gateway"
```

### Production
```yaml
istio:
  gateway:
    name: "production-gateway"
services:
  apiGateway:
    replicas: 3
  userService:
    replicas: 2
```

## Security

- **mTLS**: All service-to-service communication encrypted
- **JWT**: Stateless authentication between services
- **Network Policies**: Istio enforces traffic policies
- **Image Security**: ECR vulnerability scanning enabled

## Monitoring

The services expose metrics and health endpoints:
- Health: `GET /health`
- Metrics: `GET /metrics` (if implemented)

Integrate with:
- **Prometheus**: For metrics collection
- **Grafana**: For visualization
- **Jaeger**: For distributed tracing
- **Kiali**: For service mesh observability
