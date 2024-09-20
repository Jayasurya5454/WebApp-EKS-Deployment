# main.tf

# ============================
# 1. Terraform Configuration
# ============================

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket         = "tf-rp-states-jais"          # Replace with your S3 bucket name
    key            = "jayasuryamodel/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"            # Ensure this table exists for state locking
  }
}

# ============================
# 2. Provider Configuration
# ============================

provider "aws" {
  region = "us-east-1"
}

# ============================
# 3. Variables Definition
# ============================

# Optional: Define variables if you plan to reuse or customize them
# For simplicity, values are hardcoded in this example

# ============================
# 4. VPC Module
# ============================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0" # Use the latest version

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true    # Use a single NAT Gateway to reduce costs
  enable_vpn_gateway   = true    # Enable VPN Gateway if required

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

# ============================
# 5. EKS Module
# ============================

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 18.0" # Use the latest version
  cluster_version = "1.27"
  cluster_name    = "quotes-generator-cluster"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  eks_managed_node_groups = {
    node_group = {
      min_size     = 2
      max_size     = 6
      desired_size = 2

      instance_type = "t3.medium"
      key_name      = "your-ssh-key-name" # Replace with your SSH key name

      # Optional: Additional node group configurations
      # e.g., additional_tags, disk_size, etc.
    }
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }

  # Optional: Enable additional EKS features if needed
}

# ============================
# 6. Data Sources for EKS Cluster
# ============================

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

# ============================
# 7. Kubernetes Provider Configuration
# ============================

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token

  # Ensure the Kubernetes provider is configured after the EKS cluster is ready
  depends_on = [module.eks]
}

# ============================
# 8. Kubernetes Resources
# ============================

# 8.1. Kubernetes Deployment
resource "kubernetes_manifest" "quotes_deployment" {
  manifest = yamldecode(file("${path.module}/quotes-deployment.yaml"))

  # Ensure the deployment is applied after the Kubernetes provider is ready
  depends_on = [provider.kubernetes]
}

# 8.2. Kubernetes Service
resource "kubernetes_manifest" "quotes_service" {
  manifest = yamldecode(file("${path.module}/quotes-service.yaml"))

  # Ensure the service is applied after the deployment is ready
  depends_on = [kubernetes_manifest.quotes_deployment]
}

# ============================
# 9. Data Source to Fetch Kubernetes Service
# ============================

data "kubernetes_service" "quotes_service" {
  metadata {
    name      = "quotes-service"
    namespace = "default" # Adjust if your service is in a different namespace
  }

  # Ensure the data source waits for the service to be created
  depends_on = [kubernetes_manifest.quotes_service]
}

# ============================
# 10. Outputs
# ============================

output "quotes_service_hostname" {
  description = "Hostname of the Quotes Service Load Balancer."
  value       = try(data.kubernetes_service.quotes_service.status[0].load_balancer[0].hostname, "Hostname not available yet.")
}

