# Synadia Control Plane

Synadia Control Plane deployment with PostgreSQL backend and TLS certificates.

## Components

- **Deployment**: Runs the control-plane container (ghcr.io/connecteverything/control-plane:1.8.1)
- **Service**: Exposes ports 80 and 443
- **Ingress**: HTTPS access via app.iamusingtheinternet.com
- **Certificate**: TLS certificate from Let's Encrypt via cert-manager
- **PostgreSQL**: Cloud SQL database provisioned via Crossplane
- **PVC**: Persistent storage for application data
- **Image Pull Secret**: GitHub Container Registry authentication via ExternalSecret

## Prerequisites

1. **cert-manager**: For TLS certificate generation
2. **Crossplane with GCP Provider**: For PostgreSQL database provisioning
3. **External Secrets Operator**: For syncing secrets from GCP Secret Manager
4. **Ingress Controller**: (e.g., nginx-ingress) for external access
5. **DNS**: app.iamusingtheinternet.com pointing to your ingress controller
6. **GitHub Container Registry Credentials**: Stored in GCP Secret Manager (see main README bootstrap section)

All prerequisites and secret creation steps are covered in the main [README.md](../../../README.md#bootstrap-instructions).

## PostgreSQL Setup

The PostgreSQL database is automatically provisioned via Crossplane:

- **Instance**: `control-plane-db` (Cloud SQL PostgreSQL 16, ENTERPRISE edition)
- **Database**: `scpdata`
- **User**: `scp` (password auto-generated and stored in GCP Secret Manager)
- **Connection**: Private IP only (no public access)
- **Region**: us-west1

### How It Works

1. **Crossplane Resources**: The `postgres.yaml` file defines Crossplane custom resources (DatabaseInstance, Database, User)
2. **ArgoCD Applies**: When control-plane app syncs, ArgoCD applies these resources to Kubernetes
3. **Crossplane Provisions**: Crossplane's GCP provider controller detects these resources and provisions real infrastructure in GCP
4. **Connection Secret**: Crossplane creates a secret `control-plane-db-connection` with connection details
5. **DSN Job**: A post-sync job constructs the proper DSN format from the Crossplane secret

**Dependency**: Crossplane and the GCP provider must be installed before this app (handled by sync wave 4 > wave 2).

## KMS Key Setup

The KMS encryption key is automatically generated and managed:

1. **Pre-sync Job**: Generates a 32-byte random key on first deployment
2. **GCP Secret Manager**: Stores the key as `control-plane-kms-key`
3. **ExternalSecret**: Syncs the key from GCP to Kubernetes
4. **Format**: `base64key://KEY` (256-bit key for database encryption)

The key is automatically generated only if it doesn't exist, ensuring it persists across deployments.

## Configuration

### Update Domain

Edit the following files to use your domain:

1. `configmap.yaml` - Update `server.url`
2. `certificate.yaml` - Update `dnsNames`
3. `ingress.yaml` - Update `host` and `tls.hosts`

### Update PostgreSQL Settings

Edit `postgres.yaml` to adjust:
- Instance size (`tier`)
- Disk size (`diskSize`)
- Region (`region`)
- Backup settings

### KMS Key Configuration

The KMS key is automatically generated and stored in GCP Secret Manager. No manual configuration needed.

To use GCP KMS instead of a base64 key, update `configmap.yaml`:

```yaml
kms:
  key_url: "gcpkms://projects/PROJECT_ID/locations/LOCATION/keyRings/RING/cryptoKeys/KEY"
```

## Deployment Order

1. **KMS Key Generation** (PreSync hook) - Generates encryption key and stores in GCP Secret Manager
2. **Database Password Generation** (PreSync hook) - Generates database password and stores in GCP Secret Manager
3. **PostgreSQL Database** (via Crossplane) - Creates DB instance, database, and user
4. **ExternalSecrets** - Syncs KMS key, database password, and GHCR credentials from GCP to Kubernetes
5. **DSN Secret Job** (PostSync hook) - Constructs PostgreSQL connection string
6. **Certificate** (via cert-manager) - Issues TLS certificate
7. **Deployment** - Starts control-plane application

## Accessing the Application

Once deployed, access the control plane at:
- **URL**: https://app.iamusingtheinternet.com

## Monitoring

Check the deployment status:

```bash
# Check pods
kubectl get pods -n control-plane

# Check certificate
kubectl get certificate -n control-plane

# Check database
kubectl get databaseinstance control-plane-db -n control-plane

# Check ingress
kubectl get ingress -n control-plane

# View logs
kubectl logs -n control-plane -l app=control-plane
```

## Database Connection

The PostgreSQL DSN is automatically constructed and stored in the secret:

```bash
kubectl get secret control-plane-postgres-dsn -n control-plane -o jsonpath='{.data.postgres-dsn}' | base64 -d
```

## Troubleshooting

### Database not ready

Wait for Crossplane to provision the database (can take 5-10 minutes):

```bash
kubectl describe databaseinstance control-plane-db -n control-plane
```

### Certificate not issuing

Check cert-manager logs and certificate status:

```bash
kubectl describe certificate control-plane-tls -n control-plane
kubectl logs -n cert-manager -l app=cert-manager
```

### Pod not starting

Check if secrets exist:

```bash
kubectl get secret control-plane-tls -n control-plane
kubectl get secret control-plane-postgres-dsn -n control-plane
kubectl get secret control-plane-kms-key -n control-plane
kubectl get secret control-plane-db-password -n control-plane
kubectl get secret ghcr-credentials -n control-plane
```

### Image pull errors

Verify GitHub credentials are stored in GCP Secret Manager:

```bash
gcloud secrets versions access latest --secret=control-plane-ghcr-username
gcloud secrets versions access latest --secret=control-plane-ghcr-token
```

### DSN Secret not created

Re-run the job manually:

```bash
kubectl delete job create-postgres-dsn -n control-plane
# ArgoCD will recreate it on next sync
```

## Database Password Management

The PostgreSQL password is automatically generated and managed:

1. **Pre-sync Job**: Generates a secure random password on first deployment
2. **GCP Secret Manager**: Stores the password as `control-plane-db-password`
3. **ExternalSecret**: Syncs the password from GCP to Kubernetes
4. **Crossplane User**: References the secret to set the database user password

The password is automatically generated only if it doesn't exist, ensuring it persists across deployments.

### Manual Password Rotation

To rotate the database password:

```bash
# Generate a new password and add it as a new version
openssl rand -base64 32 | gcloud secrets versions add control-plane-db-password \
    --data-file=- \
    --project=YOUR_PROJECT_ID

# External Secrets will sync the new password within 1 hour (or force refresh)
kubectl annotate externalsecret control-plane-db-password -n control-plane \
    force-sync=$(date +%s) --overwrite

# Crossplane will automatically update the database user password
# The DSN job will need to re-run to update the connection string
kubectl delete job create-postgres-dsn -n control-plane
# ArgoCD will recreate it on next sync
```

## Security Notes

1. **Database Password**: Auto-generated and stored in GCP Secret Manager. Rotated manually as needed.
2. **Network Access**: PostgreSQL uses private IP only, accessible only from within the VPC.
3. **KMS Key**: Auto-generated 256-bit key stored in GCP Secret Manager. For production, consider using GCP KMS for key management.
4. **SSL Certificates**: Using Let's Encrypt. Consider using a commercial CA for production.
5. **Workload Identity**: Ensure the generator service accounts are bound to a GCP service account with Secret Manager admin permissions.

## Resource Requirements

- **CPU**: 100m request, 500m limit
- **Memory**: 256Mi request, 512Mi limit
- **Storage**: 10Gi PVC
- **Database**: db-f1-micro (adjust for production workload)
