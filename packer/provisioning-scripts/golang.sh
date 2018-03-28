#!/bin/bash
set -eu -o pipefail

#GOREL=go1.7.3.linux-amd64.tar.gz
GOREL=go1.9.4.linux-amd64.tar.gz
BASH_PROFILE=/home/ubuntu/.bash_profile

wget -q https://golang.org/dl/$GOREL
tar xfz $GOREL
sudo mv go /usr/local/go
rm -f $GOREL
PATH=$PATH:/usr/local/go/bin
echo '' >> /home/ubuntu/.bash_profile
echo 'export PATH=/usr/local/go/bin:$PATH' >> $BASH_PROFILE
echo 'export GOPATH=/opt/transaction-executor/go' >> $BASH_PROFILE
