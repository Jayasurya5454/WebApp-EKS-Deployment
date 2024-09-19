provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "tf-rp-states-jais"
    key    = "jayasuryamodel/terraform.tfstate"
    region = "us-east-1"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0" # Use the latest version

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_iam_role" "example" {
  name = "example-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKSClusterPolicy" {
  role      = aws_iam_role.example.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKSVPCResourceController" {
  role      = aws_iam_role.example.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_eks_cluster" "quotes_app_deploy" {
  name     = "quotes-app-deploy"
  role_arn = aws_iam_role.example.arn

  vpc_config {
    subnet_ids = module.vpc.private_subnets
  }

  depends_on = [
    aws_iam_role_policy_attachment.example-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.example-AmazonEKSVPCResourceController,
  ]
}

data "aws_eks_cluster_auth" "auth" {
  name = aws_eks_cluster.quotes_app_deploy.name
}

provider "kubernetes" {
  host                   = aws_eks_cluster.quotes_app_deploy.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.quotes_app_deploy.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.auth.token
}

resource "kubernetes_manifest" "quotes_deployment" {
  manifest = yamldecode(file("${path.module}/quotes-deployment.yaml"))
}

resource "kubernetes_manifest" "quotes_service" {
  manifest = yamldecode(file("${path.module}/quotes-service.yaml"))
}

output "endpoint" {
  value = aws_eks_cluster.quotes_app_deploy.endpoint
}

output "kubeconfig-certificate-authority-data" {
  value = aws_eks_cluster.quotes_app_deploy.certificate_authority[0].data
}

output "cluster_name" {
  value = aws_eks_cluster.quotes_app_deploy.name
}

output "quotes_service_ip" {
  value = kubernetes_manifest.quotes_service.manifest["status"]["loadBalancer"]["ingress"][0]["hostname"]
}
