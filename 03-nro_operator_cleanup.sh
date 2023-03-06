#!/bin/sh
#
# Delete NUMAResourceOperator (NOR)A and its customr resource.
#

set -euo pipefail
source ./setting.env
source ./functions.sh

parse_args $@

# 5.4.2 Delete the NUMAResourcesScheduler custom resource 
if [ -e ${MANIFEST_DIR}/nro-scheduler.yaml ]; then
    echo ">>> delete NUMAResourcesScheduler custom resource ${MANIFEST_DIR}/nro-scheduler.yaml ..."
    oc delete -f ${MANIFEST_DIR}/nro-scheduler.yaml
    echo "    delete NUMAResourcesScheduler custom resource ${MANIFEST_DIR}/nro-scheduler.yaml: done"
    rm ${MANIFEST_DIR}/nro-scheduler.yaml 
fi


#### 5.4.1 delete KubeletConfig Custom Resource
if [ -e ${MANIFEST_DIR}/nro-kubeletconfig.yaml ]; then
    echo ">>> delete KubeletConfig custom resource ${MANIFEST_DIR}/nro-kubeletconfig.yaml ..."
    oc delete -f ${MANIFEST_DIR}/nro-kubeletconfig.yaml
    echo "    delete KubeletConfig Custom Resource ${MANIFEST_DIR}/nro-kubeletconfig.yaml: done"
    rm ${MANIFEST_DIR}/nro-kubeletconfig.yaml
fi

###### 5.3.2 Delete NRO custom resource
if [ -e ${MANIFEST_DIR}/nrop.yaml ]; then
    echo ">>> delete NRO custom resource ..."
    oc delete -f ${MANIFEST_DIR}/nrop.yaml
    echo "    delete NRO custom resource: done"
    rm ${MANIFEST_DIR}/nrop.yaml
fi

remove_label_workers

if [[ "${WAIT_MCP}" == "true" ]]; then
    wait_mcp
fi

exit

# Skip mcp and NRO Operator deletion

echo "Removing all NUMA-resource scheduler : done"

exit


#### 5.3.1 Delete NRO mcp 
if [ -e ${MANIFEST_DIR}/nro-machineconfig.yaml ]; then
    echo ">>> delete NRO mcp ..."
    oc delete -f ${MANIFEST_DIR}/nro-machineconfig.yaml
    echo "    delete NRO mcp: done"
fi;


if [[ "${WAIT_MCP}" == "true" ]]; then
    wait_mcp
fi



# That's all
