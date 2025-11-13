# Minimal Environment Configuration

This directory contains the configuration for the "minimal" environment.

## Configuration Reference: dns-config.yaml

The `dns-config.yaml` file serves as the **single source of truth** and reference for all environment-specific values:
- Base domain: `gcp.iamusingtheinternet.com`
- DNS zone name: `gcp-iamusingtheinternet`
- Control plane hostname: `app.gcp.iamusingtheinternet.com`
- NATS hostname: `nats.gcp.iamusingtheinternet.com`
- GCP project ID: `erik-sandbox-408216`

### When Creating a New Environment

1. **Update `dns-config.yaml`** with your environment's values
2. **Copy values to kustomization files** (each file has clear comments showing what to update):
   - `control-plane/kustomization.yaml` - 4 value replacements
   - `nats/kustomization.yaml` - 1 value replacement
   - `crossplane/provider/kustomization.yaml` - 1 value replacement
   - `external-secrets/stores/kustomization.yaml` - 1 value replacement
3. **Update `../../argocd-apps/external-dns.yaml`** - 3 value replacements (marked with ENVIRONMENT-SPECIFIC comments)

Each kustomization file has a clearly marked section showing exactly which values need updating.

## Environment-Specific Values

**Current values (minimal environment)** - defined in `dns-config.yaml`:

### DNS Configuration

**Files to update:**
- `control-plane/kustomization.yaml` - Patches for DNS names in Ingress and Certificate
- `nats/kustomization.yaml` - Patches for DNS names in Ingress and Certificate
- `../argocd-apps/external-dns.yaml` - Domain filter and zone filter

**Current values (minimal environment):**
- **DNS Zone**: `gcp.iamusingtheinternet.com`
- **Zone Name**: `gcp-iamusingtheinternet`
- **Control Plane**: `app.gcp.iamusingtheinternet.com`
- **NATS Monitoring**: `nats.gcp.iamusingtheinternet.com`

### GCP Project Configuration

**Files to update:**
- `control-plane/kustomization.yaml` - ServiceAccount annotation and DatabaseInstance network
- `crossplane/provider/kustomization.yaml` - ProviderConfig projectID
- `external-secrets/stores/kustomization.yaml` - ClusterSecretStore projectID
- `../argocd-apps/external-dns.yaml` - Google project ID

**Current value (minimal environment):**
- **Project ID**: `erik-sandbox-408216`

### External Secrets

**Files to update:**
- `external-secrets/stores/kustomization.yaml` - GCP project ID patch

### Cert Manager

**Files to update:**
- `cert-manager/clusterissuer.yaml` - Email address for Let's Encrypt

**Current value (minimal environment):**
- **Email**: `erik048@gmail.com`

## Kustomize Patch Strategy

DNS names are defined using kustomize patches to keep environment-specific values centralized in the `kustomization.yaml` files. The base resource files use placeholder values (`example.com`) which are replaced by the environment-specific patches.

### Example: Adding a new environment

```bash
# 1. Copy the minimal environment
cp -r environments/minimal environments/production

# 2. Update DNS names in kustomization files
# Edit environments/production/control-plane/kustomization.yaml
# Change: app.gcp.iamusingtheinternet.com → app.prod.iamusingtheinternet.com

# Edit environments/production/nats/kustomization.yaml
# Change: nats.gcp.iamusingtheinternet.com → nats.prod.iamusingtheinternet.com

# 3. Update GCP project ID in all kustomization.yaml files
# 4. Update external-dns in argocd-apps/external-dns.yaml
# 5. Create new root app pointing to environments/production
```

## Testing Configuration

Validate kustomize builds before committing:

```bash
# Test control-plane
kustomize build environments/minimal/control-plane

# Test nats
kustomize build environments/minimal/nats

# Test external-secrets stores
kustomize build environments/minimal/external-secrets/stores
```
