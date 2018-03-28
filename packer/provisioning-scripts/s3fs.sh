#!/bin/bash
set -eu -o pipefail

RELEASE=v1.83

git clone https://github.com/s3fs-fuse/s3fs-fuse.git
pushd s3fs-fuse >/dev/null
git checkout tags/$RELEASE
./autogen.sh
./configure
make
sudo make install
popd >/dev/null
