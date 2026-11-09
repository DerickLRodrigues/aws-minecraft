output "instance_id" { value = aws_instance.server.id }
output "root_volume_id" { value = aws_instance.server.root_block_device[0].volume_id }
output "minecraft_address" { value = "${aws_instance.server.public_ip}:25565" }
output "ssm_command" { value = "aws ssm start-session --region sa-east-1 --target ${aws_instance.server.id}" }
output "availability_zone" { value = aws_instance.server.availability_zone }
