#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
set -x
cat /etc/os-release
oc config view
oc projects
pushd /tmp

git clone https://github.com/paigerube14/ocp-qe-perfscale-ci.git --branch ssml
ls
pushd ocp-qe-perfscale-ci/

oc login -u kubeadmin -p $(cat ${SHARED_DIR}/auth/kubeadmin-password)

HELM_DIR=$(mktemp -d)
curl -sS -L https://get.helm.sh/helm-v3.11.2-linux-amd64.tar.gz | tar -xzC ${HELM_DIR}/ linux-amd64/helm

${HELM_DIR}/linux-amd64/helm version  

mv ${HELM_DIR}/linux-amd64/helm $WORKSPACE/helm
PATH=$PATH:$WORKSPACE
helm version

oc label ns default security.openshift.io/scc.podSecurityLabelSync=false pod-security.kubernetes.io/enforce=privileged pod-security.kubernetes.io/audit=privileged pod-security.kubernetes.io/warn=privileged --overwrite

./deploy_ssml_api.sh
rc=$?
echo "Finished running ssml scenarios"
echo "Return code: $rc"
