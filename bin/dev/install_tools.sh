#!/bin/bash
set -e

# Installs tools needed to build and run HCF
bin_dir="${bin_dir:-/home/vagrant/bin}"
tools_dir="${tools_dir:-/home/vagrant/tools}"
fissile_url="${fissile_url:-https://concourse-hpe.s3.amazonaws.com/fissile-2.0.2%2B71.g608c02c.develop-linux.amd64.tgz}"
cf_url="${cf_url:-https://cli.run.pivotal.io/stable?release=linux64-binary&version=6.21.1&source=github-rel}"

mkdir -p $bin_dir
mkdir -p $tools_dir

echo "Fetching cf CLI ..."
wget -q "$cf_url"        -O $tools_dir/cf.tgz
echo "Fetching fissile ..."
wget -q "$fissile_url"   -O - | tar xz -C $bin_dir fissile

echo "Unpacking cf CLI ..."
tar -xzf $tools_dir/cf.tgz -C $bin_dir

echo "Making binaries executable ..."
chmod +x $bin_dir/fissile
chmod +x $bin_dir/cf

echo "Pulling ruby bosh image ..."
docker pull helioncf/hcf-pipeline-ruby-bosh

echo "Done."
