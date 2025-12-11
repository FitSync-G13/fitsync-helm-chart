# Redis TLS Configuration Fixes

## 🔍 Current Issues

1. **No TLS Support**: All services connect to Redis without TLS
2. **Wrong Environment Variables**: Using `REDIS_HOST` + `REDIS_PORT` instead of `REDIS_URL`
3. **CD Pipeline**: Stores `redis://` instead of `rediss://` (TLS)

## 🛠️ Required Fixes

### 1. Update CD Pipeline (database-setup-enhanced.yml)

**Current:**
```bash
redis_connection_string="redis://${{ vars.DB_PRIVATE_DNS }}:6379?tls=true"
```

**Should be:**
```bash
redis_connection_string="rediss://${{ vars.DB_PRIVATE_DNS }}:6379"
```

### 2. Update Node.js Services (user, training, notification)

**Current redis.js:**
```javascript
const redisClient = createClient({
  socket: {
    host: process.env.REDIS_HOST || 'localhost',
    port: process.env.REDIS_PORT || 6379
  }
});
```

**Fixed redis.js:**
```javascript
const redisClient = createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});
```

### 3. Update Python Services (schedule, progress)

**Current:**
```python
redis_client = await aioredis.from_url(
    f"redis://{REDIS_HOST}:{REDIS_PORT}",
    decode_responses=True
)
```

**Fixed:**
```python
redis_client = await aioredis.from_url(
    os.getenv("REDIS_URL", "redis://localhost:6379"),
    decode_responses=True
)
```

### 4. Update Helm Chart

**Current values.yaml:**
```yaml
env:
  REDIS_HOST: "redis-host"
  REDIS_PORT: "6379"
```

**Fixed values.yaml:**
```yaml
env:
  REDIS_URL: "rediss://redis-host:6379"
```

## 🔧 Implementation Steps

### Step 1: Fix CD Pipeline
Update `database-setup-enhanced.yml` line 191:
```yaml
redis_connection_string="rediss://${{ vars.DB_PRIVATE_DNS }}:6379"
```

### Step 2: Fix Node.js Services
For each service (user, training, notification), update `src/config/redis.js`:

```javascript
const { createClient } = require('redis');
const logger = require('./logger');

const redisClient = createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

redisClient.on('error', (err) => {
  logger.error('Redis Client Error:', err);
});

redisClient.on('connect', () => {
  logger.info('Redis connected successfully');
});

const connectRedis = async () => {
  try {
    await redisClient.connect();
  } catch (error) {
    logger.error('Failed to connect to Redis:', error);
    throw error;
  }
};

module.exports = { redisClient, connectRedis };
```

### Step 3: Fix Python Services
For schedule and progress services, update `main.py`:

```python
# Replace REDIS_HOST and REDIS_PORT with REDIS_URL
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")

async def init_redis():
    global redis_client
    redis_client = await aioredis.from_url(
        REDIS_URL,
        decode_responses=True
    )
    logger.info("Redis connected")
```

### Step 4: Update Helm Chart
Update `values.yaml` and templates to use `REDIS_URL`:

```yaml
env:
  REDIS_URL: "rediss://redis-host:6379"
```

And in templates, replace:
```yaml
- name: REDIS_HOST
  value: "{{ .Values.env.REDIS_HOST }}"
- name: REDIS_PORT
  value: "{{ .Values.env.REDIS_PORT }}"
```

With:
```yaml
- name: REDIS_URL
  value: "{{ .Values.env.REDIS_URL }}"
```

## 🧪 Testing TLS Connection

### Node.js Test:
```javascript
const { createClient } = require('redis');
const client = createClient({
  url: 'rediss://your-redis-host:6379'
});
await client.connect();
console.log('TLS connection successful');
```

### Python Test:
```python
import redis.asyncio as aioredis
client = await aioredis.from_url('rediss://your-redis-host:6379')
await client.ping()
print('TLS connection successful')
```

## 📋 Checklist

- [ ] Update CD pipeline to use `rediss://` URLs
- [ ] Fix user-service Redis configuration
- [ ] Fix training-service Redis configuration  
- [ ] Fix notification-service Redis configuration
- [ ] Fix schedule-service Redis configuration
- [ ] Fix progress-service Redis configuration
- [ ] Update Helm chart to use REDIS_URL
- [ ] Test TLS connections
- [ ] Redeploy services with new configuration

## 🚨 Breaking Changes

**Environment Variables Changed:**
- `REDIS_HOST` → Removed
- `REDIS_PORT` → Removed  
- `REDIS_URL` → New (replaces both above)

**Connection String Format:**
- `redis://host:port` → `rediss://host:port` (TLS enabled)
