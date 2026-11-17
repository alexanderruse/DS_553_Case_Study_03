# GCP Cloud Run

Create a project-scoped Billing budget and alerts before deployment. Authenticate
with `gcloud auth login`, then run from the repository root:

```bash
export GCP_PROJECT_ID="your-project-id"
export GCP_REGION="us-central1"
./cloud/gcp/deploy.sh
```

The script enables Cloud Run, Artifact Registry, and Cloud Build; builds
`Dockerfile.cloud`; limits Cloud Run to one instance; and prints the external
URL for the class Sheet.

Evidence to retain: budget thresholds, Artifact Registry image, Cloud Build
result, Cloud Run revision, public URL, successful synthetic review, and commit
hash.
