# =====================================================================
# MAINTENANCE HOST
#
# Not an SSH bastion. The instance sits in a private subnet with no
# public address, no key pair and no inbound security group rules. The
# SSM agent dials out to Systems Manager, so access is authorised by IAM
# and recorded in CloudTrail rather than granted by possession of a key.
#
# It exists for two operator tasks:
#   - applying db/schema.sql, which is not baked into the application
#     image and therefore cannot be applied from the container
#   - reaching the internal load balancer to verify the request path
#
# It is a development convenience and is called out in the README as
# something that would not exist in a production account, where schema
# changes belong in a pipeline stage.
# =====================================================================

resource "aws_iam_role" "bastion" {
  name = "${var.name_prefix}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Grants the agent its channel to Systems Manager. This is what replaces
# opening port 22.
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# One secret ARN, matching the scope given to the ECS execution role.
# Letting the host fetch the connection string keeps the password out of
# shell history and out of the operator's clipboard.
resource "aws_iam_role_policy" "bastion_secret" {
  name   = "read-db-url-secret"
  role   = aws_iam_role.bastion.id
  policy = data.aws_iam_policy_document.read_db_secret.json
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.name_prefix}-bastion-profile"
  role = aws_iam_role.bastion.name
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.bastion_instance_type

  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  # No public address. Outbound traffic leaves through the NAT gateway,
  # which is all the SSM agent needs.
  associate_public_ip_address = false

  # Enforces IMDSv2, which removes the SSRF path to instance credentials.
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = 8
    encrypted   = true
  }

  user_data = templatefile("${path.module}/bastion-user-data.sh", {
    secret_arn = aws_secretsmanager_secret.db_url.arn
    region     = var.region
  })

  # Editing the script above replaces the instance rather than leaving a
  # host running a stale bootstrap.
  user_data_replace_on_change = true

  tags = { Name = "${var.name_prefix}-bastion" }
}
