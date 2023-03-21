get_ocp_channel () {
    local channel=$(oc get clusterversion -o json | jq -r '.items[0].spec.channel' | sed -r -n 's/.*-(.*)/\1/p')
    echo ${channel}
}

pause_mcp () {
    oc patch --type=merge --patch='{"spec":{"paused":true}}' machineconfigpool/${MCP}
}

resume_mcp () {
    oc patch --type=merge --patch='{"spec":{"paused":false}}' machineconfigpool/${MCP}
}

get_mcp_progress_status () {
    # (worker != 'updating') && (worker-nas != 'Updating' )
    local status=$(oc get mcp worker -o json | jq -r '.status.conditions[] | select(.type == "Updating") | .status')
    if [ "$status" == "False" ]; then
      local status=$(oc get mcp ${MCP} -o json | jq -r '.status.conditions[] | select(.type == "Updating") | .status')
    fi
    echo ${status}
}

wait_mcp () {
    resume_mcp
    printf "waiting 60 sec before checking mcp status "
    local count=6
    while [[ $count -gt 0  ]]; do
        sleep 10
        printf "."
        count=$((count-1))
    done

    local status=$(get_mcp_progress_status)
    count=300
    printf "\npolling 3000 sec for mcp complete"
    while [[ $status != "False" ]]; do
        if ((count == 0)); then
            printf "\ntimeout waiting for mcp complete on the baremetal host!\n"
            exit 1
        fi
        count=$((count-1))
        printf "."
        sleep 10
        status=$(get_mcp_progress_status)
    done
    printf "\nmcp complete on the baremetal host in %d sec\n" $(( (300-count) * 10 ))
}

wait_pod_in_namespace () {
    local namespace=$1
    local count=100
    printf "waiting for pod in ${namespace}"
    while ! oc get pods -n ${namespace} 2>/dev/null | grep Running; do
        if ((count == 0)); then
            printf "\ntimeout waiting for pod in ${namespace}!\n" 
            exit 1
        fi
        count=$((count-1))
        printf "."
        sleep 5
    done
    printf "\npod in ${namespace}: up\n"
}

wait_named_pod_in_namespace () {
    local namespace=$1
    local podpattern=$2
    local count=100
    printf "waiting for pod ${podpattern} in ${namespace}"
    while ! oc get pods -n ${namespace} 2>/dev/null | grep ${podpattern} | grep Running; do
        if ((count == 0)); then
            printf "\ntimeout waiting for pod ${podpattern} in ${namespace}!\n"
            exit 1
        fi
        count=$((count-1))
        printf "."
        sleep 5
    done
    printf "\npod ${podpattern} in ${namespace}: up\n"
}

wait_named_deployement_in_namespace () {
    local namespace=$1
    local deployname=$2
    local count=100
    printf "waiting for deployment ${deployname} in ${namespace}"
    local status="False"
    while [[ "${status}" != "True" ]]; do
        if ((count == 0)); then
            printf "\ntimeout waiting for deployment ${deployname} in ${namespace}!\n"
            exit 1
        fi
        count=$((count-1))
        printf "."
        sleep 5
        status=$(oc get deploy ${deployname} -n ${namespace} -o json 2>/dev/null | jq -r '.status.conditions[] | select(.type=="Available") | .status' || echo "False")
    done
    printf "\ndeployment ${deployname} in ${namespace}: up\n"
}

exec_over_ssh () {
    local nodename=$1
    local cmd=$2
    local ssh_options="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    local ip_addr=$(oc get node ${nodename} -o json | jq -r '.status.addresses[] | select(.type=="InternalIP") | .address')
    local ssh_output=$(ssh ${ssh_options} core@${ip_addr} "$cmd")
    echo "${ssh_output}"
}

parse_args() {
    USAGE="Usage: $0 [options]
Options:
    -n             Do not wait
    -h             This
"
    while getopts "hn" OPTION
    do
        case $OPTION in
            n) WAIT_MCP="false" ;;
            h) echo "$USAGE"; exit ;;
            *) echo "$USAGE"; exit 1;;
        esac
    done

    MCP=${MCP:-"worker-nas"}
    WAIT_MCP=${WAIT_MCP:-"true"}
    WORKERS=${WORKERS:-"none"}
    if [ ${WORKERS} == "none" ]; then 
        WORKERS=$(oc get node | grep worker | awk '{print $1}')
    fi
    WORKER_LIST=( $WORKERS )
    NUM_NAS_WORKERS=${#WORKER_LIST[@]}
}


add_label_workers () {
    for worker in $WORKERS; do
        oc label --overwrite node ${worker} node-role.kubernetes.io/${MCP}=""
    done
}

remove_label_workers () {
    for worker in $WORKERS; do
        oc label --overwrite node ${worker} node-role.kubernetes.io/${MCP}-
    done
}


function ver { 
   printf "%03d%03d%03d%03d" $(echo "$1" | tr '.' ' '); 
}

hn_echo() {
    echo $@
}
hn_exit() {
    echo "HN exit"
    exit
}

