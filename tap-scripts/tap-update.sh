#!/bin/bash
# Copyright 2022 VMware, Inc.
# SPDX-License-Identifier: BSD-2-Clause
source var.conf

############################################################
# Functions                                                #
############################################################
# Version comparison function.
## OLD version as the 1st argument
## NEW version as the 2nd argument
## If update is required, return value is 0, otherwise, 1
versionlte() {
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}
versionlt() {
    [ "$1" = "$2" ] && return 1 || versionlte $1 $2
}
# Function to check if a string is in a list
contains_string() {
    local STRING="$1"
    local LIST="$2"
    echo "$LIST" | grep -w -q "$STRING"
}

############################################################
# Variables                                                #
############################################################
INSTALL_REPO=tanzu-application-platform
#Initializing the New K8S version to the existing one, just in case K8S does not need to be updated.
K8_Version_NEW=$K8_Version


############################################################
# Help                                                     #
############################################################
Help()
{
   # Display Help
   echo "This script updates an existing TAP multi-cluster setup, installed in 4 different EKS clusters."
   echo "The script requires a previous setup of the AWS CLI, the existing TAP values files and the var.conf file used to install TAP."
   echo
   echo "Syntax: tap-update.sh [-k <New K8S version] -t <New TAP version> [-h]"
   echo "options:"
   echo " -k     New Kubernetes version to be used. This parameter is optional in case the new TAP version supports the existing underlying K8S version."
   echo " -t     New TAP version to be used. This parameter is mandatory!"
   echo " -h     Print this Help."
   echo
}

############################################################
# Main program                                             #
############################################################

# Get the options
while getopts "k:t:h" option; do
   case $option in
      h) # display Help
         Help
         exit;;
      k) # Enter a cluster name
	    K8_Version_NEW=$OPTARG;;
      t) # Enter a FQDN
        TAP_VERSION_NEW=$OPTARG;;	      
     \?) # Invalid option
         Help
         exit 1;;
   esac
done

shift "$(( OPTIND - 1 ))"

if [ -z "$TAP_VERSION_NEW" ] ; then
    echo 'Missing -t ' >&2
	Help
    exit 1
fi

# CHECK if the new K8S version is a suitable version
echo "Checking availability of new K8S version in AWS..."
AVAILABLE_K8S_VERSIONS=$(aws eks describe-addon-versions | jq -r ".addons[] | .addonVersions[] | .compatibilities[] | .clusterVersion" | sort | uniq)
if ! contains_string $K8_Version_NEW "$AVAILABLE_K8S_VERSIONS" ;
then
    echo -n "The specified Kubernetes version is not available in EKS for the selected region, please, use one of: "
    echo $AVAILABLE_K8S_VERSIONS
    exit 1
fi
echo "K8S version $K8_Version_NEW is available in the $aws_region for EKS!"

# CHECK if the new TAP version is a suitable version
echo "Checking availability of new TAP version in Tanzu Network..."
AVAILABLE_TAP_VERSIONS=$( curl -s -X GET https://network.tanzu.vmware.com/api/v2/products/tanzu-application-platform/releases -H "Authorization: Bearer ${tanzu_net_api_token}" | jq -r '.releases[].version' | sort | uniq)
if ! contains_string $TAP_VERSION_NEW "$AVAILABLE_TAP_VERSIONS" ;
then
    echo -n "The specified TAP version is not available in Tanzu Network, please, use one of: "
    echo $AVAILABLE_TAP_VERSIONS
    exit 1
fi
echo "TAP version $TAP_VERSION_NEW is available in Tanzu Network!"


# CHECK clusters to be updated
CLUSTERS_TO_UPDATE=$((grep "^TAP_VIEW_CLUSTER_NAME" var.conf | awk -F'=' '{print $2}' | tr -d '"' || true) && grep "_CLUSTER_NAME" var.conf | grep -v '^#' | grep -v '^TAP_VIEW_CLUSTER_NAME' | awk -F'=' '{print $2}' | tr -d '"')

echo "The following clusters will be updated in order: $CLUSTERS_TO_UPDATE"

# COMPARE K8_Version and K8_Version_NEW
echo "Comparing Kubernetes versions..."
NOT_UPGRADING_K8S_MESSAGE="The specified Kubernetes version is not higher than the current one specified in the var.conf file. Will not update Kubernetes..."
versionlt $K8_Version $K8_Version_NEW && UPDATE_K8S=true || UPDATE_K8S=false

if $UPDATE_K8S ;
then
    echo "Updating K8S version in the EKS clusters from $K8_Version to $K8_Version_NEW..."

    for CLUSTER in $CLUSTERS_TO_UPDATE;
    do
        echo " - Updating K8S version for cluster $CLUSTER..."
        aws eks update-cluster-version --region $aws_region --name $CLUSTER --kubernetes-version $K8_Version_NEW
    done

    echo "Sleeping 30 seconds for AWS to start EKS clusters upgrade..."
    sleep 30

    UPDATING_K8S=true

    #ACTIVE CHECK OF K8S UPDATE
    NUM_CLUSTERS_TO_UPDATE=$(echo $CLUSTERS_TO_UPDATE | wc -w)
    UPDATED_CLUSTERS=0
    echo -n "Updating Kubernetes clusters "
    while [[ $UPDATED_CLUSTERS -lt $NUM_CLUSTERS_TO_UPDATE ]];
    do
        UPDATED_CLUSTERS=0
        sleep 1
        for CLUSTER in $CLUSTERS_TO_UPDATE;
        do
            [[ $(aws eks describe-cluster --name $CLUSTER | jq -r '.cluster.status') = "ACTIVE" ]] && let "UPDATED_CLUSTERS++"    
        done
        echo -n "."
    done

    echo -e "\n All K8S clusters were successfully updated!"
    echo "Updating var.conf file with new K8S version..."
    sed -i "s/^K8_Version=.*/K8_Version=$K8_Version_NEW/" var.conf

else
    echo $NOT_UPGRADING_K8S_MESSAGE
fi

# COMPARE TAP_VERSION AND TAP_VERSION_NEW
echo "Comparing TAP versions..."
NOT_UPGRADING_TAP_MESSAGE="The specified TAP version is not higher than the current one specified in the var.conf file. Will not update TAP..."
versionlt $TAP_VERSION $TAP_VERSION_NEW && UPDATE_TAP=true || UPDATE_TAP=false

if $UPDATE_TAP ;
then

    for CLUSTER in $CLUSTERS_TO_UPDATE;
    do
        #VIEW CLUSTER
        echo "Updating TAP version in $CLUSTER cluster from $TAP_VERSION to $TAP_VERSION_NEW..."
        aws eks --region $aws_region update-kubeconfig --name $CLUSTER
        tanzu package repository add tanzu-tap-repository --url ${INSTALL_REGISTRY_HOSTNAME}/${INSTALL_REPO}/tap-packages:$TAP_VERSION_NEW --namespace $TAP_NAMESPACE
        tanzu package repository get tanzu-tap-repository -n tap-install
        
        # IF UPGRADING TO VERSION HIGHER OR EQUAL 1.7, DELETE learningcenter from the values file, if it exists:
        versionlte 1.7.0 $TAP_VERSION && yq 'del(.learningcenter)' $CLUSTER-values.yaml > $CLUSTER-values.yaml

        tanzu package installed update tap -p tap.tanzu.vmware.com -v ${TAP_VERSION_NEW}  --values-file $CLUSTER-values.yaml -n tap-install    
    done
   
    echo -e "\n All TAP clusters were successfully updated!"
    echo "Updating var.conf file with new TAP version..."
    sed -i "s/^TAP_VERSION=.*/TAP_VERSION=$TAP_VERSION_NEW/" var.conf

else
    echo $NOT_UPGRADING_TAP_MESSAGE
fi
