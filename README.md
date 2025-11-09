# 🚀 NATS + Mimir Stack - Complete GitOps Platform

Production-ready infrastructure for NATS messaging with observability, secret management, and infrastructure-as-code.

## ✨ What's New

This stack now includes:
- ✅ **Persistent Volumes** for NATS JetStream
- ✅ **External Secrets Operator** for cloud-native secret management
- ✅ **Crossplane/Terraform** for infrastructure as code (RDS, VPCs, etc.)

See [docs/new-features-quickstart.md](docs/new-features-quickstart.md) for details!

## 📚 Documentation - Start Here

| Document | What It Covers |
|----------|----------------|
| **[PROJECT-SUMMARY.md](PROJECT-SUMMARY.md)** | 👈 **START HERE** - Overview, architecture decisions |
| [QUICKSTART.md](QUICKSTART.md) | Quick reference for common operations |
| [docs/new-features-quickstart.md](docs/new-features-quickstart.md) | NEW: PVs, secrets, infrastructure |
| [docs/deployment.md](docs/deployment.md) | Complete deployment walkthrough |
| [docs/external-secrets-examples.md](docs/external-secrets-examples.md) | 8 secret management examples |
| [docs/infrastructure-management.md](docs/infrastructure-management.md) | RDS with Crossplane/Terraform |

## ⚡ Quick Start

```bash
# 1. Install ArgoCD
make install-argocd

# 2. Edit configuration files with your values
# - argocd/applicationset.yaml
# - environments/dev/kustomization.yaml
# - base/cert-manager/clusterissuer.yaml

# 3. Install cert-manager
make install-cert-manager

# 4. Deploy to dev
make deploy-dev

# 5. Configure DNS
make get-loadbalancer-ip
# Point nats-dev.example.com to the IP
```

## 🎯 What's Included

- NATS Cluster (HA, TLS, JetStream with persistent storage)
- Mimir (Metrics storage & alerts)
- External Secrets Operator (AWS/GCP/Azure/Vault)
- Crossplane (Infrastructure as code)
- NATS Management UI
- ArgoCD (GitOps)
- cert-manager (Let's Encrypt)
- Complete CI/CD pipeline

## 🛠️ Common Commands

```bash
make help              # Show all commands
make validate          # Validate manifests
make deploy-dev        # Deploy to dev
make test-nats         # Test NATS
make port-forward      # Access services locally
```

## 📁 Key Files

- `base/nats/statefulset-with-secrets.yaml` - NATS with PVs & secrets
- `base/external-secrets/helmrelease.yaml` - Secret management
- `docs/infrastructure-management.md` - RDS setup guide
- `Makefile` - All common operations

## 🚀 Next Steps

1. Read [PROJECT-SUMMARY.md](PROJECT-SUMMARY.md) 
2. Review [docs/new-features-quickstart.md](docs/new-features-quickstart.md)
3. Deploy to dev environment
4. Configure secrets & infrastructure
5. Test & promote to production

**Questions?** Everything is documented in the docs/ directory!
# nats-argocd-stack
