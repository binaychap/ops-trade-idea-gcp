# Deployment and operations commands

Run the local commands below from this repository on your Mac. Commands marked
as VM commands must run inside the VM's SSH session.

## Names used by this project

- HCP Terraform organization: `ops-trade-idea`
- HCP Terraform workspace: `ops-trade-idea-gcp`
- Current default Git repository: `https://github.com/binaychap/ops-trade-idea.git`
- Current default VM name: `ops-trade-idea`
- Earlier deployed VM name: `ops-paper-trade`
- VM zone: `us-central1-a`
- Application directory on the VM: `/opt/ops-paper-trade`
- Application service name: `ops-paper-trade`

The directory and service names remain `ops-paper-trade` even when the repository
or VM name changes. Use `terraform output instance_name` and
`terraform output -raw ssh_command` to find the names for your deployed state.
Review the plan carefully if the configured VM name differs from the deployed name.

## 1. Check Terraform and sign in to HCP Terraform

This configuration requires Terraform 1.5 or newer:

```bash
terraform version
```

If your Mac still uses Terraform 1.4.6, upgrade the HashiCorp Homebrew package:

```bash
brew tap hashicorp/tap
brew upgrade hashicorp/tap/terraform
```

If that package is not installed:

```bash
brew install hashicorp/tap/terraform
```

Verify the version, then sign in:

```bash
terraform version
terraform login
```

For remote runs, select a compatible version in HCP Terraform under
**Workspace → Settings → General → Terraform Version**. Prefer matching the local
CLI version.

If `terraform plan` reports **Insufficient rights to generate a plan**, sign in
with an account that has access to this workspace. An environment token can
override the saved login; remove that override in your current terminal before
signing in again:

```bash
unset TF_TOKEN_app_terraform_io
terraform login
terraform plan
```

If access is still denied, a workspace administrator must grant your team
**Plan** access to plan, or **Write** access to apply, through the workspace's
**Settings → Team Access**. Google Cloud credentials do not control HCP access.

## 2. Choose where Terraform runs

### Local execution with HCP-hosted state

This option uses your Google login without downloading a service-account key.
In HCP Terraform, open **ops-trade-idea-gcp → Settings → General** and set
**Execution Mode** to **Local**. Keep the `cloud {}` block in `main.tf` so HCP
Terraform continues storing state.

Authenticate on your Mac:

```bash
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

Choose the Google account that has access to your GCP project and approve the
requested Google Cloud access. If the error says the `cloud-platform` scope was
not consented, repeat the login and approve that permission. If browser login
fails, follow the instructions from:

```bash
gcloud auth application-default login --no-browser
```

If your organization blocks consent, contact its administrator. A regular
`gcloud auth login` alone does not configure Application Default Credentials.

Local runs need local input variables; HCP workspace variables are not supplied
to them. Create the local file only if you do not already have one:

```bash
cp -n terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to set `project_id`, account numbers, and application
secrets. Keep it out of Git. You can also supply individual inputs as environment
variables, although entering secrets directly in commands may save them in shell
history:

```bash
TF_VAR_ios_api_key="..." TF_VAR_webull_app_key="..." terraform apply
```

### Remote execution in HCP Terraform

Local `gcloud` credentials are not available to a remote runner. Configure
application inputs in the workspace's **Variables** tab as Terraform variables;
mark secrets sensitive.

If service-account keys are permitted, configure this workspace variable:

| Setting   | Value                                               |
| --------- | --------------------------------------------------- |
| Category  | Environment variable                                |
| Key       | `GOOGLE_CREDENTIALS`                                |
| Value     | Full service-account JSON contents, not a file path |
| Sensitive | Enabled                                             |

For an existing downloaded key, copy compact JSON to your Mac clipboard
(`jq` must be installed):

```bash
jq -c . /path/to/service-account-key.json | pbcopy
```

Paste it into the variable value. Do not commit the key or share its contents.
If key creation is permitted and you need a key, the console path is
**IAM & Admin → Service Accounts → select account → Keys → Add key → Create new
key → JSON**. The service account also needs permissions for the infrastructure.

If GCP blocks key creation/download, use local execution above or configure
**Workload Identity Federation** for remote runs. Federation requires a GCP
identity pool and OIDC provider trusting HCP Terraform, trust restricted to your
organization/workspace, service-account impersonation permission, and appropriate
infrastructure permissions. Then set these HCP environment variables:

| Variable                            | Value                                                                                          |
| ----------------------------------- | ---------------------------------------------------------------------------------------------- |
| `TFC_GCP_PROVIDER_AUTH`             | `true`                                                                                         |
| `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL` | Your service-account email                                                                     |
| `TFC_GCP_WORKLOAD_PROVIDER_NAME`    | `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID` |

Remove manually configured `GOOGLE_CREDENTIALS` and
`GOOGLE_APPLICATION_CREDENTIALS` when using dynamic credentials. These three
variables alone do not create the GCP trust configuration. Follow the complete
[HashiCorp keyless setup guide](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/gcp-configuration).

## 3. Deploy

After configuring the execution mode, credentials, and input variables:

```bash
terraform init
terraform plan
terraform apply
```

Review the proposed changes and enter `yes` at the apply prompt only when you
want Terraform to perform them. Commit `.terraform.lock.hcl` to preserve provider
version selections. Re-run `terraform init` after changing modules or Terraform
settings.

The VM startup script deploys the application automatically:

1. Installs Git, curl, and the `uv` Python package manager.
2. Clones `var.repo_url` into `/opt/ops-paper-trade` if the checkout is absent.
3. Writes `.env` from Terraform inputs.
4. Runs `uv sync` to install application dependencies.
5. Creates and enables the `ops-paper-trade` systemd service, which runs:

```bash
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
```

`main.tf` passes `repo_url` into `startup.sh.tftpl` through
`metadata_startup_script`. Override the repository in `terraform.tfvars` if needed:

```hcl
repo_url = "https://github.com/YOUR_ACCOUNT/YOUR_REPO.git"
```

The script does not configure private GitHub repository authentication. Future
Git pushes do not trigger deployment, and the script does not pull updates into
an existing checkout.

Terraform's **Creation complete** message confirms infrastructure creation, not
application readiness. Startup installation can take additional time or fail;
check the logs below.

## 4. Get the dashboard and connect to the VM

On your Mac:

```bash
terraform output -raw dashboard_url
terraform output -raw external_ip
terraform output instance_name
terraform output -raw ssh_command
```

Open the dashboard URL in your browser. Copy and run the SSH command Terraform
prints. The command for the earlier deployment was:

```bash
gcloud compute ssh ops-trade-idea \
  --zone us-central1-a \
  --project <project-id>
```

Use your actual deployed VM name and project if different. You can also open
**Google Cloud Console → Compute Engine → VM instances** and click **SSH** next
to the VM.

## 5. View deployment and application logs

Run these inside the VM's SSH session:

```bash
# Follow startup/deployment progress
sudo journalctl -u google-startup-scripts.service -f

# Last 100 startup/deployment entries
sudo journalctl -u google-startup-scripts.service -n 100 --no-pager

# start and stop
sudo systemctl start ops-paper-trade
sudo systemctl stop ops-paper-trade

# Application status
sudo systemctl status ops-paper-trade

# Follow application logs
sudo journalctl -u ops-paper-trade -f

# Last 100 application entries
sudo journalctl -u ops-paper-trade -n 100 --no-pager
```

Press **Ctrl+C** to stop following logs; this does not stop the application.

For boot/startup output in the console, open **Compute Engine → VM instances →
select VM → Serial port 1 (console)**. This repository does not install a Cloud
Logging agent to forward application journal logs into **Logging → Logs Explorer**.

## 6. Stop and start the application

Inside the VM, stop the bot:

```bash
sudo systemctl stop ops-paper-trade
```

Disable the service's normal automatic startup:

```bash
sudo systemctl disable ops-paper-trade
```

Important: this project's VM startup script explicitly runs
`systemctl enable --now ops-paper-trade.service` on boot. Disabling the service
alone therefore does not keep it stopped across VM reboots while that script
remains configured. The bot stays stopped for the current boot after `stop`;
keeping it disabled across boots requires changing the startup script.

Enable and start the bot again:

```bash
sudo systemctl enable --now ops-paper-trade
```

To stop the entire VM, use **Google Cloud Console → Compute Engine → VM instances
→ select VM → Stop**. Starting the VM again runs its startup script, which starts
the bot. Stopping a VM does not delete its disks or other infrastructure.

## 7. Remove the infrastructure

Only when you intend to delete the resources managed by this Terraform workspace:

```bash
terraform destroy
```

Review the destruction plan before confirming. Deleting the VM can also delete
its boot disk and application data stored there; back up any data you need first.

## Authentication references

- [Google Application Default Credentials](https://docs.cloud.google.com/docs/authentication/provide-credentials-adc)
- [HCP Terraform GCP key credentials](https://support.hashicorp.com/hc/en-us/articles/4406586874387-How-to-set-up-Google-Cloud-GCP-credentials-in-HCP-Terraform)
- [HCP Terraform workspace permissions](https://developer.hashicorp.com/terraform/cloud-docs/users-teams-organizations/permissions/workspace)
