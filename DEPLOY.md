# Running the Voting App on Minikube (Ubuntu)

## Prerequisites

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| Ubuntu | 20.04+ | Host OS |
| Docker | 20.10+ | Minikube driver |
| Minikube | 1.30+ | Local Kubernetes cluster |
| kubectl | 1.25+ | Cluster management |
| Helm | 3.10+ | Chart deployment |

---

## Step 1 — Install Docker

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# Allow running Docker without sudo
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker --version
```

---

## Step 2 — Install Minikube

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64

# Verify
minikube version
```

---

## Step 3 — Install kubectl

```bash
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Verify
kubectl version --client
```

---

## Step 4 — Install Helm

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
```

---

## Step 5 — Start Minikube

```bash
# Minimum for the app only (no monitoring)
minikube start --driver=docker --cpus=2 --memory=4096

# If you plan to enable monitoring (Prometheus + Grafana + Loki)
# minikube start --driver=docker --cpus=4 --memory=8192

# Verify the cluster is running
kubectl get nodes
# Expected: a single node with STATUS=Ready
```

---

## Step 6 — Enable Required Addons

```bash
# NGINX ingress controller (required for routing /vote and /result)
minikube addons enable ingress

# Metrics server (required for HPA to scale pods)
minikube addons enable metrics-server

# Verify both are running (may take ~60 seconds)
kubectl get pods -n ingress-nginx
kubectl get pods -n kube-system | grep metrics-server
```

---

## Step 7 — Add the Hostname to /etc/hosts

```bash
# Get the Minikube IP
minikube ip
# Example output: 192.168.49.2

# Add the entry (replace the IP if yours is different)
echo "$(minikube ip) minikube.local" | sudo tee -a /etc/hosts

# Verify
ping -c1 minikube.local
```

---

## Step 8 — Clone the Repository

```bash
git clone https://github.com/HussamShokr/k8s-vote-app.git
cd k8s-vote-app
```

---

## Step 9 — Install the Helm Chart

The chart dependencies (cert-manager, kube-prometheus-stack, loki-stack) are
already bundled as tarballs in `helm/charts/` — no download required.

```bash
helm install voting-app ./helm --set global.hostname=minikube.local
```

Expected output:
```
NAME: voting-app
LAST DEPLOYED: ...
NAMESPACE: default
STATUS: deployed
```

---

## Step 10 — Wait for All Pods to Be Ready

```bash
# Watch pods come up (Ctrl+C when all are Running)
kubectl get pods -w

# Or wait non-interactively (up to 5 minutes)
kubectl wait --for=condition=ready pod \
  -l app=db --timeout=300s

kubectl wait --for=condition=ready pod \
  -l app=redis --timeout=60s

kubectl wait --for=condition=ready pod \
  -l app=vote --timeout=120s

kubectl wait --for=condition=ready pod \
  -l app=result --timeout=120s

kubectl wait --for=condition=ready pod \
  -l app=worker --timeout=180s
```

> **Note:** The worker pod has init containers that wait for PostgreSQL and Redis
> to be healthy before starting. This is normal and expected.

---

## Step 11 — Access the Application

Open your browser and navigate to:

| Service | URL |
|---------|-----|
| Vote UI | https://minikube.local/vote |
| Result UI | https://minikube.local/result |

> **SSL Warning:** The app uses a self-signed certificate. Your browser will show
> a security warning — click "Advanced" → "Proceed" to continue.

---

## Step 12 — Verify Everything Is Working

```bash
# All pods should be Running
kubectl get pods

# Ingress should have an ADDRESS
kubectl get ingress

# Certificate should be READY=True
kubectl get certificate

# HPA should show current/target metrics
kubectl get hpa

# PersistentVolumeClaims should be Bound
kubectl get pvc
```

---

## Optional — Enable Monitoring (Prometheus + Grafana + Loki)

Requires Minikube started with `--cpus=4 --memory=8192`.

```bash
helm upgrade voting-app ./helm \
  --set global.hostname=minikube.local \
  --set monitoring.enabled=true \
  --set monitoring.lokiEnabled=true

# Wait for monitoring pods (takes 2-3 minutes)
kubectl get pods -w

# Access Grafana
# URL: https://minikube.local/grafana
# Username: admin
# Password: prom-operator
```

---

## Optional — Apply Raw Kubernetes Specs (without Helm)

If you prefer to deploy without Helm, use the plain manifests directly:

```bash
# Apply in order (Secret and PVC must exist before the DB deployment)
kubectl apply -f k8s-specifications/db-secret.yaml
kubectl apply -f k8s-specifications/db-pvc.yaml
kubectl apply -f k8s-specifications/

# Watch pods
kubectl get pods -w
```

> This approach does not include Ingress, TLS, HPA, canary deployments,
> network policies, or monitoring. Use the Helm chart for the full setup.

---

## Uninstall

```bash
# Remove the Helm release
helm uninstall voting-app

# Delete persistent volumes (data will be lost)
kubectl delete pvc --all

# Stop Minikube
minikube stop

# Delete the Minikube cluster entirely
minikube delete
```

---

## Troubleshooting

### Pods stuck in Pending
```bash
kubectl describe pod <pod-name>
# Look for "Events" section at the bottom
# Common cause: PVC not bound — check storage class
kubectl get storageclass
```

### Worker stuck in Init state
```bash
kubectl logs <worker-pod-name> -c wait-for-db
kubectl logs <worker-pod-name> -c wait-for-redis
# The init containers print status messages — DB or Redis may still be starting
```

### Certificate not becoming Ready
```bash
kubectl describe certificate voting-app-tls
kubectl logs -n default -l app=cert-manager
# cert-manager is deployed in the default namespace via the bundled chart
```

### Ingress returns 404
```bash
kubectl describe ingress voting-app-ingress
# Ensure the ingress controller is running
kubectl get pods -n ingress-nginx
# Ensure /etc/hosts has the correct Minikube IP
cat /etc/hosts | grep minikube.local
minikube ip   # compare with above
```

### HPA showing "unknown" metrics
```bash
kubectl get hpa
# If TARGETS shows <unknown>, metrics-server is not ready yet
kubectl get pods -n kube-system | grep metrics-server
# Wait 60-90 seconds after enabling the addon
```

### Reset everything and start fresh
```bash
helm uninstall voting-app
kubectl delete pvc --all
helm install voting-app ./helm --set global.hostname=minikube.local
```
