#!/bin/bash
# Copyright 2022 VMware, Inc.
# SPDX-License-Identifier: BSD-2-Clause
source var.conf

#kubectl config get-contexts
#read -p "Target EKS Context: " target_context

#kubectl config use-context $target_context


#export TAP_NAMESPACE="tap-install"
export TAP_REGISTRY_USER=$registry_user
export TAP_REGISTRY_SERVER_ORIGINAL=$registry_url
if [ $registry_url = "${DOCKERHUB_REGISTRY_URL}" ]
then
  export TAP_REGISTRY_SERVER=$TAP_REGISTRY_USER
  export TAP_REGISTRY_REPOSITORY=$TAP_REGISTRY_USER
else
  export TAP_REGISTRY_SERVER=$registry_url
  export TAP_REGISTRY_REPOSITORY="supply-chain"
fi
export TAP_REGISTRY_PASSWORD=$registry_password
#export TAP_VERSION=1.1.0
export INSTALL_REGISTRY_USERNAME=$tanzu_net_reg_user
export INSTALL_REGISTRY_PASSWORD=$tanzu_net_reg_password

#Shared Ingress is needed when not using custom certificates
SHARED_INGRESS_ISSUER_CONFIG=""
if [[ -z ${TLS_CERT_FILE} || -z ${TLS_KEY_FILE} ]] ; 
then
  SHARED_INGRESS_ISSUER_CONFIG=$'shared:\n  ingress_issuer: letsencrypt-http01-issuer'
fi

echo  "Installing TAP Packages!"

cat <<EOF | tee $TAP_BUILD_CLUSTER_NAME-values.yaml
profile: build
ceip_policy_disclosed: true
${SHARED_INGRESS_ISSUER_CONFIG}
excluded_packages:
  - contour.tanzu.vmware.com
buildservice:
  kp_default_repository: "${TAP_REGISTRY_SERVER}/build-service"
  kp_default_repository_secret:
    name: registry-credentials
    namespace: "${TAP_NAMESPACE}"
supply_chain: basic
ootb_supply_chain_basic:    
  registry:
    server: "${TAP_REGISTRY_SERVER_ORIGINAL}"
    repository: "${TAP_REGISTRY_REPOSITORY}"
  gitops:
    ssh_secret: ""
  cluster_builder: default
  service_account: default
grype:
  namespace: "default" 
  targetImagePullSecret: registry-credentials
  metadataStore:
    url: "http://metadata-store.${tap_view_domain}"
    caSecret:
        name: store-ca-cert
        importFromNamespace: metadata-store-secrets
    authSecret:
        name: store-auth-token
        importFromNamespace: metadata-store-secrets
scanning:
  metadataStore: {} # Deactivate the Supply Chain Security Tools - Store integration.
  
image_policy_webhook:
  allow_unmatched_images: true
  
appliveview_connector:
  backend:
    sslDeactivated: "true"
    ingressEnabled: "true"
    host: appliveview.$tap_view_domain

EOF

tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION --values-file $TAP_BUILD_CLUSTER_NAME-values.yaml -n "${TAP_NAMESPACE}"

# Create LetsEncrypt Certificate Issuer for the TAP Build profile IF NO custom certs are used
# These steps need to be done after TAP installation, as it depends on cert-manager
if [[ -z ${TLS_CERT_FILE} || -z ${TLS_KEY_FILE} ]] ; 
then
  echo  "Creating ClusterIssuer!"

  cat <<EOF | tee tap-build-clusterissuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-http01-issuer
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $CERTIFICATE_ADMIN_EMAIL
    privateKeySecretRef:
      name: letsencrypt-http01-issuer
    solvers:
    - http01:
        ingress:
          class: contour
          podTemplate:
            spec:
              serviceAccountName: tap-acme-http01-solver
EOF
fi

kubectl apply -f tap-build-clusterissuer.yaml

tanzu package installed get tap -n "${TAP_NAMESPACE}"
# check all build cluster package installed succesfully
tanzu package installed list -A

# check ingress external ip
kubectl get svc -n tanzu-system-ingress