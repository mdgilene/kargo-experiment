# Kargo Release Orchestration Research

This repository contains configuration and manifests for testing release orchestration using **Kargo**, **Argo CD**, and **Helm**.

## Directory Structure

- `charts/` — Helm charts and environment-specific values for the sample application(s).
- `argocd/` — Argo CD `Application` / `ApplicationSet` manifests used to deploy stages.
- `kargo/` — Kargo `Project`, `Warehouse`, and `Stage` manifests defining the promotion pipeline.
- `stages/` — Rendered or stage-specific GitOps configurations managed by Kargo promotions.
