provider "aws" {
    region = "ap-south-1"
    profile = "raktim"
}

# Generates RSA Keypair
resource "tls_private_key" "wpkey" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save Private key locally
resource "local_file" "localkey" {
  depends_on = [
    tls_private_key.wpkey,
  ]
  content  = tls_private_key.wpkey.private_key_pem
  filename = "wpkey.pem"
}

# Upload public key to create keypair on AWS
resource "aws_key_pair" "awskey" {
   depends_on = [
    tls_private_key.wpkey,
  ]
  key_name   = "wpkey"
  public_key = tls_private_key.wpkey.public_key_openssh
}

# Creating VPC for Wordpress

resource "aws_vpc" "wp_vpc" {
  cidr_block            = "192.168.0.0/16"
  enable_dns_support    = true
  enable_dns_hostnames  = true
  tags = {
    "Name" = "wp-vpc" 
  }
}

# Creating Public Subnet for Wordpress

resource "aws_subnet" "wp_public" {
  depends_on = [
    aws_vpc.wp_vpc,
  ]
  cidr_block              = "192.168.0.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.wp_vpc.id
  tags = {
    "Name" = "wp-public"
  }
}

# Creating Private Subnet for Wordpress

resource "aws_subnet" "wp_private" {
  depends_on = [
    aws_vpc.wp_vpc,
  ]
  cidr_block              = "192.168.1.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = false
  vpc_id                  = aws_vpc.wp_vpc.id
  tags = {
    "Name" = "wp-private"
  }
}

# Creating Internet Gateway for wordpress vpc

resource "aws_internet_gateway" "wp_ig" {
  depends_on = [
    aws_vpc.wp_vpc,
  ]
  vpc_id = aws_vpc.wp_vpc.id
  tags = {
    "Name" = "wp-ig"
  }
}

# Creating Elastic IP for Nat Gateway

resource "aws_eip" "wp_eip" {
  depends_on = [
    aws_internet_gateway.wp_ig,
  ]
  tags = {
    "Name" = "wp-eip"
  }
}

# Creating Nat Gateway for Database

resource "aws_nat_gateway" "wp_ng" {
  depends_on = [
    aws_eip.wp_eip,
    aws_subnet.wp_public,
  ]
  allocation_id = aws_eip.wp_eip.id
  subnet_id     = aws_subnet.wp_public.id
  tags = {
    "Name" = "wp-ng"
  }
}

# Creating Routing Table for Internet Gateway

resource "aws_route_table" "wp_rt" {
  depends_on = [
    aws_internet_gateway.wp_ig,
  ]
  vpc_id = aws_vpc.wp_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wp_ig.id
  }
  tags = {
    "Name" = "wp-rt"
  }
}

# Associating Routing Table with Public Subnet

resource "aws_route_table_association" "wp_rta" {
  depends_on = [
    aws_subnet.wp_public,
    aws_route_table.wp_rt,
  ]
  subnet_id      = aws_subnet.wp_public.id
  route_table_id = aws_route_table.wp_rt.id
}

# Creating Routing Table for NAT Gateway

resource "aws_default_route_table" "wp_drt" {
  depends_on = [
    aws_vpc.wp_vpc,
    aws_nat_gateway.wp_ng,
  ]
  default_route_table_id = aws_vpc.wp_vpc.main_route_table_id
  route {
    cidr_block      = "0.0.0.0/0"
    nat_gateway_id  = aws_nat_gateway.wp_ng.id
  }
  tags = {
    "Name" = "wp-drt"
  }
}

# Associating Routing Table with Private Subnet
resource "aws_route_table_association" "wp_drta" {
  depends_on = [
    aws_subnet.wp_private,
    aws_default_route_table.wp_drt,
  ]
  subnet_id      = aws_subnet.wp_private.id
  route_table_id = aws_default_route_table.wp_drt.id
}

# Security group for wordpress inside public subnet

resource "aws_security_group" "wordpress_sg" {
  depends_on = [
    aws_route_table_association.wp_rta,
  ]
  name        = "wordpress-sg"
  description = "Connection between client and Wordpress"
  vpc_id      = aws_vpc.wp_vpc.id

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "httpd"
    from_port   = 80
    to_port     = 80
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# Security group for mysql database inside private subnet

resource "aws_security_group" "mysql_sg" {
  depends_on = [
    aws_security_group.wordpress_sg,
    aws_route_table_association.wp_drta,
  ]
  name        = "mysql-sg"
  description = "Conncetion between wordpress and mysql"
  vpc_id      = aws_vpc.wp_vpc.id

  ingress {
    description = "mysql"
    from_port   = 3306
    to_port     = 3306
    protocol    = "TCP"
    security_groups = [aws_security_group.wordpress_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance for Database

resource "aws_instance" "Database" {
    depends_on = [
    aws_security_group.mysql_sg,
  ]

  ami           = "ami-0e306788ff2473ccb"
  instance_type = "t2.micro"
  key_name      = "wpkey"
  vpc_security_group_ids = [aws_security_group.mysql_sg.id]
  subnet_id       = aws_subnet.wp_private.id
  user_data       = <<EOT
  #!/bin/bash
  sudo yum update -y
  sudo amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
  sudo yum install -y mariadb-server
  sudo systemctl start mariadb
  sudo systemctl enable mariadb
  mysql -u root <<EOF
  CREATE USER 'wp-user'@'${aws_instance.Wordpress.private_ip}' IDENTIFIED BY 'wp@pass';
  CREATE DATABASE wp_db;
  GRANT ALL PRIVILEGES ON wp_db.* TO 'wp-user'@'${aws_instance.Wordpress.private_ip}';
  FLUSH PRIVILEGES;
  exit
  EOF
  EOT

  tags = {
    Name = "DBServer"
  }
}

# EC2 Instance for Wordpress

resource "aws_instance" "Wordpress" {
    depends_on = [
    aws_security_group.wordpress_sg,
  ]

  ami           = "ami-0e306788ff2473ccb"
  instance_type = "t2.micro"
  key_name      = "wpkey"
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_id       = aws_subnet.wp_public.id
  
  tags = {
    Name = "WPServer"
  }
}

resource "null_resource" "WP_Setup" {

depends_on = [
    aws_instance.Wordpress,
    aws_instance.Database,
  ]

connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.wpkey.private_key_pem
    host     = aws_instance.Wordpress.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2",
      "sudo yum install -y httpd php-gd",
      "wget https://wordpress.org/latest.tar.gz",
      "tar -xzf latest.tar.gz",
      "cp wordpress/wp-config-sample.php wordpress/wp-config.php",
      "sed -i 's/database_name_here/wp_db/g' wordpress/wp-config.php",
      "sed -i 's/username_here/wp-user/g' wordpress/wp-config.php",
      "sed -i 's/password_here/wp@pass/g' wordpress/wp-config.php",
      "sed -i 's/localhost/${aws_instance.Database.private_ip}/g' wordpress/wp-config.php",
      "sudo cp -r wordpress/* /var/www/html/",
      "sudo chown -R apache /var/www",
      "sudo chgrp -R apache /var/www",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd"
     ]
  }
}

// Finally opening WordPress in Chrome Browser

resource "null_resource" "ChromeOpen"  {
depends_on = [
    aws_instance.Wordpress,
    aws_instance.Database,
    null_resource.WP_Setup,
  ]

	provisioner "local-exec" {
	    command = "chrome  ${aws_instance.Wordpress.public_ip}"
  	}
}
