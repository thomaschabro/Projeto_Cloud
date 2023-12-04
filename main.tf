# =================== VPC ===================
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"

  backend "s3" {
    bucket = "thomaschabro-bucket"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "MinhaVPC"
  }
}

# =================== Subnets ===================
resource "aws_subnet" "subnet_public" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true  # Permite que instâncias na subnet recebam IPs públicos

  tags = {
    Name = "SubnetPublica"
  }
}

resource "aws_subnet" "subnet_public2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true  # Permite que instâncias na subnet recebam IPs públicos

  tags = {
    Name = "SubnetPublica2"
  }
}

resource "aws_subnet" "subnet_private_1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.101.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false  

  tags = {
    Name = "SubnetPrivada 1"
  }
}

resource "aws_subnet" "subnet_private_2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.102.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false  

  tags = {
    Name = "SubnetPrivada 2"
  }
}

# =================== Internet Gateway ===================
resource "aws_internet_gateway" "meu_igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "MeuIGW"
  }
}

# =================== Public Route Tables ===================
resource "aws_route_table" "route_table_public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.meu_igw.id
  }

  tags = {
    Name = "MinhaTabelaDeRotaPublica"
  }
}

resource "aws_route_table_association" "associacao_tabela_rota" {
  subnet_id          = aws_subnet.subnet_public.id
  route_table_id     = aws_route_table.route_table_public.id
}


# =================== Private Route Tables ===================
resource "aws_route_table" "route_table_private" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "MinhaTabelaDeRotaPrivada"
  }
}

resource "aws_route_table_association" "associacao_tabela_rota_privada_1" {
  subnet_id          = aws_subnet.subnet_private_1.id
  route_table_id     = aws_route_table.route_table_private.id
}

resource "aws_route_table_association" "associacao_tabela_rota_privada_2" {
  subnet_id          = aws_subnet.subnet_private_2.id
  route_table_id     = aws_route_table.route_table_private.id
}

# =================== Data Base ===================
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db_subnet_group"
  subnet_ids = [aws_subnet.subnet_private_1.id, aws_subnet.subnet_private_2.id]
}

resource "aws_security_group" "security_group_db" {
  name        = "SecurityGroupDB"
  description = "Security Group to access DB"
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }
}

resource "aws_db_instance" "db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       =  "db.t2.micro"
  db_name                 = "myDB"
  username                = "admin"
  password                = "123456789"

  backup_retention_period = 10
  backup_window           = "01:00-01:30"  

  maintenance_window = "Mon:02:00-Mon:04:30"

  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.id
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.security_group_db.id]
  multi_az             = false
}

# =================== Load Balencer ===================
resource "aws_security_group" "lb_sg" {
  name        = "lb_sg"
  description = "Allow incoming traffic on ports 80 and 443"
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "load_balancer_app" {
  name               = "loadbalencer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  enable_deletion_protection = false  # Defina como true se deseja proteção contra exclusão

  enable_cross_zone_load_balancing = true

  enable_http2 = true

  subnets = [aws_subnet.subnet_public.id, aws_subnet.subnet_public2.id]  # Substitua pelos IDs das suas sub-redes
}

resource "aws_lb_target_group" "tg_lb" {
  name     = "lb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id  # Substitua pelo ID da sua VPC

  health_check {
    path = "/healthcheck"
    protocol = "HTTP"
    timeout = 5
    interval = 10
    healthy_threshold = 2
    unhealthy_threshold = 2
  }

}

resource "aws_lb_listener" "listener_lb" {
  load_balancer_arn = aws_lb.load_balancer_app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_lb.arn
  }
}

# =================== Auto Scaling ===================
resource "aws_launch_template" "launch_template" {
  name = "thomas_launch_template"
  instance_type = "t2.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups            = [aws_security_group.lb_sg.id]
    subnet_id                  = aws_subnet.subnet_public2.id
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "EC2_thomas_template"
    }
  }

user_data = base64encode(<<-EOF
      #!/bin/bash
      sudo touch app.log 
      export DEBIAN_FRONTEND=noninteractive
  
      sudo apt -y remove needrestart
      echo "fez o needrestart" >> app.log
      sudo apt-get update
      echo "fez o update" >> app.log
      sudo apt-get install -y python3-pip python3-venv git
      echo "fez o install de tudo" >> app.log
  
      # Criação do ambiente virtual e ativação
      python3 -m venv /home/ubuntu/myappenv
      echo "criou o env" >> app.log
      source /home/ubuntu/myappenv/bin/activate
      echo "ativou o env" >> app.log
  
      # Clonagem do repositório da aplicação
      git clone https://github.com/ArthurCisotto/aplicacao_projeto_cloud.git /home/ubuntu/myapp
      echo "clonou o repo" >> app.log
  
      # Instalação das dependências da aplicação
      pip install -r /home/ubuntu/myapp/requirements.txt
      echo "instalou os requirements" >> app.log
  
      sudo apt-get install -y uvicorn
      echo "instalou o uvicorn" >> app.log
   
      # Configuração da variável de ambiente para o banco de dados
      export DATABASE_URL="mysql+pymysql://admin:123456789@${aws_db_instance.db.endpoint}/myDB"
      echo "exportou o url" >> app.log
  
      cd /home/ubuntu/myapp
      # Inicialização da aplicação
      uvicorn main:app --host 0.0.0.0 --port 80 
      echo "inicializou" >> app.log
    EOF
    )

  image_id = "ami-0fc5d935ebf8bc3bc"
}

resource "aws_autoscaling_group" "autoscaling_group" {
  name = "autoscaling_group"
  max_size = 8
  min_size = 2
  desired_capacity = 4

  launch_template {
    id = aws_launch_template.launch_template.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.tg_lb.arn]
  vpc_zone_identifier = [aws_subnet.subnet_public.id, aws_subnet.subnet_public2.id]

  health_check_type = "ELB"
  health_check_grace_period = 300
  force_delete = true

  tag {
    key = "Name"
    value = "EC2_thomas"
    propagate_at_launch = true
  }
}

# =================== Auto Scaling Policies ===================
resource "aws_autoscaling_policy" "scale_out_policy" {
  name = "scale_out_policy"
  autoscaling_group_name = aws_autoscaling_group.autoscaling_group.name
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = 1
  cooldown = 300
}

resource "aws_autoscaling_policy" "scale_in_policy" {
  name = "scale_in_policy"
  autoscaling_group_name = aws_autoscaling_group.autoscaling_group.name
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = -1
  cooldown = 300
}


# =================== Cloud Watch Alarms ===================
resource "aws_cloudwatch_metric_alarm" "scale_out_alarm" {
  alarm_name = "scale_out_alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "120"
  statistic = "Average"
  threshold = "70"
  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions = [aws_autoscaling_policy.scale_out_policy.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.autoscaling_group.name
  }
}

resource "aws_cloudwatch_metric_alarm" "scale_in_alarm" {
  alarm_name = "scale_in_alarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "120"
  statistic = "Average"
  threshold = "20"
  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions = [aws_autoscaling_policy.scale_in_policy.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.autoscaling_group.name
  }
}