provider "aws" {
  region = local.region
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.38"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.14"
    }
  }
}

################################################################################
# Common Locals
################################################################################

locals {
  name   = "eks-efa-test"
  region = "us-east-1"

  tags = {
    GithubRepo = "github.com/clowdhaus/aws-eks-efa-test"
  }
}
