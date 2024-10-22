provider "aws" {
  access_key = "ACCESSKEY"
  secret_key = "SECRETKEY"
  region     = "us-east-1"
}

resource "aws_s3_bucket" "oneton_bucket" {
  bucket = var.bucket_name
  acl    = "private"  # Set the ACL for the bucket
}

resource "aws_iam_role" "ec2_role" {
  name               = "ec2_s3_access_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      }
    ]
  })
}

resource "aws_iam_policy" "s3_access_policy" {
  name        = "s3_access_policy"
  description = "A policy to allow access to S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.oneton_bucket.arn,
          "${aws_s3_bucket.oneton_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  policy_arn = aws_iam_policy.s3_access_policy.arn
  role       = aws_iam_role.ec2_role.name
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_s3_object" "folder1" {
  bucket = aws_s3_bucket.oneton_bucket.id
  key    = "folder1/"
  content = ""  # Add an empty string for directory creation
  content_type = "application/x-directory"
}

resource "aws_s3_object" "folder2" {
  bucket = aws_s3_bucket.oneton_bucket.id
  key    = "folder2/"  # Corrected key from "folder/" to "folder2/"
  content = ""  # Add an empty string for directory creation
  content_type = "application/x-directory"
}

resource "aws_s3_object" "textfile1_in_folder1" {
  bucket = aws_s3_bucket.oneton_bucket.id
  key    = "folder1/file1.txt"
  content = "This is file1 in folder1"
  content_type = "text/plain"
}

resource "aws_s3_object" "textfile2_in_folder2" {
  bucket = aws_s3_bucket.oneton_bucket.id
  key    = "folder2/file2.txt"
  content = "This is file2 in folder2"
  content_type = "text/plain"
}


resource "aws_instance" "ec2_instance" {
  ami                    = var.ami_id
  instance_type         = var.instance_type
  security_groups       = [aws_security_group.TF_SG.name]
  key_name              = aws_key_pair.TF_key.key_name  # Use key_name reference
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name  # Attach IAM role

user_data = <<-EOF
    #!/bin/bash
    set -e  # Exit immediately if a command exits with a non-zero status

    # Update the package index
    sudo apt update -y

    # Install necessary packages
    sudo apt install -y nginx apt-transport-https ca-certificates curl software-properties-common python3-pip git

    # Start Nginx
    sudo systemctl start nginx
    sudo systemctl enable nginx

    # Clone the GitHub repository
    git clone -b main https://github.com/kaushik379/On2N.git /home/ubuntu/On2N

    # Navigate to the Python app directory and install dependencies
    cd /home/ubuntu/On2N/pythonapp
    pip3 install -r requirements.txt

    # Start the Python app in the background
    nohup python3 pythonapp.py > pythonapp.log 2>&1 &

    # Create a self-signed SSL certificate
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/nginx-selfsigned.key \
    -out /etc/ssl/certs/nginx-selfsigned.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

    # Add the self-signed certificate to the trusted certificates
    sudo cp /etc/ssl/certs/nginx-selfsigned.crt /usr/local/share/ca-certificates/nginx-selfsigned.crt
    sudo update-ca-certificates
    # Update the Nginx default server block
    sudo bash -c 'cat <<EOT > /etc/nginx/sites-available/default
    server {
      listen 443 ssl;
      server_name localhost;

      ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
      ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;

      location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
      }
    }
    EOT'

    # Restart Nginx to apply changes
    sudo systemctl restart nginx
EOF

  tags = {
    Name = var.instance_name
  }
}

resource "aws_security_group" "TF_SG" {
  name        = "TF_SG"
  description = "Allow SSH and HTTP inbound traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80    # Added HTTP port 80 for web traffic
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443   # HTTPS port
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # -1 allows all outbound traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "TF_key" {
  key_name   = "TF_key"
  public_key = tls_private_key.rsa.public_key_openssh
}

resource "tls_private_key" "rsa" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "TF_key" {
  content  = tls_private_key.rsa.private_key_pem
  filename = "tfkey"
}

output "ec2_public_ips" {
  value = aws_instance.ec2_instance.public_ip
}
