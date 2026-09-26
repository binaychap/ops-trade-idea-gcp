# Ops Trade Idea — GCP infrastructure (Terraform)

Provisions the [ops-paper-trade](https://github.com/binaychap/ops-paper-trade)
bot on Google Cloud's always-free tier: an `e2-micro` VM in `us-central1`,
opens port 8000, clones the bot repo, writes `.env` from Terraform variables,
and runs the bot as a systemd service (starts on boot, restarts on failure).

Stays at $0/month as long as you keep the free-tier guardrails below.

**Deploys run automatically from GitHub**: pushing to `main` plans and
applies via GitHub Actions. No service-account keys anywhere — auth uses
Workload Identity Federation.

## One-time setup

1. Install the [gcloud CLI](https://cloud.google.com/sdk/docs/install) and log in:
   ```bash
   gcloud auth login
   ```
2. Run the setup script (creates the service account, Workload Identity
   Pool, IAM bindings, and the Terraform state bucket):
   ```bash
   PROJECT_ID=your-gcp-project-id ./scripts/setup-wif.sh
   ```
3. Add the printed values as repo secrets
   (repo → **Settings → Secrets and variables → Actions**):
   - `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_SERVICE_ACCOUNT` (required)
   - `OPTIONOMICS_API_KEY`, `OPTIONOMICS_EMAIL`, `WEBULL_APP_KEY`,
     `WEBULL_APP_SECRET`, `IOS_API_KEY` (optional; empty disables the feature)

That's it. Push to `main` and watch the **Actions** tab.

## How it works

- `.github/workflows/terraform.yml`: on every push to `main`, authenticates
  to GCP via WIF (`google-github-actions/auth`), runs `terraform init`,
  `plan`, then `apply`. Pull requests only run `plan`.
- `main.tf`: provider, `e2-micro` VM, firewall rule for port 8000.
  State lives in the `ops-trade-idea-tfstate` GCS bucket (created by the
  setup script).
- `variables.tf`: all bot settings; secrets marked `sensitive` and fed from
  `TF_VAR_*` env vars in the workflow (which read GitHub Secrets).
- `startup.sh.tftpl`: first-boot script — installs uv, clones the bot repo,
  writes `.env`, enables the systemd service.
- `outputs.tf`: public IP, dashboard URL, SSH command.

## Local runs

```bash
cp terraform.tfvars.example terraform.tfvars   # fill in project_id + secrets
gcloud auth application-default login
terraform init
terraform plan
terraform apply
```

## Free-tier guardrails (stay at $0)

- Machine type stays `e2-micro`, zone stays in `us-central1` — changing
  either bills you.
- Boot disk stays 10 GB `pd-standard` (30 GB-mo free).
- Uses the auto-assigned ephemeral IP (720 free hrs/mo per account).
  Do NOT reserve a static IP without attaching it (~$7/mo).
- Outbound data stays under 1 GB/mo (bot polling + dashboard is far below).
- Set a $1 budget alert in Cloud Billing after first deploy.

## Notes

- `DRY_RUN` defaults to `true`. The bot only submits paper orders.
- `terraform.tfvars` is gitignored. Only `terraform.tfvars.example` (no
  secrets) is committed.
- To tear down: run the workflow with `terraform destroy` — or from your
  Mac after `terraform init`: `terraform destroy`.
