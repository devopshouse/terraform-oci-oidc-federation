# Example: Self-Hosted GitLab OIDC (Private JWKS Endpoint)

Sets up GitLab CI OIDC federation for a self-hosted GitLab instance that OCI IDCS cannot reach directly. The JWKS is hosted at a public OCI Object Storage URL as a workaround.

## Why this workaround is needed

OCI IDCS validates GitLab OIDC JWTs by fetching signing keys from `{issuer}/oauth/discovery/keys`. If your GitLab instance is on a private network (VPN, RFC 1918 address space, or internal-only DNS), IDCS cannot reach that endpoint and token validation fails silently.

The solution is to mirror the JWKS at a publicly accessible URL and set `gitlab.public_key_endpoint` to that URL.

## Step 1 — Fetch the JWKS from your GitLab instance

Run this from a machine that can reach your GitLab:

```bash
curl -fsSL https://gitlab.internal.example.com/oauth/discovery/keys -o gitlab-jwks.json
```

Verify the file contains a `keys` array with at least one RSA public key:

```bash
cat gitlab-jwks.json
# {"keys":[{"kty":"RSA","kid":"...","use":"sig",...}]}
```

> GitLab rarely rotates its signing keys, but it can happen after upgrades. When it does, repeat this step and re-upload the file (Step 3 or 4).

## Step 2 — Create an OCI Object Storage bucket

Pick a compartment and region where the bucket will live. The bucket must be reachable by OCI IDCS (i.e., publicly accessible).

**Using OCI CLI:**

```bash
oci os bucket create \
  --compartment-id <compartment-ocid> \
  --name gitlab-jwks \
  --region <region>
```

Choose one of the two access methods below.

---

## Option A — Public bucket

Make the bucket public so any object URL is readable without authentication.

```bash
oci os bucket update \
  --name gitlab-jwks \
  --public-access-type ObjectRead \
  --region <region>
```

Upload the JWKS file:

```bash
oci os object put \
  --bucket-name gitlab-jwks \
  --name gitlab-jwks.json \
  --file gitlab-jwks.json \
  --region <region>
```

The public URL follows this pattern:

```
https://objectstorage.<region>.oraclecloud.com/n/<namespace>/b/gitlab-jwks/o/gitlab-jwks.json
```

To get your namespace:

```bash
oci os ns get
```

Set `gitlab.public_key_endpoint` to this URL.

---

## Option B — Private bucket with a Pre-Authenticated Request (PAR)

Keep the bucket private and create a read-only PAR for the specific object. This is the recommended approach — it avoids exposing the entire bucket.

Upload the JWKS file to a private bucket:

```bash
oci os object put \
  --bucket-name gitlab-jwks \
  --name gitlab-jwks.json \
  --file gitlab-jwks.json \
  --region <region>
```

Create a PAR with no expiry (or a long expiry you will manage):

```bash
oci os preauth-request create \
  --bucket-name gitlab-jwks \
  --name gitlab-jwks-par \
  --access-type ObjectRead \
  --object-name gitlab-jwks.json \
  --time-expires 2099-12-31T23:59:59Z \
  --region <region>
```

The response includes `access-uri`. Construct the full URL:

```
https://objectstorage.<region>.oraclecloud.com<access-uri>
```

Set `gitlab.public_key_endpoint` to this URL. The PAR URL is the secret — treat it as one.

> **PAR expiry:** OCI does not notify when a PAR expires. Calendar-remind yourself to rotate it before `time-expires`. A IDCS validation failure is the first sign of an expired PAR.

---

## Step 3 — Key rotation

GitLab signing keys can change after version upgrades. When they do, OIDC validation fails and pipelines start getting `401 Unauthorized`.

To update the hosted JWKS:

```bash
# Re-fetch from GitLab
curl -fsSL https://gitlab.internal.example.com/oauth/discovery/keys -o gitlab-jwks.json

# Re-upload (same command as initial upload — overwrites the object)
oci os object put \
  --bucket-name gitlab-jwks \
  --name gitlab-jwks.json \
  --file gitlab-jwks.json \
  --region <region>
```

No Terraform changes are needed. OCI IDCS fetches the URL on each token validation, so the new keys take effect immediately.

---

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform apply
```

Store outputs as masked GitLab CI/CD variables (Settings → CI/CD → Variables):

```bash
terraform output -raw ci_oidc_config_json   # → OCI_OIDC_CONFIG variable
terraform output gitlab_oidc_audience       # → use in id_tokens.OCI_TOKEN.aud
```

## Pipeline authentication

The pipeline authentication steps are identical to the GitLab SaaS example. Copy [`../gitlab-only/gitlab-ci.yml`](../gitlab-only/gitlab-ci.yml) to `.gitlab-ci.yml` in your repository.
