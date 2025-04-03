# Kubernetes Voting Application

This repository contains a Helm chart for deploying a multi-tier voting application to Kubernetes. The application includes frontend services, a backend worker, and database components with monitoring, auto-scaling, and secure networking.

## Application Architecture

The voting application consists of the following components:

- **Frontend Services**:
  - **Vote UI**: Allows users to cast votes between two options (e.g., cats vs. dogs)
  - **Result UI**: Real-time dashboard displaying the current voting results

- **Backend Components**:
  - **Worker**: Processes votes from Redis and stores them in PostgreSQL database
  - **Redis**: In-memory data store for temporary vote collection and caching
  - **PostgreSQL**: Persistent relational database for storing vote results

- **Monitoring & Observability**:
  - **Prometheus**: Time series database for metrics collection and alerting
  - **Grafana**: Visualization dashboards for metrics and logs
  - **Loki**: Log aggregation system designed to store and query logs

## Features

- **Horizontal Pod Autoscaling (HPA)** for frontend and backend services based on CPU and memory metrics
- **Canary deployment** strategy for the backend worker with configurable traffic weight
- **Database backups** with automated CronJob and configurable retention policy
- **Database restoration** procedures for disaster recovery
- **Network policies** to restrict traffic between application tiers, enhancing security
- **Ingress with SSL termination** using auto-renewing self-signed certificates
- **Persistent storage** for databases with configurable storage classes
- **Resource management** with configurable requests and limits
- **Health checks** via readiness and liveness probes
- **Service discovery** via Kubernetes DNS

## Prerequisites

- Kubernetes cluster (Minikube, kind, EKS, GKE, AKS, etc.)
- kubectl command-line tool configured to access your cluster
- Helm v3 installed
- Ingress controller enabled (for Minikube: `minikube addons enable ingress`)
- cert-manager installed (or enable it in the values.yaml)
- Available storage provisioner in your cluster (for persistent volumes)

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/yourusername/voting-app-k8s.git
cd voting-app-k8s
```

### 2. Install cert-manager (if not already installed)

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.crds.yaml
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace
```

### 3. Update dependencies

```bash
cd helm-01
helm dependency update
```

### 4. Install the Helm chart

```bash
helm install voting-app . --set global.hostname=minikube.local
```

### 5. Set up local hostname (for Minikube)

```bash
echo "$(minikube ip) minikube.local" | sudo tee -a /etc/hosts
```

### 6. Access the application

- Vote UI: https://minikube.local/vote
- Result UI: https://minikube.local/result
- Grafana: https://minikube.local/grafana (default credentials: admin/prom-operator)
- Loki: https://minikube.local/loki

## Configuration

The `values.yaml` file contains all configurable parameters for the application. Here are the key configuration sections:

### Global Settings
```yaml
global:
  namespace: default
  env: production
  hostname: minikube.local
```

### Service Configurations
```yaml
vote:
  image: kodekloud/examplevotingapp_vote:v1
  replicas: 1
  resources:
    requests:
      memory: "64Mi"
      cpu: "250m"
    limits:
      memory: "128Mi"
      cpu: "500m"
```

### Autoscaling Parameters
```yaml
vote:
  autoscaling:
    enabled: true
    minReplicas: 1
    maxReplicas: 5
    targetCPUUtilizationPercentage: 80
    targetMemoryUtilizationPercentage: 80
```

### Database Settings
```yaml
db:
  enabled: true
  image: postgres:15-alpine
  env:
    POSTGRES_USER: postgres
    POSTGRES_PASSWORD: postgres
  persistence:
    enabled: true
    size: 1Gi
```

### Backup Settings
```yaml
db:
  backup:
    enabled: true
    schedule: "0 1 * * *"  # Daily at 1 AM
    retention: 7  # Days to keep backups
```

### Ingress Configuration
```yaml
ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
  paths:
    vote: /vote(/|$)(.*)
    result: /result(/|$)(.*)
```

### Certificate Management
```yaml
certificate:
  enabled: true
  duration: 2160h  # 90 days
  renewBefore: 360h  # 15 days
```

Refer to the [Implementation Guide](IMPLEMENTATION.md) for details on advanced configuration options.

## Monitoring and Observability

This deployment includes a complete monitoring stack:

1. **Metrics Collection**: 
   - Prometheus automatically discovers and scrapes metrics from all services
   - Custom metrics for application-specific monitoring
   - Built-in alerts for critical system metrics

2. **Visualization**: 
   - Pre-configured Grafana dashboards for:
     - Kubernetes cluster overview
     - Node metrics
     - Application performance
     - Database health

3. **Logging**:
   - Loki collects logs from all application components
   - Log aggregation with metadata and labels
   - Query and search capabilities through LogQL
   - Integration with Grafana for unified observability

4. **Alerting**:
   - Configured for critical service disruptions
   - CPU/Memory threshold alerts
   - Error rate monitoring
   - Database connectivity issues

Access Grafana at https://minikube.local/grafana (default credentials: admin/prom-operator)

## Backup and Restore

### Database Backups

Automated backups are configured as a CronJob that runs according to the schedule defined in values.yaml (default: daily at 1 AM).

The backup process:
1. Creates a PostgreSQL dump file with timestamp
2. Stores it in a dedicated persistent volume
3. Automatically manages retention by cleaning up old backups

### Restoration Procedure

To restore from a backup:

1. List available backups:
   ```bash
   kubectl exec -it $(kubectl get pods -l app=db -o jsonpath='{.items[0].metadata.name}') -- ls -la /backups
   ```

2. Create a restore job (replace BACKUP_FILENAME with the actual filename):
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: db-restore
     labels:
       app: db
   spec:
     template:
       spec:
         containers:
         - name: restore
           image: bitnami/postgresql:15
           command:
           - /bin/bash
           - -c
           - |
             BACKUP_FILE="/backups/BACKUP_FILENAME"
             pg_restore -h db -U postgres -d postgres -c $BACKUP_FILE
           env:
           - name: PGPASSWORD
             value: postgres
           volumeMounts:
           - name: backup-storage
             mountPath: /backups
         volumes:
         - name: backup-storage
           persistentVolumeClaim:
             claimName: db-backup-pvc
         restartPolicy: OnFailure
   EOF
   ```

For detailed instructions, see the [Implementation Guide](IMPLEMENTATION.md).

## Networking

The application uses network policies to restrict traffic between the different tiers:

- **Frontend tier** (vote, result):
  - Can only communicate with their respective backend services
  - Vote UI can only connect to Redis
  - Result UI can only connect to PostgreSQL

- **Backend tier** (worker):
  - Can only communicate with database tier
  - Bidirectional access to both Redis and PostgreSQL

- **Database tier** (PostgreSQL, Redis):
  - Only accepts connections from appropriate services
  - PostgreSQL accepts connections from Worker and Result UI
  - Redis accepts connections from Vote UI and Worker

This ensures that each component can only access the resources it needs, following the principle of least privilege.

## Troubleshooting

### Common Issues

1. **Pending PVCs**: If persistent volume claims remain in pending state, check your storage class configuration.

2. **Certificate Issues**: If TLS certificates are not working, verify that cert-manager is properly installed and the ClusterIssuer is healthy.

3. **Ingress Problems**: If Ingress is not working, check that the Ingress controller is running and properly configured.

4. **Database Connection Errors**: If components can't connect to databases, check network policies and ensure services are properly resolving.

For detailed troubleshooting steps, see the [Implementation Guide](IMPLEMENTATION.md).

## License

[MIT License](LICENSE)