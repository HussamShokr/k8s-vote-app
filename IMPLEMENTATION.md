# Voting Application Implementation Guide

This guide provides detailed instructions for deploying, configuring, and maintaining the voting application in Kubernetes.

## Table of Contents

- [Architecture Deep Dive](#architecture-deep-dive)
- [Installation](#installation)
- [Configuration Reference](#configuration-reference)
- [Advanced Features](#advanced-features)
- [Maintenance Procedures](#maintenance-procedures)
- [Monitoring and Alerting](#monitoring-and-alerting)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)

## Architecture Deep Dive

### Component Relationships

```
                 ┌─────────┐
                 │ Vote UI │
                 └────┬────┘
                      │
                      ▼
                 ┌─────────┐      ┌─────────┐      ┌─────────────┐
                 │  Redis  │◄────►│  Worker │◄────►│ PostgreSQL  │
                 └─────────┘      └─────────┘      └──────┬──────┘
                                                         │
                                                         ▼
                                                  ┌─────────────┐
                                                  │ Result UI   │
                                                  └─────────────┘
```

### Data Flow

1. **Vote Submission**:
   - Users cast votes through the Vote UI (frontend service)
   - Vote choices are submitted via HTTP POST
   - Each vote contains a vote option and a unique voter ID

2. **Vote Storage in Redis**:
   - Votes are stored in Redis as key-value pairs
   - Key: Voter ID ensures one vote per user
   - Value: Vote choice (e.g., "a" or "b")
   - Redis provides in-memory performance for fast voting

3. **Vote Processing**:
   - Worker service continuously monitors Redis for new votes
   - Processes votes by extracting voter ID and vote choice
   - Updates or inserts records in PostgreSQL
   - If a voter changes their vote, the previous vote is replaced

4. **Result Storage**:
   - PostgreSQL stores the permanent record of all processed votes
   - Schema includes tables for vote counts and individual votes
   - Data is persisted across application restarts

5. **Result Display**:
   - Result UI reads current vote tallies from PostgreSQL
   - Displays real-time vote counts and percentages
   - Updates dynamically as new votes are processed

### Technical Implementation Details

1. **Vote UI**:
   - Built with Python Flask
   - Socket.IO for real-time updates
   - Simple HTTP interface
   - Minimal JavaScript for vote submission

2. **Redis**:
   - Standard Redis instance
   - No persistence configuration required
   - Used for temporary vote storage
   - Optimized for key-value operations

3. **Worker**:
   - .NET application 
   - Connection pooling for database efficiency
   - Optimized for continuous processing
   - Handles Redis connection failures gracefully

4. **PostgreSQL**:
   - Standard PostgreSQL database
   - Uses a simple schema with votes table
   - Configured with appropriate indexes
   - Persistence enabled for data durability

5. **Result UI**:
   - Node.js application
   - Express framework
   - Socket.IO for real-time updates
   - Direct PostgreSQL queries for current results

## Installation

### Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- kubectl configured to connect to your cluster
- Ingress controller installed
- cert-manager v1.5.0+ installed (if using SSL)
- Storage class available for persistent volumes

### Detailed Installation Steps

1. **Prepare Your Environment**

```bash
# Check kubectl connection
kubectl cluster-info

# Verify Helm installation
helm version

# Check for storage classes
kubectl get storageclass

# Ensure Ingress controller is running (for Minikube)
minikube addons enable ingress
kubectl get pods -n ingress-nginx
```

2. **Clone the Repository**

```bash
git clone https://github.com/HussamShokr/voting-app-k8s.git
cd voting-app-k8s
```

3. **Install cert-manager (if needed)**

This step is essential for SSL certificate management:

```bash
# Create namespace
kubectl create namespace cert-manager

# Install cert-manager CRDs
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.crds.yaml

# Add Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.13.2 \
  --set installCRDs=true
  
# Verify installation
kubectl get pods -n cert-manager
```

4. **Customize Configuration**

Review and modify the values.yaml file:

```bash
cd helm-01
# Edit values.yaml to match your environment
# Pay special attention to:
# - Storage classes
# - Persistent volume sizes
# - Resource requests/limits
# - Hostname for Ingress
```

Key areas to customize:
- Storage classes must match those available in your cluster
- Resource limits should be appropriate for your environment
- If using a cloud provider, consider LoadBalancer instead of NodePort
- Set passwords to secure values for production deployments

5. **Update Dependencies**

```bash
helm dependency update
```

6. **Install the Chart**

For Minikube:
```bash
helm install voting-app . --set global.hostname=minikube.local
```

For production:
```bash
# Create a production values file
cp values.yaml production-values.yaml
# Edit production-values.yaml

# Install with production values
helm install voting-app . \
  --set global.hostname=vote.example.com \
  -f production-values.yaml
```

7. **Verify the Installation**

```bash
# Check all resources
kubectl get all

# Check deployments
kubectl get deployments

# Check services
kubectl get svc

# Check pods
kubectl get pods

# Check persistent volume claims
kubectl get pvc

# Check ingress
kubectl get ingress

# Check certificate
kubectl get certificate
```

8. **Set Up DNS or Hosts File**

For Minikube (local development):
```bash
echo "$(minikube ip) minikube.local" | sudo tee -a /etc/hosts
```

For production:
Configure your DNS provider to point your domain to your cluster's ingress controller IP.

9. **Access the Application**

After installation, you can access:
- Vote UI: https://minikube.local/vote
- Result UI: https://minikube.local/result
- Grafana: https://minikube.local/grafana
- Loki: https://minikube.local/loki

## Configuration Reference

### Global Settings

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `global.namespace` | Kubernetes namespace | `default` | `voting-app` |
| `global.env` | Environment name | `production` | `staging` |
| `global.hostname` | Hostname for Ingress | `minikube.local` | `vote.example.com` |

### Database Configuration

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `db.enabled` | Enable PostgreSQL | `true` | `true` |
| `db.name` | Service name | `db` | `postgres` |
| `db.image` | PostgreSQL image | `postgres:15-alpine` | `postgres:16-alpine` |
| `db.replicas` | Number of replicas | `1` | `1` |
| `db.resources.requests.memory` | Memory request | `256Mi` | `512Mi` |
| `db.resources.requests.cpu` | CPU request | `250m` | `500m` |
| `db.resources.limits.memory` | Memory limit | `512Mi` | `1Gi` |
| `db.resources.limits.cpu` | CPU limit | `500m` | `1000m` |
| `db.persistence.enabled` | Enable persistence | `true` | `true` |
| `db.persistence.storageClass` | Storage class | `""` | `"standard"` |
| `db.persistence.size` | PVC size | `1Gi` | `10Gi` |
| `db.persistence.accessMode` | Access mode | `ReadWriteOnce` | `ReadWriteOnce` |
| `db.env.POSTGRES_USER` | PostgreSQL username | `postgres` | `appuser` |
| `db.env.POSTGRES_PASSWORD` | PostgreSQL password | `postgres` | `complexPassword123!` |

### Redis Configuration

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `redis.enabled` | Enable Redis | `true` | `true` |
| `redis.name` | Service name | `redis` | `redis-cache` |
| `redis.image` | Redis image | `redis:alpine` | `redis:7-alpine` |
| `redis.replicas` | Number of replicas | `1` | `1` |
| `redis.resources.requests.memory` | Memory request | `64Mi` | `128Mi` |
| `redis.resources.requests.cpu` | CPU request | `250m` | `300m` |
| `redis.resources.limits.memory` | Memory limit | `128Mi` | `256Mi` |
| `redis.resources.limits.cpu` | CPU limit | `500m` | `600m` |
| `redis.persistence.enabled` | Enable persistence | `true` | `true` |
| `redis.persistence.storageClass` | Storage class | `""` | `"standard"` |
| `redis.persistence.size` | PVC size | `1Gi` | `5Gi` |

### Frontend Services

#### Vote UI

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `vote.enabled` | Enable Vote UI | `true` | `true` |
| `vote.name` | Service name | `vote` | `voting-frontend` |
| `vote.image` | Vote UI image | `kodekloud/examplevotingapp_vote:v1` | `kodekloud/examplevotingapp_vote:v2` |
| `vote.replicas` | Number of replicas | `1` | `3` |
| `vote.service.type` | Service type | `NodePort` | `ClusterIP` |
| `vote.service.port` | Service port | `8080` | `80` |
| `vote.service.targetPort` | Target port | `80` | `8080` |
| `vote.service.nodePort` | NodePort value | `31000` | `30080` |
| `vote.resources.requests.memory` | Memory request | `64Mi` | `128Mi` |
| `vote.resources.requests.cpu` | CPU request | `250m` | `300m` |
| `vote.resources.limits.memory` | Memory limit | `128Mi` | `256Mi` |
| `vote.resources.limits.cpu` | CPU limit | `500m` | `600m` |

#### Result UI

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `result.enabled` | Enable Result UI | `true` | `true` |
| `result.name` | Service name | `result` | `results-frontend` |
| `result.image` | Result UI image | `kodekloud/examplevotingapp_result:v1` | `kodekloud/examplevotingapp_result:v2` |
| `result.replicas` | Number of replicas | `1` | `2` |
| `result.service.type` | Service type | `NodePort` | `ClusterIP` |
| `result.service.port` | Service port | `8081` | `80` |
| `result.service.targetPort` | Target port | `80` | `8080` |
| `result.service.nodePort` | NodePort value | `31001` | `30081` |
| `result.resources.requests.memory` | Memory request | `64Mi` | `128Mi` |
| `result.resources.requests.cpu` | CPU request | `250m` | `300m` |
| `result.resources.limits.memory` | Memory limit | `128Mi` | `256Mi` |
| `result.resources.limits.cpu` | CPU limit | `500m` | `600m` |

### Worker Configuration

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `worker.enabled` | Enable Worker | `true` | `true` |
| `worker.name` | Service name | `worker` | `vote-processor` |
| `worker.image` | Worker image | `kodekloud/examplevotingapp_worker:v2` | `kodekloud/examplevotingapp_worker:v3` |
| `worker.replicas` | Number of replicas | `1` | `2` |
| `worker.resources.requests.memory` | Memory request | `256Mi` | `512Mi` |
| `worker.resources.requests.cpu` | CPU request | `250m` | `500m` |
| `worker.resources.limits.memory` | Memory limit | `512Mi` | `1Gi` |
| `worker.resources.limits.cpu` | CPU limit | `500m` | `1000m` |
| `worker.canary.enabled` | Enable canary | `true` | `true` |
| `worker.canary.image` | Canary image | `kodekloud/examplevotingapp_worker:v2` | `kodekloud/examplevotingapp_worker:v3-beta` |
| `worker.canary.replicas` | Canary replicas | `1` | `1` |
| `worker.canary.weight` | Traffic weight | `20` | `10` |

### HPA Configuration

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `vote.autoscaling.enabled` | Enable Vote HPA | `true` | `true` |
| `vote.autoscaling.minReplicas` | Minimum replicas | `1` | `2` |
| `vote.autoscaling.maxReplicas` | Maximum replicas | `5` | `10` |
| `vote.autoscaling.targetCPUUtilizationPercentage` | Target CPU utilization | `80` | `70` |
| `vote.autoscaling.targetMemoryUtilizationPercentage` | Target memory utilization | `80` | `70` |
| `result.autoscaling.enabled` | Enable Result HPA | `true` | `true` |
| `result.autoscaling.minReplicas` | Minimum replicas | `1` | `2` |
| `result.autoscaling.maxReplicas` | Maximum replicas | `5` | `10` |
| `result.autoscaling.targetCPUUtilizationPercentage` | Target CPU utilization | `80` | `70` |
| `result.autoscaling.targetMemoryUtilizationPercentage` | Target memory utilization | `80` | `70` |
| `worker.autoscaling.enabled` | Enable Worker HPA | `true` | `true` |
| `worker.autoscaling.minReplicas` | Minimum replicas | `1` | `2` |
| `worker.autoscaling.maxReplicas` | Maximum replicas | `5` | `8` |
| `worker.autoscaling.targetCPUUtilizationPercentage` | Target CPU utilization | `80` | `70` |
| `worker.autoscaling.targetMemoryUtilizationPercentage` | Target memory utilization | `80` | `70` |

### Backup Configuration

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `db.backup.enabled` | Enable backup CronJob | `true` | `true` |
| `db.backup.schedule` | Backup schedule (cron format) | `0 1 * * *` | `0 */6 * * *` |
| `db.backup.image` | Backup image | `bitnami/postgresql:15` | `bitnami/postgresql:16` |
| `db.backup.retention` | Number of backups to keep | `7` | `14` |
| `db.backup.resources.requests.memory` | Memory request | `64Mi` | `128Mi` |
| `db.backup.resources.requests.cpu` | CPU request | `100m` | `200m` |
| `db.backup.resources.limits.memory` | Memory limit | `128Mi` | `256Mi` |
| `db.backup.resources.limits.cpu` | CPU limit | `200m` | `300m` |
| `db.backup.storage.size` | Backup storage size | `2Gi` | `5Gi` |
| `db.backup.storage.storageClass` | Storage class | `""` | `"standard"` |

### Ingress Configuration

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `ingress.enabled` | Enable Ingress | `true` | `true` |
| `ingress.name` | Ingress name | `voting-app-ingress` | `vote-ingress` |
| `ingress.annotations` | Ingress annotations | Various | Add custom annotations |
| `ingress.paths.vote` | Path pattern for Vote UI | `/vote(/\|$)(.*)` | `/app/vote(/\|$)(.*)` |
| `ingress.paths.result` | Path pattern for Result UI | `/result(/\|$)(.*)` | `/app/result(/\|$)(.*)` |
| `ingress.paths.grafana` | Path pattern for Grafana | `/grafana(/\|$)(.*)` | `/monitoring/grafana(/\|$)(.*)` |
| `ingress.paths.loki` | Path pattern for Loki | `/loki(/\|$)(.*)` | `/monitoring/loki(/\|$)(.*)` |

### Certificate Configuration

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `certificate.enabled` | Enable SSL certificate | `true` | `true` |
| `certificate.name` | Certificate name | `voting-app-tls` | `vote-tls-cert` |
| `certificate.secretName` | Secret name | `voting-app-tls` | `vote-tls-secret` |
| `certificate.duration` | Certificate duration | `2160h` (90 days) | `8760h` (1 year) |
| `certificate.renewBefore` | Renew certificate before | `360h` (15 days) | `720h` (30 days) |
| `certificate.organization` | Organization name | `Voting App` | `Example Corp` |
| `certificate.wildcardDomain` | Enable wildcard domain | `true` | `false` |
| `clusterIssuer.enabled` | Enable ClusterIssuer | `true` | `true` |
| `clusterIssuer.name` | ClusterIssuer name | `selfsigned-issuer` | `letsencrypt-prod` |

### Network Policies

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `networkPolicies.enabled` | Enable network policies | `true` | `true` |
| `networkPolicies.frontendLabels` | Frontend selector labels | `[app: vote, app: result]` | Custom labels |
| `networkPolicies.backendLabels` | Backend selector labels | `[app: worker]` | Custom labels |
| `networkPolicies.databaseLabels` | Database selector labels | `[app: db, app: redis]` | Custom labels |

## Advanced Features

### Canary Deployments

The Worker component is configured for canary deployments, allowing you to gradually roll out new versions.

#### Canary Configuration

In the values.yaml file:
```yaml
worker:
  canary:
    enabled: true
    image: kodekloud/examplevotingapp_worker:v2
    replicas: 1
    weight: 20  # % of traffic to route to canary
```

#### Implementing a Canary Rollout

1. **Start with a low traffic percentage**:
   ```yaml
   worker:
     canary:
       enabled: true
       image: kodekloud/examplevotingapp_worker:v3-beta
       replicas: 1
       weight: 5  # Start with just 5% of traffic
   ```

2. **Gradually increase the traffic**:
   ```bash
   # Update to 20% traffic
   helm upgrade voting-app ./helm-01 --set worker.canary.weight=20
   
   # Update to 50% traffic
   helm upgrade voting-app ./helm-01 --set worker.canary.weight=50
   
   # Update to 80% traffic
   helm upgrade voting-app ./helm-01 --set worker.canary.weight=80
   ```

3. **Complete the rollout** by updating the main image and disabling canary:
   ```yaml
   worker:
     image: kodekloud/examplevotingapp_worker:v3-beta  # Now main is using the new version
     canary:
       enabled: false
   ```

#### Monitoring a Canary Deployment

```bash
# Check both deployments
kubectl get deployments -l app=worker

# Compare logs between main and canary
kubectl logs -l app=worker,version=stable
kubectl logs -l app=worker,version=canary

# Monitor error rates and performance
# (Use Grafana dashboards for this)
```

### Database Backup and Restore

#### Automated Backups

The automated backup system creates regular backups according to the schedule in values.yaml:

```yaml
db:
  backup:
    enabled: true
    schedule: "0 1 * * *"  # Daily at 1 AM
    retention: 7  # Keep backups for 7 days
```

The backup CronJob uses pg_dump to create a compressed binary backup of the PostgreSQL database.

#### Manual Backup

You can create an on-demand backup:

```bash
# Create a manual backup job
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: manual-db-backup
  labels:
    app: db
spec:
  template:
    spec:
      securityContext:
        runAsUser: 0
        fsGroup: 0
      containers:
      - name: backup
        image: bitnami/postgresql:15
        command:
        - /bin/bash
        - -c
        - |
          # Create a directory with appropriate permissions
          mkdir -p /backups
          chmod 777 /backups
          
          BACKUP_FILE="/backups/postgres-manual-$(date +%Y%m%d-%H%M%S).dump"
          echo "Creating backup: $BACKUP_FILE"
          pg_dump -h db -U postgres -d postgres -F c -f $BACKUP_FILE
          
          # Set appropriate permissions on the backup file
          chmod 644 $BACKUP_FILE
          echo "Backup completed at: $BACKUP_FILE"
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

#### Detailed Restore Procedure

To restore from a backup:

1. **List available backups**:
```bash
kubectl exec -it $(kubectl get pods -l app=db -o jsonpath='{.items[0].metadata.name}') -- ls -la /backups
```

2. **Create a restore job** (replace BACKUP_FILENAME with the actual backup filename):
```bash
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: db-restore
  labels:
    app: db
spec:
  backoffLimit: 3
  template:
    spec:
      securityContext:
        runAsUser: 0
        fsGroup: 0
      containers:
      - name: restore
        image: bitnami/postgresql:15
        command:
        - /bin/bash
        - -c
        - |
          # Set the backup file to restore
          BACKUP_FILE="/backups/BACKUP_FILENAME"
          
          if [ ! -f "$BACKUP_FILE" ]; then
            echo "Backup file $BACKUP_FILE not found!"
            echo "Available backups:"
            ls -la /backups
            exit 1
          fi
          
          echo "Restoring from backup: $BACKUP_FILE"
          # Drop existing connections
          psql -h db -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='postgres' AND pid <> pg_backend_pid();"
          
          # Restore the database
          pg_restore -h db -U postgres -d postgres -c -C $BACKUP_FILE
          
          echo "Restore complete!"
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

3. **Monitor the restore process**:
```bash
# Watch the job status
kubectl get job db-restore -w

# Check the logs
kubectl logs job/db-restore
```

4. **Verify the restoration**:
```bash
# Connect to the database
kubectl exec -it $(kubectl get pods -l app=db -o jsonpath='{.items[0].metadata.name}') -- psql -U postgres

# Check if the data is restored
postgres=# SELECT COUNT(*) FROM votes;
postgres=# \q
```

#### Simulating Disaster Recovery

To test your backup and restore procedure:

1. Create a backup:
```bash
kubectl apply -f manual-db-backup.yaml
```

2. Simulate data loss:
```bash
# Connect to PostgreSQL
kubectl exec -it $(kubectl get pods -l app=db -o jsonpath='{.items[0].metadata.name}') -- psql -U postgres

# Delete data
postgres=# TRUNCATE votes;
postgres=# \q
```

3. Restore from backup:
```bash
kubectl apply -f db-restore.yaml
```

4. Verify data recovery:
```bash
# Check vote counts in the UI or via database query
```

### Network Policies

The chart includes network policies that restrict traffic between application tiers:

#### Frontend Tier Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-policy
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: frontend
  ingress:
  # Allow ingress from anywhere (for public access)
  - {}
  egress:
  # Allow egress only to backend and database services
  - to:
    - podSelector:
        matchLabels:
          app: redis
    ports:
    - protocol: TCP
      port: 6379
```

#### Backend Tier Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-policy
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: backend
  egress:
  # Allow egress only to database services
  - to:
    - podSelector:
        matchLabels:
          app: db
  - to:
    - podSelector:
        matchLabels:
          app: redis
```

#### Database Tier Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-policy
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: database
  ingress:
  # Allow ingress only from backend and frontend
  - from:
    - podSelector:
        matchLabels:
          app: worker
  - from:
    - podSelector:
        matchLabels:
          app: result
```

These network policies enhance security by limiting the potential attack surface. You can customize them by editing the templates in the `templates/network-policies/` directory.

## Maintenance Procedures

### Upgrading the Application

#### Standard Upgrade

To upgrade the application to a new version:

```bash
# Update values in values.yaml, then:
helm upgrade voting-app ./helm-01
```

#### Upgrading Specific Components

To upgrade just one component:

```bash
# Upgrade the vote UI
helm upgrade voting-app ./helm-01 --set vote.image=kodekloud/examplevotingapp_vote:v2

# Upgrade the result UI
helm upgrade voting-app ./helm-01 --set result.image=kodekloud/examplevotingapp_result:v2

# Upgrade the worker
helm upgrade voting-app ./helm-01 --set worker.image=kodekloud/examplevotingapp_worker:v3
```

#### Rollback Procedures

If an upgrade fails or causes issues:

```bash
# List revisions
helm history voting-app

# Rollback to previous revision
helm rollback voting-app 1

# Rollback to specific revision
helm rollback voting-app [REVISION_NUMBER]
```

### Scaling

#### Manual Scaling

You can manually scale components if needed:

```bash
# Scale the vote UI
kubectl scale deployment vote --replicas=3

# Scale the result UI
kubectl scale deployment result --replicas=2

# Scale the worker
kubectl scale deployment worker --replicas=4
```

However, HPA will automatically scale components based on CPU/memory usage if enabled.

#### Modifying HPA Settings

To adjust HPA settings:

```bash
# Create a file called hpa-values.yaml
cat <<EOF > hpa-values.yaml
vote:
  autoscaling:
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70
worker:
  autoscaling:
    minReplicas: 3
    maxReplicas: 8
EOF

# Apply the changes
helm upgrade voting-app ./helm-01 -f hpa-values.yaml
```

### Resource Adjustments

To adjust resource allocations:

```bash
# Create a file called resource-values.yaml
cat <<EOF > resource-values.yaml
vote:
  resources:
    requests:
      memory: "128Mi"
      cpu: "500m"
    limits:
      memory: "256Mi"
      cpu: "1000m"
worker:
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "1Gi"
      cpu: "1000m"
EOF

# Apply the changes
helm upgrade voting-app ./helm-01 -f resource-values.yaml
```

### Certificate Rotation

Certificates are automatically renewed by cert-manager before they expire. However, you can manually rotate them:

```bash
# Delete the certificate
kubectl delete certificate voting-app-tls

# cert-manager will automatically create a new one
# Wait a moment, then check the new certificate
kubectl get certificate voting-app-tls
```

### Database Maintenance

#### Running PostgreSQL Maintenance Commands

```bash
# Connect to PostgreSQL
kubectl exec -it $(kubectl get pods -l app=db -o jsonpath='{.items[0].metadata.name}') -- psql -U postgres

# Run VACUUM
postgres=# VACUUM ANALYZE;

# Check table sizes
postgres=# SELECT pg_size_pretty(pg_total_relation_size('votes'));

# Exit
postgres=# \q
```

#### Database Password Rotation

To change the database password:

```bash
# Create a secret with the new password
kubectl create secret generic db-password --from-literal=password=NewPasswordHere

# Update the deployment
helm upgrade voting-app ./helm-01 --set db.env.POSTGRES_PASSWORD=NewPasswordHere
```

Remember to update any applications that need the new password.

## Monitoring and Alerting

### Grafana Setup

#### Accessing Grafana

1. Access Grafana at `https://minikube.local/grafana`
2. Default credentials: admin/prom-operator
3. Change the password on first login

#### Important Dashboards

The deployment includes several useful dashboards:

1. **Kubernetes Cluster Overview**:
   - Shows node status, resource usage, and health
   - Dashboard ID: 10000

2. **Pod Resources**:
   - Detailed view of pod resource usage
   - Dashboard ID: 10001

3. **Voting App Dashboard**:
   - Application-specific metrics
   - Dashboard ID: 10002

4. **Database Performance**:
   - PostgreSQL performance metrics
   - Dashboard ID: 10003

### Connecting Loki to Grafana

1. In Grafana UI, navigate to Configuration > Data Sources
2. Click "Add data source" and select "Loki"
3. Set the URL to `http://loki.default.svc.cluster.local:3100` (or `http://loki:3100` if in the same namespace)
4. Click "Save & Test"

### Querying Logs

Once Loki is connected, you can query logs using LogQL:

1. Go to Explore in Grafana
2. Select Loki as the data source
3. Use queries like:
   - `{app="vote"}`: Logs from Vote UI
   - `{app="result"}`: Logs from Result UI
   - `{app="worker"}`: Logs from Worker
   - `{app="db"}`: Logs from PostgreSQL
   - `{app="redis"}`: Logs from Redis

4. Filter for errors:
   - `{app="worker"} |= "error"`
   - `{app="vote"} |= "error" | json`

### Creating Custom Dashboards

To create a custom dashboard:

1. Go to "+" > "Dashboard" in Grafana
2. Add a new panel
3. Configure the panel with metrics or logs
4. For voting app metrics, use queries like:
   - `rate(http_requests_total{app="vote"}[5m])`: Request rate
   - `histogram_quantile(0.95, sum(rate(http_response_time_seconds_bucket{app="vote"}[5m])) by (le))`: 95th percentile response time

4. Save the dashboard

### Setting Up Alerts

Basic alerts are included in Prometheus, but you can add custom alerts:

1. Go to Alerting > Notification Channels to set up where alerts should be sent
2. Create a new alert rule:
   - Go to Alerting > Alert Rules > New Alert Rule
   - Configure the query, conditions, and notification channel
   - Example alert: Worker pod restarts
     ```
     count by(container) (changes(kube_pod_container_status_restarts_total{namespace="default", pod=~"worker.*"}[15m]) > 3)
     ```

### Common Monitoring Use Cases

1. **Vote Submission Rate**:
   - Query: `sum(rate(votes_processed_total[5m]))`
   - Shows the rate of votes being processed

2. **Error Rates**:
   - Query: `sum(rate(http_requests_total{status=~"5.."}[5m]))`
   - Shows the rate of 5xx errors

3. **Database Performance**:
   - Query: `pg_stat_activity_count{datname="postgres"}`
   - Shows active database connections

4. **Redis Memory Usage**:
   - Query: `redis_memory_used_bytes / redis_memory_max_bytes * 100`
   - Shows Redis memory usage percentage

## Troubleshooting

### Common Issues

#### Ingress Not Working

1. **Check Ingress Controller**:
   ```bash
   kubectl get pods -n ingress-nginx
   ```
   The ingress-controller pod should be running.

2. **Verify Ingress Configuration**:
   ```bash
   kubectl describe ingress voting-app-ingress
   ```
   Look for errors in the Events section.

3. **Check SSL Configuration**:
   ```bash
   kubectl describe certificate voting-app-tls
   ```
   The certificate should be ready and valid.

4. **Test DNS Resolution**:
   ```bash
   nslookup minikube.local
   # or
   ping minikube.local
   ```
   Ensure the hostname resolves to the correct IP.

5. **Inspect Ingress Controller Logs**:
   ```bash
   kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
   ```
   Look for any error messages.

#### Certificate Issues

1. **Check Certificate Status**:
   ```bash
   kubectl describe certificate voting-app-tls
   ```
   Look for error messages in the Status and Events sections.

2. **Verify ClusterIssuer**:
   ```bash
   kubectl describe clusterissuer selfsigned-issuer
   ```
   Ensure the issuer is configured correctly.

3. **Check cert-manager Logs**:
   ```bash
   kubectl logs -n cert-manager -l app=cert-manager
   ```
   Look for any errors related to certificate issuance.

4. **Verify Secret Creation**:
   ```bash
   kubectl get secret voting-app-tls
   ```
   The secret should exist and contain the certificate.

#### Database Connection Errors

1. **Check Database Pod**:
   ```bash
   kubectl get pods -l app=db
   ```
   Ensure the PostgreSQL pod is running.

2. **Inspect Database Logs**:
   ```bash
   kubectl logs -l app=db
   ```
   Look for error messages.

3. **Check Worker Logs**:
   ```bash
   kubectl logs -l app=worker
   ```
   Look for database connection errors.

4. **Test Database Connection**:
   ```bash
   kubectl exec -it $(kubectl get pods -l app=db -o jsonpath='{.items[0].metadata.name}') -- psql -U postgres -c "SELECT 1;"
   ```
   This should return "1" if the database is working.

5. **Verify Network Policies**:
   ```bash
   kubectl describe networkpolicy
   ```
   Ensure network policies allow connections between worker and database.

#### Persistent Volume Issues

1. **Check PVC Status**:
   ```bash
   kubectl get pvc
   ```
   PVCs should be in the "Bound" state.

2. **Inspect PVC Details**:
   ```bash
   kubectl describe pvc db-data-pvc
   ```
   Look for any errors in the Events section.

3. **Verify Storage Class**:
   ```bash
   kubectl get storageclass
   ```
   Ensure the storage class exists and is working.

4. **Check Pod Events**:
   ```bash
   kubectl describe pod -l app=db
   ```
   Look for volume-related errors.

### Debugging Tools

#### Checking Logs

```bash
# Vote UI logs
kubectl logs -l app=vote

# Result UI logs
kubectl logs -l app=result

# Worker logs
kubectl logs -l app=worker

# Database logs
kubectl logs -l app=db

# Redis logs
kubectl logs -l app=redis
```

For previous container logs:
```bash
kubectl logs -l app=worker --previous
```

For continuous log streaming:
```bash
kubectl logs -l app=worker -f
```

#### Inspecting Resources

```bash
# Describe a deployment
kubectl describe deployment vote

# Get details about a service
kubectl describe service vote

# Check pod details
kubectl describe pod -l app=vote
```

#### Exec into Pods

```bash
# Get a shell in the Vote UI pod
kubectl exec -it $(kubectl get pods -l app=vote -o jsonpath='{.items[0].metadata.name}') -- sh

# Check Redis data
kubectl exec -it $(kubectl get pods -l app=redis -o jsonpath='{.items[0].metadata.name}') -- redis-cli
redis:6379> KEYS *
redis:6379> GET <key>

# Examine PostgreSQL
kubectl exec -it $(kubectl get pods -l app=db -o jsonpath='{.items[0].metadata.name}') -- psql -U postgres
postgres=# \dt
postgres=# SELECT * FROM votes LIMIT 10;
```

#### Network Debugging

```bash
# Test network connectivity
kubectl run -it --rm debug --image=busybox -- sh
/ # wget -O- http://vote:8080
/ # wget -O- http://result:8081
/ # wget -O- http://db:5432
/ # wget -O- http://redis:6379

# Test DNS resolution
/ # nslookup vote.default.svc.cluster.local
/ # nslookup db.default.svc.cluster.local
```

#### Resource Utilization

```bash
# Check CPU and memory usage
kubectl top pods

# Check node resource usage
kubectl top nodes
```

### Diagnostic Steps

For general application issues, follow these steps:

1. **Check Pod Status**:
   ```bash
   kubectl get pods
   ```
   All pods should be in "Running" state.

2. **Check Service Endpoints**:
   ```bash
   kubectl get endpoints
   ```
   Ensure services have endpoints.

3. **Verify Network Policies**:
   ```bash
   kubectl describe networkpolicy
   ```
   Check if traffic is being properly allowed/blocked.

4. **Examine Events**:
   ```bash
   kubectl get events --sort-by='.lastTimestamp'
   ```
   Look for error events.

5. **Validate Application Logs**:
   Review logs for each component as shown above.

6. **Check HPA Status**:
   ```bash
   kubectl get hpa
   ```
   Ensure HPAs are properly scaling.

7. **Validate Ingress and Certificate**:
   ```bash
   kubectl describe ingress
   kubectl describe certificate
   ```
   Check for proper configuration.

8. **Test Application Flow**:
   - Cast a vote at https://minikube.local/vote
   - Check if it appears at https://minikube.local/result
   - If not, check worker logs for processing errors

## Security Considerations

### Best Practices

1. **Secrets Management**:
   - Don't store sensitive information in values.yaml
   - Use Kubernetes Secrets for passwords and tokens
   - Consider using a secrets management solution like HashiCorp Vault or Kubernetes external secrets

   Example:
   ```bash
   # Create a secret for database credentials
   kubectl create secret generic db-credentials \
     --from-literal=username=postgres \
     --from-literal=password=SecurePasswordHere
   
   # Reference in values.yaml
   db:
     env:
       POSTGRES_USER: 
         valueFrom:
           secretKeyRef:
             name: db-credentials
             key: username
       POSTGRES_PASSWORD:
         valueFrom:
           secretKeyRef:
             name: db-credentials
             key: password
   ```

2. **Network Policies**:
   - Customize network policies to match your security requirements
   - Restrict egress traffic where possible
   - Consider using additional policies for namespaces

3. **Resource Quotas**:
   - Implement namespace resource quotas to prevent resource exhaustion
   ```bash
   apiVersion: v1
   kind: ResourceQuota
   metadata:
     name: voting-app-quota
   spec:
     hard:
       requests.cpu: "4"
       requests.memory: 4Gi
       limits.cpu: "8"
       limits.memory: 8Gi
   ```

4. **RBAC for Service Accounts**:
   - Configure proper Role-Based Access Control for the application ServiceAccounts
   - Use the principle of least privilege

   Example:
   ```yaml
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: worker-sa
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: Role
   metadata:
     name: worker-role
   rules:
   - apiGroups: [""]
     resources: ["configmaps"]
     verbs: ["get", "list"]
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: RoleBinding
   metadata:
     name: worker-rolebinding
   subjects:
   - kind: ServiceAccount
     name: worker-sa
   roleRef:
     kind: Role
     name: worker-role
     apiGroup: rbac.authorization.k8s.io
   ```

5. **Certificate Management**:
   - For production, use a trusted Certificate Authority
   - Configure cert-manager with Let's Encrypt for automatic, trusted certificates

   Example values for Let's Encrypt:
   ```yaml
   clusterIssuer:
     name: letsencrypt-prod
     email: admin@example.com
     server: https://acme-v02.api.letsencrypt.org/directory
   ```

6. **Container Security**:
   - Use non-root users in containers
   - Set read-only root filesystems where possible
   - Enable seccomp and AppArmor profiles

   Example securityContext:
   ```yaml
   securityContext:
     runAsNonRoot: true
     runAsUser: 1000
     readOnlyRootFilesystem: true
     allowPrivilegeEscalation: false
   ```

7. **Scanning and Compliance**:
   - Regularly scan container images for vulnerabilities
   - Implement pod security policies
   - Use admission controllers for policy enforcement

### Production Readiness Checklist

- [ ] **Resource Management**:
  - [ ] Set resource requests and limits for all components
  - [ ] Configure HPAs with appropriate scaling parameters
  - [ ] Implement resource quotas for namespaces

- [ ] **Security**:
  - [ ] Update default passwords to strong, random values
  - [ ] Store sensitive data in Kubernetes Secrets
  - [ ] Configure network policies properly
  - [ ] Use RBAC for service accounts
  - [ ] Enable pod security context

- [ ] **Data Management**:
  - [ ] Configure proper persistent storage with appropriate storage classes
  - [ ] Set up regular database backups
  - [ ] Test restore procedures
  - [ ] Implement data retention policies

- [ ] **Observability**:
  - [ ] Set up comprehensive monitoring with Prometheus
  - [ ] Configure Grafana dashboards for visualization
  - [ ] Set up logging with Loki
  - [ ] Configure appropriate alerts

- [ ] **Resilience**:
  - [ ] Use multiple replicas for critical components
  - [ ] Implement pod disruption budgets
  - [ ] Configure pod anti-affinity for high-availability
  - [ ] Set up proper liveness and readiness probes

- [ ] **Networking**:
  - [ ] Use proper SSL certificates from a trusted issuer
  - [ ] Configure Ingress with appropriate annotations
  - [ ] Set up proper network policies

- [ ] **CI/CD**:
  - [ ] Implement GitOps workflow for deployments
  - [ ] Set up CI/CD pipeline for automatic testing and deployment
  - [ ] Configure deployment strategies (blue/green or canary)
