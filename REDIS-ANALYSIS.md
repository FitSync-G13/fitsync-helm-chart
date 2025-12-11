# Redis TLS Configuration Analysis

## 🔍 Current State Analysis

### ✅ What Works
- **Redis v4.6.11** (Node.js) and **redis.asyncio** (Python) both support TLS
- All microservices have Redis integration
- Database setup pipeline creates Redis with TLS certificates

### ❌ What's Broken

#### 1. **Incorrect Redis URL Format in Secrets Manager**
**Current:** `redis://fitsync-db.dev-api.fitsync.online:6379?tls=true`
**Should be:** `rediss://fitsync-db.dev-api.fitsync.online:6379`

#### 2. **Microservices Don't Support TLS URLs**
- **Node.js services** use separate `REDIS_HOST` + `REDIS_PORT`
- **Python services** use `redis://` URL format (no TLS)
- **None support `rediss://` protocol**

#### 3. **Helm Chart Uses Wrong Environment Variables**
- Uses `REDIS_HOST` and `REDIS_PORT` instead of `REDIS_URL`

## 🛠️ Required Fixes

### Phase 1: Fix CD Pipeline (Immediate)
Update `database-setup-enhanced.yml` line ~191:
```bash
# Change from:
redis_connection_string="redis://${{ vars.DB_PRIVATE_DNS }}:6379?tls=true"

# To:
redis_connection_string="rediss://${{ vars.DB_PRIVATE_DNS }}:6379"
```

### Phase 2: Fix Microservices (Code Changes Required)

#### Node.js Services (user, training, notification)
**File:** `src/config/redis.js`
```javascript
// Current (BROKEN):
const redisClient = createClient({
  socket: {
    host: process.env.REDIS_HOST || 'localhost',
    port: process.env.REDIS_PORT || 6379
  }
});

// Fixed (TLS SUPPORT):
const redisClient = createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});
```

#### Python Services (schedule, progress)
**File:** `main.py`
```python
# Current (BROKEN):
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
redis_client = await aioredis.from_url(f"redis://{REDIS_HOST}:{REDIS_PORT}")

# Fixed (TLS SUPPORT):
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
redis_client = await aioredis.from_url(REDIS_URL, decode_responses=True)
```

### Phase 3: Update Helm Chart (✅ Already Fixed)
- Changed from `REDIS_HOST`/`REDIS_PORT` to `REDIS_URL`
- Updated all service templates
- Updated values.yaml

## 🧪 Testing TLS Support

### Node.js Test (redis v4.6.11):
```javascript
const { createClient } = require('redis');

// Test TLS connection
const client = createClient({
  url: 'rediss://fitsync-db.dev-api.fitsync.online:6379'
});

await client.connect();
console.log('✅ TLS connection successful');
```

### Python Test (redis.asyncio):
```python
import redis.asyncio as aioredis

# Test TLS connection
client = await aioredis.from_url(
    'rediss://fitsync-db.dev-api.fitsync.online:6379',
    decode_responses=True
)
await client.ping()
print('✅ TLS connection successful')
```

## 📋 Implementation Priority

### 🚨 Critical (Blocks Deployment)
1. **Fix CD Pipeline** - Update Redis URL format in secrets
2. **Fix Microservices** - Update Redis configuration code

### 🔧 Important (Helm Chart)
3. **Helm Chart** - ✅ Already updated to use REDIS_URL

## 🎯 Deployment Strategy

### Option 1: Quick Fix (For Testing)
1. Manually update the Redis secret to use `rediss://` format
2. Deploy with current microservice code (will fail TLS)
3. Fix microservices later

### Option 2: Complete Fix (Recommended)
1. Fix CD pipeline first
2. Fix all microservice code
3. Rebuild and push new images to ECR
4. Deploy with Helm chart

## 🔧 Manual Secret Fix (For Testing)

```bash
# Update Redis secret manually for testing
aws secretsmanager update-secret \
  --secret-id "fitsync/development/redis-url" \
  --secret-string "rediss://fitsync-db.dev-api.fitsync.online:6379" \
  --region us-east-2
```

## 📝 Current Status

- ✅ **Helm Chart**: Fixed to use REDIS_URL
- ❌ **CD Pipeline**: Still creates `redis://` URLs  
- ❌ **Microservices**: Don't support `rediss://` URLs
- ❌ **Secrets Manager**: Contains wrong URL format

## 🚀 Next Steps

1. **Immediate**: Fix the Redis secret manually for testing
2. **Short-term**: Update microservice code to support TLS URLs
3. **Long-term**: Update CD pipeline to create correct URLs

The Helm chart is ready, but the microservices need code changes to support TLS properly.
