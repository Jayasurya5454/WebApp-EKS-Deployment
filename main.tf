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
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 3.14"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}
resource "aws_eip" "nat" {
  count = 3

  domain = "vpc"
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 14.0"
  cluster_version = "1.27"
  cluster_name    = "quotes-generator-cluster"
  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.private_subnets

  node_groups = {
    eks_nodes = {
      desired_capacity = 2
      max_capacity     = 3
      min_capacity     = 1
      instance_type    = "t2.micro"
    }
  }
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

resource "kubernetes_manifest" "quotes_deployment" {
  manifest = yamldecode(file("${path.module}/quotes-deployment.yaml"))
}

resource "kubernetes_manifest" "quotes_service" {
  manifest = yamldecode(file("${path.module}/quotes-service.yaml"))
}

output "quotes_service_ip" {
  value = kubernetes_manifest.quotes_service.manifest["status"]["loadBalancer"]["ingress"][0]["hostname"]
}
