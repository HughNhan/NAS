#!/bin/sh

# Install NUMA-Resource Operator, NRO and its custom resource 
#

set -euo pipefail

source ./setting.env
source ./functions.sh

parse_args $@

mkdir -p ${MANIFEST_DIR}/

##### install NUMA Resource operator NOR #####
# skip NRO if version < 4.12 or subscription already exists 
channel=$(get_ocp_channel)
if [ $(ver ${channel}) -lt $(ver 4.12) ] ; then
    echo "version ${channel} does not support NUMA-aware Schedule"
    exit
fi

if ! oc get Subscription numaresources-operator -n openshift-numaresources 2>/dev/null; then
    echo "generating ${MANIFEST_DIR}/sub-nro.yaml ..."
    export OCP_CHANNEL=$(get_ocp_channel)
    envsubst < templates/sub-nro.yaml.template > ${MANIFEST_DIR}/sub-nro.yaml
    oc create -f ${MANIFEST_DIR}/sub-nro.yaml
    echo "generating ${MANIFEST_DIR}/sub-nro.yaml: done"
    wait_pod_in_namespace openshift-numaresources
fi


###### create NRO mcp if it is not already created ######
if ! oc get mcp worker-nas 2>/dev/null; then
  #5.3.1 -i  generate mcp yaml
  echo "generating mcp ${MANIFEST_DIR}/nro-machineconfig.yaml ..."
  envsubst < templates/nro-machineconfig.yaml.template > ${MANIFEST_DIR}/nro-machineconfig.yaml
  echo "generating mcp ${MANIFEST_DIR}/nro-machineconfig.yaml: done"

  #5.3.1 - ii create mcp
  echo "create mcp  ${MANIFEST_DIR}/nro-machineconfig.yaml ..."
  oc create -f ${MANIFEST_DIR}/nro-machineconfig.yaml
  if [[ "${WAIT_MCP}" == "true" ]]; then
    wait_mcp
  fi
  echo "create mcp  ${MANIFEST_DIR}/nro-machineconfig.yaml: done"
fi

echo short circuit exit; exit;

###### create NRO custom resource  ######
#5.3.2 - i  generate NRO custom resource yaml
echo "generating ${MANIFEST_DIR}/nrop.yaml.template..."
envsubst < templates/nrop.yaml.template > ${MANIFEST_DIR}/nrop.yaml
echo "generating ${MANIFEST_DIR}/nrop.yaml: done"

#5.3.2 - ii  create NRO custom resource
echo "create NRO custom resource ${MANIFEST_DIR}/nropyaml ..."
oc create -f ${MANIFEST_DIR}/nrop.yaml
echo "create NRO custom resource ${MANIFEST_DIR}/nrop.yaml: done"

sleep 10
### Verifying NRO custom resource depoyment
if ! oc get numaresourcesoperators.nodetopology.openshift.io  2>/dev/null; then  0                                
    echo "NRO custom resource deployed successfully ..."
else
    echo "NRO custom resource failed to deploy ..."
fi


