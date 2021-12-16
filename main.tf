terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {

    region = "${var.region}"
    access_key = "${var.access_key}"
    secret_key = "${var.secret_key}"
}

#Creating VPC

resource "aws_vpc" "efs-vpc" { 

cidr_block=var.vpc_cidr_block

tags = {
     Name:"${var.env_prefix}-vpc"
}
}

#Creating Subnet1

resource "aws_subnet" "subnet_1_cidr" {

vpc_id=aws_vpc.efs-vpc.id
cidr_block=var.subnet_1_cidr
availability_zone=var.az_1

tags = {
     Name:"${var.env_prefix}-subnet1"
}

}

# Create Internet Gateway 

resource "aws_internet_gateway" "n-igw" {

vpc_id=aws_vpc.efs-vpc.id

tags = {
     Name:"${var.env_prefix}-igw"
}
}


#Creating Subnet2

resource "aws_subnet" "subnet_2_cidr" {

vpc_id=aws_vpc.efs-vpc.id
cidr_block=var.subnet_2_cidr
availability_zone=var.az_2
tags = {
     Name:"${var.env_prefix}-subnet2"
}
}

# Create Route Table 

resource "aws_route_table" "public-route" {
  vpc_id =  aws_vpc.efs-vpc.id
  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.n-igw.id
  }

   tags = {
     Name:"${var.env_prefix}-rt1"
}
}

# Route table association

resource "aws_route_table_association" "a" {
  subnet_id      = ["aws_subnet.subnet_1_cidr.id","aws_subnet.subnet_2_cidr.id"]
  route_table_id = aws_route_table.public-route.id
}

# the instances over SSH and HTTP
resource "aws_security_group" "web-sg" {
  name        = "instance_sg"
  description = "Used in the terraform"
  vpc_id=aws_vpc.efs-vpc.id
  
  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # NFS access from anywhere
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



resource  "aws_instance" "wordpress-host" {

ami = "${var.image_id}"
instance_type = "t2.micro"
key_name = "awsautomation"
vpc_id =  aws_vpc.efs-vpc.id
subnet_id = aws_subnet.subnet_1_cidr.id
availability_zone=var.az_1
associate_public_ip_address = true
vpc_security_group_ids = [aws_security_group.web-sg.id]
key_name = "test-web"
user_data = <<-EOF

      #!/bin/bash
      sudo yum update -y
      sudo amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
      sudo yum install -y httpd mariadb-server
      cd /var/www/html
      sudo echo "healthy" > healthy.html
      sudo wget https://wordpress.org/latest.tar.gz
      sudo tar -xzf latest.tar.gz
      sudo cp -r wordpress/* /var/www/html/
      sudo rm -rf wordpress
      sudo rm -rf latest.tar.gz
      sudo chmod -R 755 wp-content
      sudo chown -R apache:apache wp-content
      sudo service httpd start
      sudo chkconfig httpd on

      EOF


    tags = {
      Name = "test-Wordpress-Server"
    }
} 





resource "aws_efs_file_system" "myefs" {
depends_on = [ aws_security_group.web-sg,aws_instance.wordpress-host ]
creation_token = "my_nfs"

  tags = {
    Name = "My efs"
  }
}

resource "aws_efs_mount_target" "myefsmount1" {
  depends_on = [aws_efs_file_system.myefs]
  file_system_id = aws_efs_file_system.myefs.id
  subnet_id      = aws_subnet.subnet_1_cidr.id
  security_groups = [aws_security_group.web-sg.id]
}

resource "null_resource" "ec2_mount" {
  depends_on = [aws_efs_mount_target.myefsmount1]
  connection {
    type = "ssh"
    user = "ec2-user"
    key_name = "awsautomation"
    host = aws_instance.wordpress-host[0].public_ip
  }

  provisioner "remote-exec" {
    inline = [
	  "sudo yum install git httpd -y",
      "sudo mount -t nfs4 -${aws_efs_mount_target.ip_address}:/ /var/www/html/",
	  "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Reshmitp/reshmiterraform /var/www/html",
      "sudo mv /var/www/html/high-availability_efs/* /var/www/html/",
      "sudo systemctl start httpd"
    ]
  }
