# Observability stack (separate cluster)

Deploy Prometheus/Grafana + OpenSearch in the new observability spoke. Example commands assume:
- Observability cluster context: `kubectl config use-context obs`
- App cluster context: `kubectl config use-context app`
- DNS: `obs.fitsync.online` with subdomains for UIs.

## Helm repos
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add opensearch https://opensearch-project.github.io/helm-charts
helm repo update
```

## Prometheus/Grafana in observability cluster
```bash
kubectl config use-context obs
helm upgrade --install kube-prom-stack prometheus-community/kube-prometheus-stack \
  -n observability --create-namespace \
  -f observability/kube-prometheus-stack-values.yaml
```
- Grafana at `https://grafana.obs.fitsync.online`
- Prometheus remote_write receive at `https://prometheus-receiver.obs.fitsync.online/api/v1/receive`

## Prometheus Agent in app cluster (scrape locally, remote_write to obs)
Edit `observability/prometheus-agent-values.yaml` with the remote_write URL + auth, then:
```bash
kubectl config use-context app
helm upgrade --install prom-agent prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f observability/prometheus-agent-values.yaml
```

## OpenSearch + Dashboards in observability cluster
```bash
kubectl config use-context obs
helm upgrade --install opensearch opensearch/opensearch \
  -n observability \
  -f observability/opensearch-values.yaml

helm upgrade --install opensearch-dashboards opensearch/opensearch-dashboards \
  -n observability \
  -f observability/opensearch-values.yaml
```
- Dashboards at `https://osd.obs.fitsync.online`
- OpenSearch API via TLS ingress at `https://opensearch-api.obs.fitsync.online`

## Fluent Bit in the main cluster (logs -> OpenSearch)
- Edit `observability/fluent-bit-values.yaml` with your OpenSearch host, auth secret (`fluent-bit-opensearch-auth`), and TLS secret (`fluent-bit-opensearch-tls`).
- Deploy in the main cluster:
```bash
kubectl config use-context app
helm upgrade --install fluent-bit fluent/fluent-bit \
  -n logging --create-namespace \
  -f observability/fluent-bit-values.yaml
```

## Notes
- Set real TLS certs/secret names and strong passwords before deploy.
- Lock ingress with Cloudflare IPs and/or WAF; if you must expose via NLB, add TLS termination there instead of plain HTTP.
- For log shipping from app cluster, use HTTPS/mTLS to the OpenSearch ingress host and present the CA to the agent.

