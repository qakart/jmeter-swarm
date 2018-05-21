#!/bin/sh -x

# This variable describe manager location
MANAGER_REGION="nyc3"

# This array describes workers location
declare -a WORKER_REGIONS=("ams3" "fra1" "lon1")

# DigitalOcean Access Token
export DO_TOKEN="your_digitalocean_access_token"

function to_do_creation(){
echo "--driver=digitalocean --digitalocean-access-token=${DO_TOKEN} --digitalocean-size=1gb --digitalocean-region=${1} --digitalocean-private-networking=true --digitalocean-image=ubuntu-16-04-x64"
}

# Manager machine name
MANAGER_ID=manager-${MANAGER_REGION}

# Create manager machine
docker-machine create \
    $(to_do_creation $MANAGER_REGION) \
    --engine-label role=$MANAGER_ID \
    $MANAGER_ID

# This command extract real ip address
MANAGER_IP=`docker-machine ip $MANAGER_ID`

# Init docker swarm manager on machine
docker-machine ssh $MANAGER_ID "docker swarm init --advertise-addr ${MANAGER_IP}"

# Extract a token necessary to attach workers to swarm
WORKER_TOKEN=`docker-machine ssh $MANAGER_ID docker swarm join-token worker | grep token | awk '{ print $5 }'`

# this array holds worker machine names
declare -a WORKER_IDS=()

# Iterate over worker regions
for region in "${WORKER_REGIONS[@]}"
do
    # Machine name
    worker_machine_name=$(echo worker-${region})

    # Create worker machine
    docker-machine create \
    $(to_do_creation $region) \
    --engine-label role=$worker_machine_name \
    $worker_machine_name
    
	WORKER_IDS+=($worker_machine_name)
	
    # Join to Swarm as worker
    docker-machine ssh ${worker_machine_name} \
    "docker swarm join --token ${WORKER_TOKEN} ${MANAGER_IP}:2377"
done

# Overlay network information
SUB_NET="172.23.0.0/16"
TEST_NET=my-overlay

# Switch swarm manager machine
eval $(docker-machine env $MANAGER_ID)

# From swarm manager overlay network creation
docker network create \
  -d overlay \
  --attachable \
  --subnet=$SUB_NET $TEST_NET
  
# this array is necessary to hold containers name
declare -a JMETER_CONTAINERS=()

# for each worker machine
for id in "${WORKER_IDS[@]}"
do
   # for three times we create JMeter slave service 
   # using engine label for scheduling
   for index in $(seq -f "%02g" 1 3)
   do
   	jmeter_container_name=$(echo ${id}_${index}_jmeter)

	docker service create \
	--name $jmeter_container_name \
	--constraint "engine.labels.role==$id" \
	--network $TEST_NET \
	vmarrazzo/jmeter \
	-s -n \
	-Jclient.rmi.localport=7000 -Jserver.rmi.localport=60000 \
	-Jserver.rmi.ssl.disable=true
   	# save container name
    JMETER_CONTAINERS+=($jmeter_container_name)
    done
done
