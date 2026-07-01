locals {
  github_enabled = contains(var.ci_platforms, "github")
  gitlab_enabled = contains(var.ci_platforms, "gitlab")

  idcs_endpoint = trimsuffix(data.oci_identity_domains.domain.domains[0].url, ":443")

  github_sub_claims = concat(
    [for repo in try(var.github.repositories, []) : "repo:${repo}:ref:refs/heads/${var.github.branch}"],
    [for repo in try(var.github.repositories, []) : "repo:${repo}:pull_request"]
  )

  github_repo_names = toset(local.github_enabled && var.github.create_secrets ? [for repo in try(var.github.repositories, []) : split("/", repo)[1]] : [])

  gitlab_sub_claims = try(var.gitlab.issuer, "") == "" ? [] : [
    for project in var.gitlab.projects :
    "project_path:${project}:ref_type:${var.gitlab.ref_type}:ref:${var.gitlab.ref}"
  ]

  gitlab_audience = try(var.gitlab.audience, null)


  ci_oidc_config_json = jsonencode({
    oci_idcs_endpoint  = local.idcs_endpoint
    oci_client_id      = oci_identity_domains_app.oci_app.name
    oci_client_secret  = oci_identity_domains_app.oci_app.client_secret
    oci_region         = var.oci_region
    oci_tenancy_id     = oci_identity_domains_app.oci_app.tenancy_ocid
    oci_compartment_id = var.oci_compartment_id
  })
}
