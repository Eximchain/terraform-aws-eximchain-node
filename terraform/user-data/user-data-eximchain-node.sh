#!/bin/bash
# This script is meant to be run in the User Data of each EC2 Instance while it's booting. The script uses the
# run-consul script to configure and start Consul in server mode. Note that this script assumes it's running in an AMI
# built from the Packer template in examples/vault-consul-ami/vault-consul.json.

set -eu

readonly BASH_PROFILE_FILE="/home/ubuntu/.bash_profile"
# This is necessary to retrieve the address for vault
echo "export VAULT_ADDR=https://${vault_dns}:${vault_port}" >> $BASH_PROFILE_FILE
source $BASH_PROFILE_FILE

readonly VAULT_TLS_CERT_DIR="/opt/vault/tls"
readonly VAULT_TLS_CERT_FILE="$VAULT_TLS_CERT_DIR/vault.crt.pem"
readonly VAULT_TLS_KEY_FILE="$VAULT_TLS_CERT_DIR/vault.key.pem"

function wait_for_terraform_provisioners {
    # Ensure terraform has run all provisioners
    while [ ! -e /opt/quorum/info/network-id.txt ]
    do
        sleep 5
    done
}

function download_vault_certs {
  # Download vault certs from s3
  aws configure set s3.signature_version s3v4
  while [ -z "$(aws s3 ls s3://${vault_cert_bucket}/ca.crt.pem)" ]
  do
      echo "S3 object not found, waiting and retrying"
      sleep 5
  done
  while [ -z "$(aws s3 ls s3://${vault_cert_bucket}/vault.crt.pem)" ]
  do
      echo "S3 object not found, waiting and retrying"
      sleep 5
  done
  aws s3 cp s3://${vault_cert_bucket}/ca.crt.pem $VAULT_TLS_CERT_DIR
  aws s3 cp s3://${vault_cert_bucket}/vault.crt.pem $VAULT_TLS_CERT_DIR

  # Set ownership and permissions
  sudo chown ubuntu $VAULT_TLS_CERT_DIR/*
  sudo chmod 600 $VAULT_TLS_CERT_DIR/*
  sudo /opt/vault/bin/update-certificate-store --cert-file-path $CA_TLS_CERT_FILE
}

# Send the log output from this script to user-data.log, syslog, and the console
# From: https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

wait_for_terraform_provisioners

# Start vault and consul servers if we're using a local vault
if [ ${vault_dns} == "127.0.0.1" ]
then
  /opt/vault/bin/generate-setup-vault
  # These variables are passed in via Terraform template interpolation
  /opt/consul/bin/run-consul --server --cluster-tag-key "${consul_cluster_tag_key}" --cluster-tag-value "${consul_cluster_tag_value}"
  /opt/vault/bin/run-vault --s3-bucket "${s3_bucket_name}" --s3-bucket-region "${aws_region}" --tls-cert-file "$VAULT_TLS_CERT_FILE"  --tls-key-file "$VAULT_TLS_KEY_FILE"
else
  download_vault_certs
fi

/opt/quorum/bin/run-init-eximchain-node $VAULT_ADDR
