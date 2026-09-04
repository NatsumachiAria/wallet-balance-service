# =====================================================================
# DATA SOURCES — account/identity lookups used to build ARNs and hints
# =====================================================================

data "aws_caller_identity" "current" {}

# Latest Amazon Linux 2023 image, resolved at plan time instead of being
# pinned to an AMI id that goes stale and differs per region.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
