provider "aws" {
  region = var.region
}

# -----------------------------
# VPC & Subnets (same VPC)
# -----------------------------
resource "aws_vpc" "aurora_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "aurora-repl-vpc" }
}

resource "aws_subnet" "subnet_a" {
  vpc_id            = aws_vpc.aurora_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.region}a"
}

resource "aws_subnet" "subnet_b" {
  vpc_id            = aws_vpc.aurora_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}b"
}

resource "aws_db_subnet_group" "aurora_subnet_group" {
  name       = "aurora-subnet-group"
  subnet_ids = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]
}

# -----------------------------
# Security Group
# -----------------------------
resource "aws_security_group" "aurora_sg" {
  name   = "aurora-sg"
  vpc_id = aws_vpc.aurora_vpc.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------
# Parameter Group for Logical Replication
# -----------------------------
resource "aws_rds_cluster_parameter_group" "aurora_params" {
  name        = "aurora-logical-repl"
  family      = "aurora-postgresql15"
  description = "Enable logical replication"

  parameters = [
    { name = "rds.logical_replication", value = "1" },
    { name = "wal_level", value = "logical" },
    { name = "max_replication_slots", value = "10" },
    { name = "max_wal_senders", value = "10" }
  ]
}

# -----------------------------
# Aurora Source Cluster
# -----------------------------
resource "aws_rds_cluster" "source_cluster" {
  cluster_identifier             = "aurora-source"
  engine                         = "aurora-postgresql"
  engine_version                 = "15.4"
  master_username                = var.master_username
  master_password                = var.master_password
  db_subnet_group_name           = aws_db_subnet_group.aurora_subnet_group.name
  vpc_security_group_ids         = [aws_security_group.aurora_sg.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora_params.name
  skip_final_snapshot            = true
}

resource "aws_rds_cluster_instance" "source_instance" {
  identifier         = "aurora-source-instance"
  cluster_identifier = aws_rds_cluster.source_cluster.id
  instance_class     = "db.t3.small"
  engine             = "aurora-postgresql"
  publicly_accessible = true
}

# -----------------------------
# Aurora Target Cluster
# -----------------------------
resource "aws_rds_cluster" "target_cluster" {
  cluster_identifier             = "aurora-target"
  engine                         = "aurora-postgresql"
  engine_version                 = "15.4"
  master_username                = var.master_username
  master_password                = var.master_password
  db_subnet_group_name           = aws_db_subnet_group.aurora_subnet_group.name
  vpc_security_group_ids         = [aws_security_group.aurora_sg.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora_params.name
  skip_final_snapshot            = true
}

resource "aws_rds_cluster_instance" "target_instance" {
  identifier         = "aurora-target-instance"
  cluster_identifier = aws_rds_cluster.target_cluster.id
  instance_class     = "db.t3.small"
  engine             = "aurora-postgresql"
  publicly_accessible = true
}

# -----------------------------
# Create Replicator User Automatically
# -----------------------------
resource "null_resource" "replicator_user" {
  depends_on = [aws_rds_cluster_instance.source_instance]

  provisioner "local-exec" {
    command = <<EOT
PGPASSWORD='${var.master_password}' psql "host=${aws_rds_cluster.source_cluster.endpoint} port=5432 user=${var.master_username} dbname=postgres sslmode=require" -c "CREATE ROLE replicator WITH LOGIN REPLICATION PASSWORD '${var.replication_password}'; GRANT rds_replication TO replicator;"
EOT
  }
}

output "source_endpoint" {
  value = aws_rds_cluster.source_cluster.endpoint
}

output "target_endpoint" {
  value = aws_rds_cluster.target_cluster.endpoint
}
