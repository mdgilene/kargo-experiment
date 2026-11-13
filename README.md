# Kargo Release Orchestration Research

Kargo + Argo CD + Helm, using an **app-of-apps** layout. Everything in this repo is versioned
together with semver git tags (`vX.Y.Z`); a tag is the unit Kargo promotes.

## Layout (on `main`)

| Path | Purpose |
|---|---|
| `charts/hello-world`, `charts/hello-api` | Helm charts (Argo Rollouts blue/green, smoke test as pre-promotion analysis) |
| `stages/<env>/<app>.yaml` | Per-environment Helm values for each app |
| `apps/<env>/<app>.yaml` | Child Argo CD `Application` manifests for that environment |
| `argocd/root-<env>.yaml` | Root (app-of-apps) Application per environment; apply once with `kubectl` |
| `kargo/` | Kargo `Project`, `Warehouse`, `Stage`s and the E2E `AnalysisTemplate`s |

## How a release flows

1. Tag the repo (`git tag -a vX.Y.Z`, bump `version` in both `Chart.yaml` files) and push.
2. The Warehouse creates Freight for the tag; `dev` auto-promotes, then `staging`, then `prod`.
3. Each stage builds its `stage/<env>` branch from the tagged commit: `charts/`, `values/`, `apps/`.
4. `root-<env>` (tracking `stage/<env>`) deploys the child apps; Kargo syncs the root, then each child.
5. `staging` runs the E2E suites (`kargo/analysis-e2e*.yaml`) as Kargo verification.

## Ports (kind)

`hello-world` is exposed on NodePorts 32080 (dev), 32081 (staging), 32082 (prod).
`hello-api` is ClusterIP only; use `kubectl port-forward`.
