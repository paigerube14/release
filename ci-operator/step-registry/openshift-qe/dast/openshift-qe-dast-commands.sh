#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
set -x
cat /etc/os-release
oc config view
oc projects
python --version
pushd /tmp
python -m virtualenv ./venv_qe
source ./venv_qe/bin/activate

REPO_URL="https://github.com/paigerube14/ocp-qe-perfscale-ci.git";

git clone $REPO_URL --branch ssml --depth 1
pushd ocp-qe-perfscale-ci

git clone https://github.com/RedHatProductSecurity/rapidast.git --branch development dast_tool

oc login -u kubeadmin -p $(echo $KUBEADMIN_PASSWORD_FILE)

helm version
          
./deploy_ssml_api.sh

mkdir ${SHARED_DIR}/dast_results/
cp -r results ${SHARED_DIR}/dast_results/