/**
 * AWS Instance
 * ============
 * This is an module to creates a DC/OS AWS Instance.
 *
 * If `ami` variable is not set. This module uses the mesosphere suggested OS
 * which also includes all prerequisites.
 *
 * Using you own AMI
 * -----------------
 * If you choose to use your own AMI please make sure the DC/OS related
 * prerequisites are met. Take a look at https://docs.mesosphere.com/1.11/installing/ent/custom/system-requirements/install-docker-RHEL/
 *
 * EXAMPLE
 * -------
 *
 *```hcl
 * module "dcos-master-instance" {
 *   source  = "terraform-dcos/instance/aws"
 *   version = "~> 0.3.0"
 *
 *   cluster_name = "production"
 *   subnet_ids = ["subnet-12345678"]
 *   security_group_ids = ["sg-12345678"]
 *   hostname_format = "%[3]s-master%[1]d-%[2]s"
 *   ami = "ami-12345678"
 *
 *   extra_volumes = [
 *     {
 *       size        = 100
 *       type        = "gp2"
 *       iops        = null
 *       device_name = "/dev/xvdi"
 *     },
 *     {
 *       size        = 1000
 *       type        = ""      # Use AWS default.
 *       iops        = 0       # Use AWS default.      
 *       device_name = "/dev/xvdj"
 *     }
 *   ]
 * }
 *```
 */

provider "aws" {
}

data "aws_region" "current" {
}

// If name_prefix exists, merge it into the cluster_name
locals {
  cluster_name = var.name_prefix != "" ? "${var.name_prefix}-${var.cluster_name}" : var.cluster_name
  region       = var.region != "" ? var.region : data.aws_region.current.name
}

module "dcos-tested-oses" {
  source = "../terraform-aws-tested-oses"

  providers = {
    aws = aws
  }

  os = var.dcos_instance_os
}

resource "aws_instance" "instance" {
  instance_type = var.instance_type
  ami           = coalesce(var.ami, module.dcos-tested-oses.aws_ami)

  count                       = var.num
  key_name                    = var.key_name
  vpc_security_group_ids      = var.security_group_ids
  associate_public_ip_address = var.associate_public_ip_address
  iam_instance_profile        = var.iam_instance_profile

  subnet_id = element(var.subnet_ids, count.index % length(var.subnet_ids))

  tags = merge(
    var.tags,
    {
      "Name" = format(
        var.hostname_format,
        count.index + 1,
        local.region,
        local.cluster_name,
      )
      "Cluster"           = var.cluster_name
      "KubernetesCluster" = var.cluster_name
    },
  )

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = var.root_volume_type
    delete_on_termination = true
  }

  volume_tags = merge(
    var.tags,
    {
      "Name" = format(
        "root-volume-${var.hostname_format}",
        count.index + 1,
        local.region,
        local.cluster_name,
      )
      "Cluster" = var.cluster_name
    },
  )

  user_data         = var.user_data
  get_password_data = var.get_password_data

  lifecycle {
    ignore_changes = [
      user_data,
      ami,
    ]
  }
}
/*
data "aws_instance" "created" {
  count = var.num
  
  filter {
    name = "tag:Name"
    values = [format(
        var.hostname_format,
        count.index + 1,
        local.region,
        local.cluster_name,
    )]
  }
  
  filter {
    name = "tag:Cluster"
    values = [var.cluster_name]
  }

  filter {
    name = "tag:KubernetesCluster"
    values = [var.cluster_name]
  }
}
*/
locals {
  instance_extravolume_list = length(var.extra_volumes) > 0 ? flatten([
    for instance in aws_instance.instance: [
      for volume in var.extra_volumes[*] : {
        "${index(aws_instance.instance, instance) + 1}-${volume.device_name}" = {
          "instance"          = instance.id
          "availability_zone" = instance.availability_zone
          "device_name"       = volume.device_name
	  "iops"              = volume.iops
	  "size"              = volume.size
	  "type"              = volume.type
        }
      }
    ]
  ]) : null
  
  instance_extravolume = local.instance_extravolume_list == null ? {} : {for item in local.instance_extravolume_list: keys(item)[0] => values(item)[0]}
}

/*
output "instance_extravolume_output" {
  value = local.instance_extravolume
}
*/
 
resource "aws_ebs_volume" "volume" {
  # Extra volumes are grouped by instance first. For example:
  # - 1-volume1 (instance 0)
  # - 1-volume2 (instance 0)
  # - 2-volume1 (instance 1)
  # - 2-volume2 (instance 1)
  # - 3-volume1 (instance 2)
  # - 3-volume2 (instance 2)

  for_each = local.instance_extravolume  
  availability_zone = each.value.availability_zone

  size = lookup(
    each.value,
    "size",
    "120",
  )
  type = lookup(
    each.value,
    "type",
    "",
  )
  iops = lookup(
    each.value,
    "iops",
    "0",
  )

  tags = merge(
    var.tags,
    {
      "Name" = format(
        var.extra_volume_name_format,
        var.cluster_name,
        each.key,
      )
      "Cluster" = var.cluster_name
    },
  )

}

resource "aws_volume_attachment" "volume-attachment" {
  for_each = local.instance_extravolume
  
  device_name = each.value.device_name
  volume_id = aws_ebs_volume.volume[each.key].id
  instance_id = each.value.instance_id
  
  force_detach = true

  lifecycle {
    ignore_changes = [
      instance_id,
      volume_id,
    ]
  }
}

