#!/bin/sh

set -euo pipefail

source ./setting.env
source ./functions.sh

parse_args $@





###### Delete NRO custom resource
if oc get numaresourcesoperators.nodetopology.openshift.io  2>/dev/null; then  0                                
    echo "Remove NRO custom resource ..."
    [ -e  ${MANIFEST_DIR}/nrop.yaml ] &&  oc delete -f ${MANIFEST_DIR}/nrop.yaml
fi

#### Skip NRO mcp deletion
#### Skip NRO deletion

#### old start

exit

echo "Removing performance profile ..."
[ -e ${MANIFEST_DIR}/nro.yaml ] && oc delete -f ${MANIFEST_DIR}/nro.yaml

if [[ "${SNO}" == "true" ]]; then
   echo oc label mcp master machineconfiguration.openshift.io/role-
fi

if [[ "${WAIT_MCP}" == "true" ]]; then
    wait_mcp
fi

echo "Removing performance profile: done"
