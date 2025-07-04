output "cluster_id" {
  value = aws_eks_cluster.anikettestproject.id
}

output "node_group_id" {
  value = aws_eks_node_group.anikettestproject.id
}

output "vpc_id" {
  value = aws_vpc.anikettestproject_vpc.id
}

output "subnet_ids" {
  value = aws_subnet.anikettestproject_subnet[*].id
}

