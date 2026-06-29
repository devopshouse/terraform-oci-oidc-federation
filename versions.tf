terraform {
  required_version = ">= 1.3.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0"
    }
    github = {
      source  = "integrations/github"
      version = ">= 6.0"
    }
  }
}
