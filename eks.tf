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

  node_security_group_enable_recommended_rules = false
  node_security_group_additional_rules = {
    all-vpc-ingress = {
      description = "All VPC traffic"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = [local.vpc_cidr]
      type        = "ingress"
    }
    all-egress = {
      description = "All traffic"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
      type        = "egress"
    }
  }

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
        # Enable passwordless SSH
        # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-start.html#efa-start-passwordless
        cat > ~/.ssh/config <<-EOF
        Host *
            ForwardAgent yes
        Host *
            StrictHostKeyChecking no
        EOF

        echo '${module.key_pair.private_key_openssh}' > ~/.ssh/id_rsa
        echo '${module.key_pair.public_key_openssh}' > ~/.ssh/id_rsa.pub
        cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/*

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
      max_size     = 2
      desired_size = 2
    }
    efa-2 = {
      subnet_ids = [aws_subnet.lz["two"].id]
    }
  }

  tags = local.tags
}

################################################################################
# SSH Key Pair
################################################################################

module "key_pair" {
  source  = "terraform-aws-modules/key-pair/aws"
  version = "~> 2.0"

  key_name           = "deployer-one"
  create_private_key = true

  tags = local.tags
}
