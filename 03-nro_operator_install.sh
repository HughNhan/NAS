#!/bin/sh
#
# Install NUMAResourceOperator NRO and its custom resource.
#

set -euo pipefail
source ./setting.env
source ./functions.sh

parse_args $@

mkdir -p ${MANIFEST_DIR}/

##### 5.2.1 install NUMAResourceOperator NOR #####
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
    echo ">>> create NRO Subscription ${MANIFEST_DIR}/sub-nro.yaml: done"
    oc create -f ${MANIFEST_DIR}/sub-nro.yaml
    echo "    create NRO Subscription ${MANIFEST_DIR}/sub-nro.yaml: done"
    wait_pod_in_namespace openshift-numaresources
fi

add_label_workers

###### 5.3.1 create NRO mcp if it is not already created ######
if ! oc get mcp ${MCP} 2>/dev/null; then
  echo "generating NRO mcp ${MANIFEST_DIR}/nro-machineconfig.yaml ..."
  envsubst < templates/nro-machineconfig.yaml.template > ${MANIFEST_DIR}/nro-machineconfig.yaml

  echo ">>> create NRO mcp ${MANIFEST_DIR}/nro-machineconfig.yaml"
  oc create -f ${MANIFEST_DIR}/nro-machineconfig.yaml
  echo "    create NRO mcp ${MANIFEST_DIR}/nro-machineconfig.yaml: done"
fi


###### 5.3.2 create NRO custom resource
echo "generating NRO Custom Resource ${MANIFEST_DIR}/nrop.yaml.template..."
envsubst < templates/nrop.yaml.template > ${MANIFEST_DIR}/nrop.yaml

echo ">>> create NRO Custom Resource ${MANIFEST_DIR}/nrop.yaml"
oc create -f ${MANIFEST_DIR}/nrop.yaml
echo "     create NRO Custom Resource ${MANIFEST_DIR}/nrop.yaml: done"

sleep 10
### Verifying NRO custom resource deployment
if oc get numaresourcesoperators.nodetopology.openshift.io  2>/dev/null; then 
    echo "NRO custom resource deployed successfully"
else
    echo "NRO custom resource failed to deploy"
    exit
fi

############### 5.4 Deploy NUMA-aware secondary Pod Scheduler   ##############
# 5.4.1 Create the KubeletConfig custom resource that configures the pod admittance policy for the machine profile:
echo "generating KubeletConfig Custom Resource ${MANIFEST_DIR}/nro-kubeletconfig.yaml..."
envsubst < templates/nro-kubeletconfig.yaml.template > ${MANIFEST_DIR}/nro-kubeletconfig.yaml

echo ">>> create KubeletConfig custom resource ${MANIFEST_DIR}/nro-kubeletconfig.yaml ..."
oc create -f ${MANIFEST_DIR}/nro-kubeletconfig.yaml
echo "    create KubeletConfig Custom Resource ${MANIFEST_DIR}/nro-kubeletconfig.yaml: done >>>"

# 5.4.2 Create the NUMAResourcesScheduler custom resource that deploys the NUMA-aware custom pod scheduler
echo "generating NUMAResourceSchedulerCustom Resource ${MANIFEST_DIR}/nro-scheduler.yaml"
envsubst < templates/nro-scheduler.yaml.template > ${MANIFEST_DIR}/nro-scheduler.yaml

echo ">>> create NUMAResourcesScheduler custom resource ${MANIFEST_DIR}/nro-scheduler.yaml ..."
oc create -f ${MANIFEST_DIR}/nro-scheduler.yaml
echo "    create NUMAResourcesScheduler custom resource ${MANIFEST_DIR}/nro-scheduler.yaml: done"

if [[ "${WAIT_MCP}" == "true" ]]; then
    wait_mcp
fi

# Verify NAS Pod Scheduler
if oc get all -n openshift-numaresources  2>/dev/null; then 
    echo "NAS Pod Scheduler custom resource deployed successfully"
else
    echo "NAS Pod Scheduler custom resource failed to deploy"
    exit
fi

echo short circuit exit; exit;
