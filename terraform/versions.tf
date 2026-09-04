# =====================================================================
# TERRAFORM AND PROVIDER VERSIONS
#
# No backend block: state is local. The reasoning is in the README.
# =====================================================================

terraform {
  required_version = ">= 1.12.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.62"
    }
  }
}
