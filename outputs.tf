output "server_address" {
  description = "Address to enter in Minecraft's multiplayer menu."
  value       = aws_eip.minecraft.public_ip
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.minecraft.id
}

output "ssm_connect_command" {
  description = "Open a shell on the server via SSM Session Manager."
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.minecraft.id}"
}

output "data_volume_id" {
  description = "EBS volume holding the world data."
  value       = aws_ebs_volume.data.id
}
