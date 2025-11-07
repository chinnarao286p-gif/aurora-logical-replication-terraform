output "source_endpoint" {
  value = aws_rds_cluster.source_cluster.endpoint
}

output "target_endpoint" {
  value = aws_rds_cluster.target_cluster.endpoint
}

output "replication_user" {
  value = "replicator"
}
