# NATS ArgoCD Stack

Multi-cluster GitOps infrastructure using ArgoCD hub-spoke pattern.

## Architecture

```
Hub Cluster (ArgoCD)
    │
    ├── ApplicationSets
    │       │
    │       ├── clusters/hub/config.yaml      ──► Hub (self-managing)
    │       ├── clusters/staging/config.yaml  ──► Spoke: staging
    │       └── clusters/prod/config.yaml     ──► Spoke: production
    │
    └── Auto-generates apps per cluster:
            ├── cert-manager (wave 0)
            ├── crossplane (wave 1)
            ├── external-dns (wave 1)
            ├── external-secrets (wave 1)
            ├── mimir (wave 3)
            ├── nats (wave 3)
            └── control-plane (wave 4)
```

> **Single-cluster deployment**: The hub can manage itself. Complete both Hub and Spoke setup on the same cluster, using `https://kubernetes.default.svc` as the server URL.

---

## Prerequisites

Complete these steps BEFORE setting up any clusters.

### 1. Enable GCP APIs

```bash
gcloud services enable \
  container.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  dns.googleapis.com \
  cloudkms.googleapis.com \
  servicenetworking.googleapis.com
```

### 2. Private Services Access (for Cloud SQL)

```bash
gcloud compute addresses create google-managed-services-default \
    --global --purpose=VPC_PEERING --prefix-length=16 --network=default

gcloud services vpc-peerings connect \
    --service=servicenetworking.googleapis.com \
    --ranges=google-managed-services-default --network=default
```

### 3. Create Service Accounts

```bash
export PROJECT_ID="your-project"

# External Secrets SA - reads from GCP Secret Manager
gcloud iam service-accounts create external-secrets-sa \
    --display-name="External Secrets Operator"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:external-secrets-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/secretmanager.admin"

# Crossplane SA - manages Cloud SQL, KMS, networking
gcloud iam service-accounts create crossplane-sa \
    --display-name="Crossplane GCP Provider"
for role in roles/cloudsql.admin roles/cloudkms.admin roles/compute.networkAdmin; do
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:crossplane-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="$role"
done

# External DNS SA - manages Cloud DNS records
gcloud iam service-accounts create external-dns \
    --display-name="External DNS"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:external-dns@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/dns.admin"
```

### 4. Generate Service Account Keys

```bash
export PROJECT_ID="your-project"

# Create keys directory (git-ignored)
mkdir -p .keys

# Key for External Secrets (gcpsm-secret)
gcloud iam service-accounts keys create .keys/external-secrets-sa.json \
    --iam-account=external-secrets-sa@${PROJECT_ID}.iam.gserviceaccount.com

# Key for Crossplane (gcp-credentials)
gcloud iam service-accounts keys create .keys/crossplane-sa.json \
    --iam-account=crossplane-sa@${PROJECT_ID}.iam.gserviceaccount.com
```

> **Security Note**: These keys grant significant GCP access.
> - Never commit to git (`.keys/` is in `.gitignore`)
> - Consider Workload Identity for production
> - Rotate regularly: `gcloud iam service-accounts keys list` / `delete` / `create`

### 5. Workload Identity Bindings

```bash
export PROJECT_ID="your-project"

# For control-plane secret generator
gcloud iam service-accounts add-iam-policy-binding \
    external-secrets-sa@${PROJECT_ID}.iam.gserviceaccount.com \
    --role=roles/iam.workloadIdentityUser \
    --member="serviceAccount:${PROJECT_ID}.svc.id.goog[control-plane/secret-generator]"

# For external-dns
gcloud iam service-accounts add-iam-policy-binding \
    external-dns@${PROJECT_ID}.iam.gserviceaccount.com \
    --role=roles/iam.workloadIdentityUser \
    --member="serviceAccount:${PROJECT_ID}.svc.id.goog[external-dns/external-dns]"
```

### 6. GitHub Container Registry Credentials

Store GHCR credentials in Secret Manager for the control-plane image pull:

```bash
echo -n "your-github-username" | gcloud secrets create control-plane-ghcr-username --data-file=-
echo -n "ghp_your_token" | gcloud secrets create control-plane-ghcr-token --data-file=-
```

### 7. Fork and Configure Repository

```bash
# Fork this repo, then update the repoURL in:
#   - argocd/hub-bootstrap.yaml
#   - argocd/applicationsets/*.yaml

# Create your cluster config
cp clusters/minimal/config.yaml clusters/my-cluster/config.yaml
# Edit clusters/my-cluster/config.yaml with your values
```

---

## Hub Cluster Setup

The hub cluster runs ArgoCD and manages all spoke clusters.

### 1. Install ArgoCD

```bash
# Switch to hub cluster context
kubectl config use-context <hub-cluster-context>

# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

### 2. Login to ArgoCD CLI

```bash
# Port-forward (or use ingress if configured)
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Login
argocd login localhost:8080 --username admin --password <password-from-above>
```

---

## Spoke Cluster Setup

Repeat these steps for **each cluster that will run workloads** (including the hub itself).

### 1. Register Cluster with ArgoCD

From the hub cluster:

```bash
# For REMOTE spoke clusters:
argocd cluster add <spoke-context-name> --name <cluster-name>

# Get the server URL for your config.yaml
argocd cluster list
```

> **Hub as spoke**: If deploying apps to the hub cluster itself, skip this step. The hub is already registered as `in-cluster` with server URL `https://kubernetes.default.svc`.

### 2. Create Bootstrap Secrets

On the **target cluster** (spoke, or hub if self-managing):

```bash
# Switch to target cluster context (skip if already on hub for hub-as-spoke)
kubectl config use-context <cluster-context>

# External Secrets credentials (reads from GCP Secret Manager)
kubectl create namespace bootstrap-secrets
kubectl create secret generic gcpsm-secret -n bootstrap-secrets \
    --from-file=secret-access-credentials=.keys/external-secrets-sa.json

# Crossplane credentials (manages GCP resources)
kubectl create namespace crossplane-system
kubectl create secret generic gcp-credentials -n crossplane-system \
    --from-file=creds=.keys/crossplane-sa.json

# Verify
kubectl get secret gcpsm-secret -n bootstrap-secrets
kubectl get secret gcp-credentials -n crossplane-system
```

### 3. Update Cluster Config

Edit `clusters/<name>/config.yaml` with the cluster's values:

```yaml
cluster:
  name: my-cluster                              # Must match ArgoCD cluster name
  server: https://1.2.3.4                       # From 'argocd cluster list'
                                                # Use https://kubernetes.default.svc for hub-as-spoke

gcp:
  project: my-gcp-project
  region: us-west1
  network: default

dns:
  baseDomain: my-cluster.example.com
  zoneName: my-cluster-zone                     # Cloud DNS zone name

apps:
  controlPlane:
    enabled: true
    host: app.my-cluster.example.com
    image: ghcr.io/connecteverything/control-plane:1.8.1
  nats:
    enabled: true
    host: nats.my-cluster.example.com
    replicas: 3
  mimir:
    enabled: true

certManager:
  email: admin@example.com
  issuer: letsencrypt-prod
```

---

## Deploy

After completing prerequisites, hub setup, and spoke setup:

```bash
# Switch to hub cluster
kubectl config use-context <hub-cluster-context>

# Apply the bootstrap app
kubectl apply -f argocd/hub-bootstrap.yaml

# Watch apps deploy
kubectl get applications -n argocd -w
```

---

## Adding a New Cluster

1. Complete [Spoke Cluster Setup](#spoke-cluster-setup) for the new cluster
2. Create `clusters/<name>/config.yaml`
3. Commit and push - ApplicationSets auto-discover and deploy

---

## Repository Structure

```
clusters/
  minimal/
    config.yaml           # All cluster-specific values

base/                     # Shared Kustomize bases
  cert-manager/
  control-plane/
  crossplane/
  external-secrets/
  nats/

argocd/
  hub-bootstrap.yaml      # Bootstrap app for hub
  applicationsets/
    infrastructure.yaml   # cert-manager, crossplane, external-secrets, external-dns
    applications.yaml     # nats, mimir, control-plane
```

## Sync Waves

| Wave | Components |
|------|------------|
| 0 | cert-manager, cert-manager-issuers |
| 1 | crossplane, external-secrets, external-dns |
| 2 | crossplane-provider + provider-config, external-secrets-stores |
| 3 | nats, mimir |
| 4 | control-plane |

---

## Troubleshooting

### ApplicationSet Status

```bash
kubectl get applicationsets -n argocd
kubectl describe applicationset <name> -n argocd
```

### Generated Applications

```bash
kubectl get applications -n argocd
kubectl describe application <cluster>-<app> -n argocd
```

### Crossplane Provider Issues

```bash
kubectl get providers.pkg.crossplane.io
kubectl describe provider provider-gcp-sql
kubectl get providerrevisions
```

### External Secrets Issues

```bash
kubectl describe clustersecretstore gcpsm-cluster-store
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

### Certificate Issues

```bash
kubectl get certificates -A
kubectl describe certificate <name> -n <namespace>
kubectl get certificaterequests -A
```

---

## Validation

```bash
make validate  # Validates all Kustomize bases and cluster configs
```

## License

MIT
