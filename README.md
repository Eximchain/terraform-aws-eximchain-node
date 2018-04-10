Table of Contents
=================

   * [Warning](#warning)
   * [Work In Progress](#work-in-progress)
   * [Quick Start Guide](#quick-start-guide)
      * [Prerequisites](#prerequisites)
      * [Supported Regions](#supported-regions)
   * [Generate SSH key for EC2 instances](#generate-ssh-key-for-ec2-instances)
      * [Build AMIs to launch the instances with](#build-amis-to-launch-the-instances-with)
      * [Launch Network with Terraform](#launch-network-with-terraform)
      * [Launch and configure vault](#launch-and-configure-vault)
      * [Wait for processes](#wait-for-processes)
         * [Attach the Geth Console](#attach-the-geth-console)
         * [Destroy the Node](#destroy-the-node)

Created by [gh-md-toc](https://github.com/ekalinin/github-markdown-toc)

# Warning
This software launches and uses real AWS resources. It is not a demo or test. By using this software, you will incur the costs of any resources it uses in your AWS account.

# Work In Progress
This repository is a work in progress. A more complete version of this README and code is coming soon.

# Quick Start Guide

## Prerequisites

* You must have AWS credentials at the default location (typically `~/.aws/credentials`)
* You must have the following programs installed on the machine you will be using to launch the network:
    * Python 2.7
    * Hashicorp Packer
    * Hashicorp Terraform

## Supported Regions

The following AWS regions are supported for use with this tool. Attempting to use regions not on this list may result in unexpected behavior. Note that this list may change over time
in the event new regions are added to AWS infrastructure or incompatibilities with existing regions are added or discovered.

* us-east-1
* us-east-2
* us-west-1
* us-west-2
* eu-central-1
* eu-west-1
* eu-west-2
* ap-south-1
* ap-northeast-1
* ap-northeast-2
* ap-southeast-1
* ap-southeast-2
* ca-central-1
* sa-east-1

# Generate SSH key for EC2 instances

Generate an RSA key with ssh-keygen. This only needs to be done once. If you change the output file location you must change the key paths in the terraform variables file later.

```sh
$ ssh-keygen -t rsa -f ~/.ssh/eximchain-node
# Enter a password if you wish
```

Add the key to your ssh agent. This must be done again if you restart your computer. If this is not done, it will cause problems provisioning the instances with terraform.

```sh
$ ssh-add ~/.ssh/eximchain-node
# Enter your password if there is one
```

## Build AMIs to launch the instances with

You may skip this step. If you do, your AMI will be the most recent one built by the official Eximchain AWS Account. We try to keep this as recent as possible but currently no guarantees are made.

If you wish to build yourself, use packer to build the AMIs needed to launch instances

```sh
$ cd packer
$ packer build eximchain-node.json
# Wait for build
$ cd ..
```

## Launch Network with Terraform

Copy the example.tfvars file

```sh
$ cd terraform
$ cp example.tfvars terraform.tfvars
```

Fill in your username as the `cert_owner`:

```sh
$ sed -i '' "s/FIXME_USER/$USER/" terraform.tfvars
```

If you did the build yourself, make sure to specify a `eximchain_node_ami` variable with the resulting AMI ID.

Check terraform.tfvars and change any values you would like to change. Note that the values given in examples.tfvars is NOT completely AWS free tier eligible, as they include t2.small and t2.medium instances. We do not recommend using t2.micro instances, as they were unable to compile solidity during testing.

You may also fill in the quorum_dns variable if you would like to use a remote vault server for key storage, in the case you are using this as part of a larger infrastructure. If not filled in, a local vault server backed by an s3 bucket will be run on the node.

If it is your first time using this package, you will need to run `terraform init` before applying the configuration.

Apply the terraform configuration

```sh
$ terraform apply
# Enter "yes" and wait for infrastructure creation
```

Note the DNS in the output or retain the terminal output. You will need it to finish setting up the node.

## Launch and configure vault

SSH into the node:

```sh
$ NODE=<node DNS>
$ ssh ubuntu@$NODE
```

If you are not using a remote vault server, initialize the vault. Choose the number of key shards and the unseal threshold based on your use case. For a simple test cluster, choose 1 for both. If you are using enterprise vault, you may configure the vault with another unseal mechanism as well.

```sh
$ KEY_SHARES=<Number of key shards>
$ KEY_THRESHOLD=<Number of keys needed to unseal the vault>
$ vault init -key-shares=$KEY_SHARES -key-threshold=$KEY_THRESHOLD
```

Unseal the vault and initialize it with permissions for the quorum nodes. Once setup-vault.sh is complete, the quorum nodes will be able to finish their boot-up procedure. Note that this example is for a single key initialization, and if the key is sharded with a threshold greater than one, multiple users will need to run the unseal command with their shards.

```sh
$ UNSEAL_KEY=<Unseal key output by vault init command>
$ vault unseal $UNSEAL_KEY
$ ROOT_TOKEN=<Root token output by vault init command>
$ /opt/vault/bin/setup-vault.sh $ROOT_TOKEN
```

If any of these commands fail, wait a short time and try again. If waiting doesn't fix the issue, you may need to destroy and recreate the infrastructure.

## Wait for processes

Wait for processes to start

One way to check is to inspect the log folder. If geth and constellation have started, we expect to find logs for `constellation` and `eximchain`, not just `init-eximchain`.

```sh
$ ls /opt/quorum/log
```

Another way is to check the supervisor config folder. if geth and constellation have started, we expect to find files `eximchain-supervisor.conf` and `constellation-supervisor.conf`.

```sh
$ ls /etc/supervisor/conf.d
```

Finally, you can check for the running processes themselves.  Expect to find a running process other than your grep for each of these.

```sh
$ ps -aux | grep constellation-node
$ ps -aux | grep geth
```

### Attach the Geth Console

Once the processes are all running, you can attach your console to the geth JavaScript console

```sh
$ geth attach
```

You should be able to see your other nodes as peers. Connecting may take a few minutes.

```javascript
> admin.peers
```

You should also have a nonzero block number once you start syncing.

```javascript
> eth.blockNumber
```

### Destroy the Node

To take down your running node:

```sh
# From the terraform directory
$ terraform destroy
# Enter "yes" and wait for the network to be destroyed
```

If it finishes with a single error that looks like as follows, ignore it.  Rerunning `terraform destroy` will show that there are no changes to make.

```
Error: Error applying plan:

1 error(s) occurred:

* aws_s3_bucket.vault_storage (destroy): 1 error(s) occurred:

* aws_s3_bucket.vault_storage: Error deleting S3 Bucket: NoSuchBucket: The specified bucket does not exist
	status code: 404, request id: 8641A613A9B146ED, host id: TjS8J2QzS7xFgXdgtjzf6FR1Z2x9uqA5UZLHaMEWKg7I9JDRVtilo6u/XSN9+Qnkx+u5M83p4/w= "vault-storage"

Terraform does not automatically rollback in the face of errors.
Instead, your Terraform state file has been partially updated with
any resources that successfully completed. Please address the error
above and apply again to incrementally change your infrastructure.
```
