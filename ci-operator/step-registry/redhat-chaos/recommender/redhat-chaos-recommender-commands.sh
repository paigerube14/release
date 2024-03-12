#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
set -x
cat /etc/os-release
oc config view
oc projects
python3 --version
ls

ls -la /root/kraken

echo "kubeconfig loc $$KUBECONFIG"
echo "Using the flattened version of kubeconfig"
oc config view --flatten > /tmp/config
telemetry_password=$(cat "/secret/telemetry/telemetry_password")
export TELEMETRY_PASSWORD=$telemetry_password

export KUBECONFIG=/tmp/config
   
export NAMESPACE=$TARGET_NAMESPACE
export KRKN_KUBE_CONFIG=$KUBECONFIG
export ENABLE_ALERTS=False
export PROMETHEUS_ENDPOINT=https://$(oc get route -n openshift-monitoring prometheus-k8s -o jsonpath="{.spec.host}")
export PROMETHEUS_TOKEN=$(oc create token -n openshift-monitoring prometheus-k8s --duration=6h || oc sa get-token -n openshift-monitoring prometheus-k8s || oc sa new-token -n openshift-monitoring prometheus-k8s)

ls
pwd 

./chaos-recommender/run.sh
rc=$?
echo "Finished running time scenario"
echo "Return code: $rc"
