#!/bin/bash

shopt -s expand_aliases
alias echo='echo -e'

# fake server-url
RANCHER_SERVER=https://your_rancher_server.com
ROLEFLAGS=""
CLUSTER_CREATE_TYPE=
DOCKER="DOCKER"
KUBERNETES="KUBERNETES"

function usage() {
	echo "usage: "
	echo "\t\t1) $0 -p <password> -u <user> -s <server>"
	echo "\t\t2) $0 -t <token> -s <server>"
	echo ""
	echo "\tIn the first example we use basic auth to access the API"
	echo "\tIn the second example we use an API Token"
	echo ""
	echo ""
	echo "Full argument list"
	echo "\t-c - set the docker command argument to include --controlplane" 
	echo "\t-d - Retrieve the docker command for creating a custom cluster "
	echo "\t\tThis argument may be used with -c -e and -w to specify the node role types"
	echo "\t-e - set the docker command argument to include --etcd" 
	echo "\t-h - This help and usage block"
	echo "\t-k - Retrieve the kubectl command for importing an existing kubernetes cluster "
	echo "\t-n <cluster-name> - name of the cluster to create in Rancher"
	echo "\t\tThis must be in DNS hostname format - lower case letters, dash and period accepted"
	echo "\t-p <password> - users password"
	echo "\t-s <server_url> - server url in the form https://server.url"
	echo "\t-t API Token to use"
	echo "\t-u <user> - users name"
	echo "\t-w - set the docker command argument to include --worker" 
	echo "\t-x - execute the final command instead of outputting it."
	echo "\t-z <admin-password> - setup the admin user in rancher (ignore any -p or -u arguments)"
}

function create_cluster() {
	OPTIND=1
	set -x
	while getopts cdehikn:p:s:t:u:wxz: flag
	do
		case "${flag}" in
			c) ROLEFLAGS=$ROLEFLAGS" --controlplane";;
			d) [ -n "$CLUSTER_CREATE_TYPE" ] && usage || CLUSTER_CREATE_TYPE=$DOCKER;;
			e) ROLEFLAGS=$ROLEFLAGS" --etcd";;
			h) usage
				exit 0
				;;
			i) INSECURE="--insecure";;
			k) [ -n "$CLUSTER_CREATE_TYPE" ] && usage || CLUSTER_CREATE_TYPE=$KUBERNETES;;
			n) CLUSTERNAME=$OPTARG;;
			p) PASSWORD=$OPTARG;;
			s) RANCHER_SERVER=$OPTARG;;
			t) APITOKEN=$OPTARG;;
			u) USER=$OPTARG;;
			w) ROLEFLAGS=$ROLEFLAGS" --worker";;
			x) EXECUTE="true";;
			z) ADMIN_PASSWORD=$OPTARG
				USER="admin"
				[ ! -n $PASSWORD ] && : || PASSWORD="admin"
				;;
		esac
	done

	if [ -z "$CLUSTER_CREATE_TYPE" ]; then
		echo "ERROR: you must specify one of -d or -k"
		usage
		exit 1
	fi

	if [ -z "$APITOKEN" ]; then
		# Login
		LOGINRESPONSE=`curl -s "$RANCHER_SERVER/v3-public/localProviders/local?action=login" -H 'content-type: application/json' --data-binary '{"username":"'$USER'","'password'":"'$PASSWORD'"}' $INSECURE`
		LOGINTOKEN=`echo $LOGINRESPONSE | jq -r .token`

		if [ -n "$ADMIN_PASSWORD" ]; then
			# Change password
			curl -s $RANCHER_SERVER'/v3/users?action=changepassword' -H 'content-type: application/json' -H "Authorization: Bearer $LOGINTOKEN" --data-binary '{"currentPassword":"'$PASSWORD'","newPassword":"'$ADMIN_PASSWORD'"}' $INSECURE

			# Get a new token
			LOGINRESPONSE=`curl -s "$RANCHER_SERVER/v3-public/localProviders/local?action=login" -H 'content-type: application/json' --data-binary '{"username":"'$USER'","'password'":"'$ADMIN_PASSWORD'"}' $INSECURE`
			LOGINTOKEN=`echo $LOGINRESPONSE | jq -r .token`
		fi

		# Create API key
		APIRESPONSE=`curl -s "$RANCHER_SERVER/v3/token" -H 'content-type: application/json' -H "Authorization: Bearer $LOGINTOKEN" --data-binary '{"type":"token","description":"'$CLUSTERNAME'"}' $INSECURE`
		# Extract and store token
		APITOKEN=`echo $APIRESPONSE | jq -r .token`

		if [ -n "$ADMIN_PASSWORD" ]; then
			# Set server-url
			curl -s $RANCHER_SERVER'/v3/settings/server-url' -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" -X PUT --data-binary '{"name":"server-url","value":"'$RANCHER_SERVER'"}' $INSECURE > /dev/null

		fi
	fi


	# Create token
	#curl -s "$RANCHER_SERVER/v3/clusterregistrationtoken" -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" --data-binary '{"type":"clusterRegistrationToken","clusterId":"'$CLUSTERID'"}' $INSECURE > /dev/null

	if [ "$CLUSTER_CREATE_TYPE" == "$DOCKER" ]; then
		# Create cluster
		CLUSTERRESPONSE=`curl -s "$RANCHER_SERVER/v3/cluster?_replace=true" -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" --data-binary '{"dockerRootDir":"/var/lib/docker","enableNetworkPolicy":false,"type":"cluster","rancherKubernetesEngineConfig":{"addonJobTimeout":30,"ignoreDockerVersion":true,"sshAgentAuth":false,"type":"rancherKubernetesEngineConfig","authentication":{"type":"authnConfig","strategy":"x509"},"network":{"type":"networkConfig","plugin":"canal"},"ingress":{"type":"ingressConfig","provider":"nginx"},"monitoring":{"type":"monitoringConfig","provider":"metrics-server"},"services":{"type":"rkeConfigServices","kubeApi":{"podSecurityPolicy":false,"type":"kubeAPIService"},"etcd":{"snapshot":false,"type":"etcdService","extraArgs":{"heartbeat-interval":500,"election-timeout":5000}}}},"name":"'$CLUSTERNAME'"}' $INSECURE`
		# Extract clusterid to use for generating the run command
		CLUSTERID=`echo $CLUSTERRESPONSE | jq -r .id`

		# Fetch docker command
		AGENTCMD=`curl -s $RANCHER_SERVER'/v3/clusterregistrationtokens?id="'$CLUSTERID'"&limit=-1' -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" $INSECURE | jq -r '.data[].nodeCommand' | head -1`
	else
		# It's not a custom cluster so let's create an import cluster
		# Create cluster
		CLUSTERRESPONSE=`curl -s "$RANCHER_SERVER/v3/cluster?_replace=true" -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" --data-binary '{"name":"'$CLUSTERNAME'"}' $INSECURE`
		# Extract clusterid to use for generating the run command
		CLUSTERID=`echo $CLUSTERRESPONSE | jq -r .id`

		if [ -z "$INSECURE" ]; then
			# Fetch k8s command

			#This command seems to work in the v2.6 tech preview
			#AGENTCMD=`curl -s $RANCHER_SERVER'/v3/clusterregistrationtokens?id="'$CLUSTERID'"&limit=-1' -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" | jq -r '.data[0].command' `

			#This command is for v2.5.8 and earlier
			AGENTCMD=`curl -s $RANCHER_SERVER'/v3/clusterregistrationtokens?id="'$CLUSTERID'"&limit=-1' -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" -X POST --data-binary '{"clusterId":"'$CLUSTERID'"}' | jq -r '.command' `
		else
			# Fetch insecure k8s command

			#This command seems to work in the v2.6 tech preview
			#AGENTCMD=`curl -s $RANCHER_SERVER'/v3/clusterregistrationtokens?id="'$CLUSTERID'"&limit=-1' -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" $INSECURE | jq -r '.data[0].insecureCommand' `

			#This command is for v2.5.8 and earlier
			AGENTCMD=`curl -s $RANCHER_SERVER'/v3/clusterregistrationtokens?id="'$CLUSTERID'"&limit=-1' -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" -X POST --data-binary '{"clusterId":"'$CLUSTERID'"}' $INSECURE | jq -r '.insecureCommand' `
		fi
	fi

	# Concat commands
	RUNCMD="$AGENTCMD $ROLEFLAGS"

	if [ -n "$EXECUTE" ]; then 
		eval $RUNCMD 
	else
		echo $RUNCMD
	fi
}