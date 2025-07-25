#!/bin/bash
set -euo pipefail

trap 'CHILDREN=$(jobs -p); if test -n "${CHILDREN}"; then kill ${CHILDREN} && wait; fi' TERM

INSTANCE_PREFIX="${NAMESPACE}"-"${UNIQUE_HASH}"
GOOGLE_PROJECT_ID="$(< ${CLUSTER_PROFILE_DIR}/openshift_gcp_project)"
GOOGLE_COMPUTE_REGION="${LEASED_RESOURCE}"
GOOGLE_COMPUTE_ZONE="$(< ${SHARED_DIR}/openshift_gcp_compute_zone)"
if [[ -z "${GOOGLE_COMPUTE_ZONE}" ]]; then
  echo "Expected \${SHARED_DIR}/openshift_gcp_compute_zone to contain the GCP zone"
  exit 1
fi

mkdir -p "${HOME}"/.ssh
BUNDLE_VERSION="$(crc version | grep -oP '^OpenShift version\s*:\s*\K\S+')"
ARCH=$(uname -m)
case "${ARCH}" in
    x86_64)
        BUNDLE_ARCH="amd64"
	;;
    aarch64)
        BUNDLE_ARCH="arm64"
	;;
    *)
        BUNDLE_ARCH=${ARCH}
	;;
esac
BUNDLE=crc_libvirt_"${BUNDLE_VERSION}"_"${BUNDLE_ARCH}".crcbundle

mock-nss.sh

# gcloud compute will use this key rather than create a new one
cp "${CLUSTER_PROFILE_DIR}"/ssh-privatekey "${HOME}"/.ssh/google_compute_engine
chmod 0600 "${HOME}"/.ssh/google_compute_engine
cp "${CLUSTER_PROFILE_DIR}"/ssh-publickey "${HOME}"/.ssh/google_compute_engine.pub
echo 'ServerAliveInterval 30' | tee -a "${HOME}"/.ssh/config
echo 'ServerAliveCountMax 1200' | tee -a "${HOME}"/.ssh/config
chmod 0600 "${HOME}"/.ssh/config

# Copy pull secret to user home
cp "${CLUSTER_PROFILE_DIR}"/pull-secret "${HOME}"/pull-secret

gcloud auth activate-service-account --quiet --key-file "${CLUSTER_PROFILE_DIR}"/gce.json
gcloud --quiet config set project "${GOOGLE_PROJECT_ID}"
gcloud --quiet config set compute/zone "${GOOGLE_COMPUTE_ZONE}"
gcloud --quiet config set compute/region "${GOOGLE_COMPUTE_REGION}"

cat  > "${HOME}"/run-tests.sh << 'EOF'
#!/bin/bash
set -euo pipefail
export PATH=/home/packer:$PATH
mkdir -p /tmp/artifacts

function run-tests() {
  pushd crc
  cp -r test/testdata ${HOME}/testdata
  set +e
  /tmp/e2e.test --pull-secret-file="${HOME}"/pull-secret \
                --bundle-location="${HOME}"/$(cat "${HOME}"/bundle) \
                --crc-binary=/tmp \
                --godog.tags='~@story_registry && @linux && ~@minimal && ~@microshift' \
                --godog.paths test/e2e/features/
  if [[ $? -ne 0 ]]; then
    exit 1
    popd
  fi
  popd
}

run-tests
EOF

chmod +x "${HOME}"/run-tests.sh

# Get the bundle
curl -L "https://mirror.openshift.com/pub/openshift-v4/clients/crc/bundles/openshift/${BUNDLE_VERSION}/${BUNDLE}" -o /tmp/${BUNDLE}

echo "${BUNDLE}" > "${HOME}"/bundle

export LD_PRELOAD=/usr/lib64/libnss_wrapper.so
until gcloud compute --project "${GOOGLE_PROJECT_ID}" ssh --zone "${GOOGLE_COMPUTE_ZONE}" packer@"${INSTANCE_PREFIX}" --command "exit 0" 2>/dev/null; do
  echo "Waiting for SSH to become available..."
  sleep 5
done
echo "SSH is now available for ${INSTANCE_PREFIX}"

LD_PRELOAD=/usr/lib64/libnss_wrapper.so gcloud compute scp \
  --quiet \
  --project "${GOOGLE_PROJECT_ID}" \
  --zone "${GOOGLE_COMPUTE_ZONE}" \
  --recurse "${HOME}"/run-tests.sh packer@"${INSTANCE_PREFIX}":~/run-tests.sh

LD_PRELOAD=/usr/lib64/libnss_wrapper.so gcloud compute scp \
  --quiet \
  --project "${GOOGLE_PROJECT_ID}" \
  --zone "${GOOGLE_COMPUTE_ZONE}" \
  --recurse "${HOME}"/pull-secret packer@"${INSTANCE_PREFIX}":~/pull-secret

LD_PRELOAD=/usr/lib64/libnss_wrapper.so gcloud compute scp \
  --quiet \
  --project "${GOOGLE_PROJECT_ID}" \
  --zone "${GOOGLE_COMPUTE_ZONE}" \
  --recurse /bin/crc packer@"${INSTANCE_PREFIX}":/tmp/crc

LD_PRELOAD=/usr/lib64/libnss_wrapper.so gcloud compute scp \
  --quiet \
  --project "${GOOGLE_PROJECT_ID}" \
  --zone "${GOOGLE_COMPUTE_ZONE}" \
  --recurse /bin/e2e.test packer@"${INSTANCE_PREFIX}":/tmp/e2e.test

LD_PRELOAD=/usr/lib64/libnss_wrapper.so gcloud compute scp \
  --quiet \
  --project "${GOOGLE_PROJECT_ID}" \
  --zone "${GOOGLE_COMPUTE_ZONE}" \
  --recurse "${HOME}"/bundle packer@"${INSTANCE_PREFIX}":~/bundle

LD_PRELOAD=/usr/lib64/libnss_wrapper.so gcloud compute scp \
  --quiet \
  --project "${GOOGLE_PROJECT_ID}" \
  --zone "${GOOGLE_COMPUTE_ZONE}" \
  --recurse /tmp/"${BUNDLE}" packer@"${INSTANCE_PREFIX}":~/"${BUNDLE}"

LD_PRELOAD=/usr/lib64/libnss_wrapper.so gcloud compute scp \
  --quiet \
  --project "${GOOGLE_PROJECT_ID}" \
  --zone "${GOOGLE_COMPUTE_ZONE}" \
  --recurse /opt/crc packer@"${INSTANCE_PREFIX}":~/crc

LD_PRELOAD=/usr/lib64/libnss_wrapper.so gcloud compute --project "${GOOGLE_PROJECT_ID}" ssh \
  --zone "${GOOGLE_COMPUTE_ZONE}" \
  packer@"${INSTANCE_PREFIX}" \
  --command 'sudo rm -fr /usr/local/go; sudo yum install -y podman make golang'

LD_PRELOAD=/usr/lib64/libnss_wrapper.so gcloud compute --project "${GOOGLE_PROJECT_ID}" ssh \
  --zone "${GOOGLE_COMPUTE_ZONE}" \
  packer@"${INSTANCE_PREFIX}" \
  --command '/home/packer/run-tests.sh'
