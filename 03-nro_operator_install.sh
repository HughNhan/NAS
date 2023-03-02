#!/bin/sh

# Install NRO and performanceprofile for SNO or regular cluster
#

set -euo pipefail

source ./setting.env
source ./functions.sh

parse_args $@

if [ "${SNO}" == "false" ]; then
  echo oc label --overwrite node ${BAREMETAL_WORKER} node-role.kubernetes.io/worker-cnf=""
fi

mkdir -p ${MANIFEST_DIR}/

##### install NUMA Resource operator #####
# skip NRO if version < 4.12 or subscription already exists 
channel=$(get_ocp_channel)
if [ $(ver ${channel}) -ge $(ver 4.12) ] ; then
  if ! oc get Subscription  numaresources-operator -n openshift-numaresources 2>/dev/null; then
    echo "generating ${MANIFEST_DIR}/sub-nro.yaml ..."
    export OCP_CHANNEL=$(get_ocp_channel)
    envsubst < templates/sub-nro.yaml.template > ${MANIFEST_DIR}/sub-nro.yaml
    oc create -f ${MANIFEST_DIR}/sub-nro.yaml
    echo "generating ${MANIFEST_DIR}/sub-nro.yaml: done"
  fi
  wait_pod_in_namespace openshift-numaresources
fi

echo short circuit exit; exit
;
###### generate performance profile ######
echo "Acquiring cpu info from worker node ${BAREMETAL_WORKER} ..."
all_cpus=$(exec_over_ssh ${BAREMETAL_WORKER} lscpu | awk '/On-line CPU/{print $NF;}')

if [ "${SNO}" == "false" ]; then
    export DU_RESERVED_CPUS=$(exec_over_ssh ${BAREMETAL_WORKER} "cat /sys/bus/cpu/devices/cpu0/topology/thread_siblings_list")
else
    file="/etc/kubernetes/openshift-workload-pinning"
    if [ "$(exec_over_ssh ${BAREMETAL_WORKER} "test -e $file && echo true")" == "true" ]; then
        # awk: match "cpuset" line, strip double quotes from NF , print NF 
        #export DU_RESERVED_CPUS=$(exec_over_ssh ${BAREMETAL_WORKER} "cat /etc/kubernetes/openshift-workload-pinning" | awk '/cpuset/{gsub(/"/, "", $NF); print $NF;}' )

        # Use yq to parse, but yq is not available on node. Hence run yq locally,
        cpuset=$(exec_over_ssh ${BAREMETAL_WORKER} "cat /etc/kubernetes/openshift-workload-pinning" | grep cpuset )
        export DU_RESERVED_CPUS=$(echo $cpuset | yq e '.management.cpuset' -)
    else
        echo "WARNING this SNO has no workload-paritioning. Please fix it and then try again"
        exit;
    fi
fi

PYTHON=$(get_python_exec)
export DU_ISOLATED_CPUS=$(${PYTHON} cpu_cmd.py cpuset-substract ${all_cpus} ${DU_RESERVED_CPUS})
echo "Acquiring cpu info from worker node ${BAREMETAL_WORKER}: done"

echo "generating ${MANIFEST_DIR}/performance_profile.yaml ..."
if [[ "${SNO}" == "false" ]]; then
    export MCP=worker-cnf
else
    export MCP=master
fi
envsubst < templates/performance_profile.yaml.template > ${MANIFEST_DIR}/performance_profile.yaml
echo "generating ${MANIFEST_DIR}/performance_profile.yaml: done"

##### apply performance profile ######
if [ "${SNO}" == "true" ]; then
   oc label --overwrite mcp master machineconfiguration.openshift.io/role=master
else
   ./create_mcp.sh
fi

# Give the Operator some delays to reach ready state. Else it can error out.
sleep 10

echo "apply ${MANIFEST_DIR}/performance_profile.yaml ..."
oc apply -f ${MANIFEST_DIR}/performance_profile.yaml

if [[ "${WAIT_MCP}" == "true" ]]; then
    wait_mcp
fi

echo "apply ${MANIFEST_DIR}/performance_profile.yaml: done"
