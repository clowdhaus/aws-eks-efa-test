################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.19"

  cluster_name    = local.name
  cluster_version = "1.29"

  # To facilitate easier interaction for demonstration purposes
  cluster_endpoint_public_access = true

  # Gives Terraform identity admin access to cluster which will
  # allow deploying resources (Karpenter) into the cluster
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  # Add security group rules on the node group security group to allow EFA traffic
  enable_efa_support = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # Not required, but used in the example to access the nodes to inspect drivers and devices
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }

  eks_managed_node_groups = {
    # This node group is for core addons such as CoreDNS
    default = {
      instance_types = ["m6i.xlarge"]

      min_size     = 1
      max_size     = 2
      desired_size = 2
    }
  }

  self_managed_node_group_defaults = {
    # The EKS AL2 GPU AMI provides all of the necessary components
    # for accelerated workloads w/ EFA
    ami_type      = "AL2_x86_64_GPU"
    instance_type = "c6i.32xlarge"

    min_size     = 1
    max_size     = 1
    desired_size = 1

    pre_bootstrap_user_data = <<-EOT
        # RDMA perftest
        yum install git libtool pciutils-devel -y && \
          cd /opt && \
          git clone https://github.com/linux-rdma/perftest.git && \
          cd /opt/perftest && \
          ./autogen.sh && \
          ./configure && \
          make && \
          make install

        export KUBELET_EXTRA_ARGS='--node-labels=vpc.amazonaws.com/efa.present=true,nvidia.com/gpu.present=true \
          --register-with-taints=nvidia.com/gpu=true:NoSchedule'

      EOT

    # This will:
    # 1. Create a placement group for the node group to cluster instances together
    # 2. Filter out subnets that reside in AZs that do not support the instance type
    # 3. Expose all of the available EFA interfaces on the launch template
    enable_efa_support = true

    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }

  self_managed_node_groups = {
    efa-1 = {
      subnet_ids   = [aws_subnet.lz["one"].id]
      desired_size = 2
    }
    efa-2 = {
      subnet_ids = [aws_subnet.lz["two"].id]
    }
  }

  tags = local.tags
}
