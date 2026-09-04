# =====================================================================
# PROVIDER
#
# default_tags applies these to every resource this provider creates,
# which is why individual resources only carry a Name tag.
# =====================================================================

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
    }
  }
}
