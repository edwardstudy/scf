#!/bin/bash
set -e

BINDIR=`readlink -f "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/"`

# Determines whether a container is running
# container_running <CONTAINER_NAME>
function container_running {
  container_name=$1

  if out=$(docker inspect --format='{{.State.Running}}' ${container_name} 2>/dev/null); then
    if [ "$out" == "false" ]; then
      return 1
    fi
  else
    return 1
  fi

  return 0
}

# Determines whether a container exists
# container_exists <CONTAINER_NAME>
function container_exists {
  container_name=$1

  if out=$(docker inspect ${container_name} 2>/dev/null); then
    return 0
  else
    return 1
  fi
}

# Kills an hcf role
# kill_role <ROLE_NAME>
function kill_role {
  role=$1
  container=$(docker ps -a -q --filter "label=fissile_role=${role}")
  if [[ ! -z $container ]]; then
    docker rm --force $container > /dev/null 2>&1
  fi
}

# Starts an hcf role
# start_role <IMAGE_NAME> <CONTAINER_NAME> <ROLE_NAME> <OVERLAY_GATEWAY>
function start_role {
  image=$1
  name=$2
  role=$3
  overlay_gateway=$4

  extra="$(setup_role $role)"

  mkdir -p $store_dir/$role
  mkdir -p $log_dir/$role

  docker run -it -d --name $name \
    --net=hcf \
    --cap-add=NET_ADMIN --cap-add=NET_RAW \
    --label=fissile_role=$role \
    --dns=127.0.0.1 --dns=8.8.8.8 \
    --cgroup-parent=instance \
    -e "HCF_OVERLAY_GATEWAY=${overlay_gateway}" \
    -e "HCF_NETWORK=overlay" \
    -v $store_dir/$role:/var/vcap/store \
    -v $log_dir/$role:/var/vcap/sys/log \
    $extra \
    $image \
    $consul_address \
    $config_prefix > /dev/null
}

# Perform role-specific setup. Return extra arguments needed to start
# the role's container.
# setup_role <ROLE_NAME>
function setup_role() {
  role=$1
  extra=""

  case "$role" in
    "api")
      mkdir -p $store_dir/fake_nfs_share
      touch $store_dir/fake_nfs_share/.nfs_test
      extra="-v ${store_dir}/fake_nfs_share:/var/vcap/nfs/shared"
      ;;
    "doppler")
      extra="--privileged"
      ;;
    "loggregator_trafficcontroller")
      extra="--privileged"
      ;;
    "router")
      extra="--privileged"
      ;;
    "api_worker")
      mkdir -p $store_dir/fake_nfs_share
      touch $store_dir/fake_nfs_share/.nfs_test
      extra="-v $store_dir/fake_nfs_share:/var/vcap/nfs/shared"
      ;;
    "ha_proxy")
      extra="-p 80:80 -p 443:443 -p 4443:4443 -p 2222:2222"
      ;;
    "mysql_proxy")
      extra="-p 3306:3306"
      ;;
    "diego_cell")
      extra="--privileged --cap-add=ALL -v /lib/modules:/lib/modules"
      ;;
    "cf-usb")
      mkdir -p $store_dir/fake_cf_usb_nfs_share
      extra="-v ${store_dir}/fake_cf_usb_nfs_share:/var/vcap/nfs"
      ;;
  esac

  echo "$extra"
}


# Starts the hcf consul server
# start_hcf_consul <CONTAINER_NAME>
function start_hcf_consul() {
  container_name=$1

  mkdir -p $store_dir/$container_name

  if container_exists $container_name ; then
    docker rm $container_name > /dev/null 2>&1
  fi

  cid=$(docker run -d \
    --net=bridge --net=hcf \
    -p 8401:8401 -p 8501:8501 -p 8601:8601 -p 8310:8310 -p 8311:8311 -p 8312:8312 \
    --name $container_name \
    -v $store_dir/$container_name:/opt/hcf/share/consul \
    -t helioncf/hcf-consul-server:latest \
    -bootstrap -client=0.0.0.0 --config-file /opt/hcf/etc/consul.json)
}

# Waits for the hcf consul server to start
# wait_hcf_consul <CONSUL_ADDRESS>
function wait_for_consul() {
  $BINDIR/wait_for_consul.bash $1
}

# gets container name from a fissile docker image name
# get_container_name <IMAGE_NAME>
function get_container_name() {
  echo "${1/:/-}"
}

# imports spec and opinion configs into HCF consul
# run_consullin <CONSUL_ADDRESS> <CONFIG_SOURCE>
function run_consullin() {
  $BINDIR/consullin.bash $1 $2
}

# imports default user and role configs
# run_config <CONSUL_ADDRESS> <PUBLIC_IP>
function run_configs() {
  gato api $1
  public_ip=$2 $BINDIR/configs.sh
}

# get list of all possible images
# get_all_images
function get_all_images() {
    fissile dev list-roles
}

# get consul image
# get_consul_image
function get_consul_image() {
    get_all_images | grep 'consul'
}

# get all possible role images (except consul, and test roles)
# get_role_images
function get_role_images() {
    get_all_images | grep -v 'consul\|smoke_tests\|acceptance_tests'
}

# Convert a list of image names to role names. For use in a pipe.
function to_roles() {
    awk -F":" '{print $1}' | sed -e "s/^${FISSILE_REPOSITORY}-//"
}

# Convert a list of role and image names to images.
# By allowing both role and image names this function can be used to normalize arguments.
function to_images() {
    for role in "$@"
    do
	case "$role" in
	    ${FISSILE_REPOSITORY}-*) echo $role
		;;
	    *) get_image_name $role
		;;
	esac
    done
}

# Convert a list of image names to associated containers, running or not.
function image_to_container() {
    for image in "$@"
    do
	docker ps -q -a --filter "ancestor=$image"
    done
}

# gets a role name from a fissile image name
# get_role_name <IMAGE_NAME>
function get_role_name() {
  role=$(echo $1 | awk -F":" '{print $1}')
  echo ${role#"${FISSILE_REPOSITORY}-"}
}

# gets an image name from a role name
# IMPORTANT: assumes the image is in the local Docker registry
# IMPORTANT: if more than one image is found, it retrieves the first
# get_image_name <ROLE_NAME>
function get_image_name() {
  role=$1
  echo $(docker inspect --format "{{index .RepoTags 0}}" $(docker images -q --filter "label=role=${role}" | head -n 1))
}

# checks if the appropriate version of a role is running
# if it isn't, the currently running role is killed, and
# the correct image is started;
# uses fissile to determine what are the correct images to run
# handle_restart <IMAGE_NAME> <OVERLAY_GATEWAY>
function handle_restart() {
  image=$1
  overlay_gateway=$2

  container_name=$(get_container_name $image)
  role_name=$(get_role_name $image)

  if container_running $container_name ; then
    echo "Role ${role_name} running with appropriate version ..."
    return 1
  else
    echo "Restarting ${role_name} ..."
    kill_role $role_name
    start_role $image $container_name $role $overlay_gateway
    return 0
  fi
}

# Reads all roles that are not tasks from role-manifest.yml
# Uses shyaml for parsing
# list_all_non_task_roles
function list_all_non_task_roles() {
  role_manifest=`readlink -f "${BINDIR}/../../../etc/hcf/config/role-manifest.yml"`

  cat ${role_manifest} | shyaml get-values-0 roles | while IFS= read -r -d '' role_block; do
      role_name=$(echo "${role_block}" | shyaml get-value name)
      is_task=$(echo "${role_block}" | shyaml get-value is_task false)
      if [[ "${is_task}" == "false" ]] ; then
        echo $role_name
      fi
  done
}

# Reads all roles that are tasks from role-manifest.yml
# Uses shyaml for parsing
# list_all_task_roles
function list_all_task_roles() {
  role_manifest=`readlink -f "${BINDIR}/../../../etc/hcf/config/role-manifest.yml"`

  cat ${role_manifest} | shyaml get-values-0 roles | while IFS= read -r -d '' role_block; do
    role_name=$(echo "${role_block}" | shyaml get-value name)
    is_task=$(echo "${role_block}" | shyaml get-value is_task false)
    if [[ "${is_task}" == "true" ]] ; then
      echo $role_name
    fi
  done
}

# Reads all processes for a sepcific role from the role manifest
# Uses shyaml for parsing
# list_all_non_task_roles <ROLE_NAME>
function list_processes_for_role() {
  role_manifest=`readlink -f "${BINDIR}/../../../etc/hcf/config/role-manifest.yml"`
  role_name_filter=$1

  cat ${role_manifest} | shyaml get-values-0 roles | while IFS= read -r -d '' role_block; do
      role_name=$(echo "${role_block}" | shyaml get-value name)

      if [[ "${role_name}" == "${role_name_filter}" ]] ; then
        while IFS= read -r -d '' process_block; do
          process_name=$(echo "${process_block}" | shyaml get-value name)
          echo $process_name
        done < <(echo "${role_block}" | shyaml get-values-0 processes)
      fi
  done
}

# Reads all processes for a sepcific role from the role manifest
# Uses shyaml for parsing
# list_all_non_task_roles <ROLE_NAME>
function list_processes_for_role() {
  role_manifest=`readlink -f ""${BINDIR}/../../../etc/hcf/config/role-manifest.yml""`
  role_name_filter=$1

  cat ${role_manifest} | shyaml get-values-0 roles | while IFS= read -r -d '' role_block; do
      role_name=$(echo "${role_block}" | shyaml get-value name)

      if [[ "${role_name}" == "${role_name_filter}" ]] ; then
        while IFS= read -r -d '' process_block; do
          process_name=$(echo "${process_block}" | shyaml get-value name)
          echo $process_name
        done < <(echo "${role_block}" | shyaml get-values-0 processes)
      fi
  done
}
