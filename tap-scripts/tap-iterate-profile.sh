#!/bin/bash
# Copyright 2022 VMware, Inc.
# SPDX-License-Identifier: BSD-2-Clause
source var.conf

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
export TAP_CNRS_DOMAIN=$tap_run_domain
export INSTALL_REGISTRY_USERNAME=$tanzu_net_reg_user
export INSTALL_REGISTRY_PASSWORD=$tanzu_net_reg_password

SHARED_INGRESS_ISSUER_CONFIG=""
CNRS_TLS_CONFIG=""
CNRS_INGRESS_CONFIG=""
if [[ -n ${TLS_CERT_FILE} && -n ${TLS_KEY_FILE} ]] ; 
then
  echo  "Creating configurations for custom wildcard certificate!"
  # If Custom wildcard certificate is used, configure secrets on a per-component basis
  ## cnrs
  kubectl create secret tls cnrs-cert --cert $TLS_CERT_FILE --key $TLS_KEY_FILE -n ${TAP_DEV_NAMESPACE};
  CNRS_TLS_CONFIG="  default_tls_secret: \"${TAP_DEV_NAMESPACE}/cnrs-cert\""
  CNRS_INGRESS_CONFIG='  ingress_issuer: ""'
else
  #Shared Ingress is needed when not using custom certificates
  SHARED_INGRESS_ISSUER_CONFIG=$'shared:\n  ingress_issuer: letsencrypt-http01-issuer'
  CNRS_INGRESS_CONFIG='  ingress_issuer: letsencrypt-http01-issuer'
fi

echo  "Installing TAP Packages!"
cat <<EOF | tee $TAP_ITERATE_CLUSTER_NAME-values.yaml

profile: iterate
ceip_policy_disclosed: true
${SHARED_INGRESS_ISSUER_CONFIG}
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

metadata_store:
  app_service_type: LoadBalancer

image_policy_webhook:
  allow_unmatched_tags: true

contour:
  envoy:
    service:
      type: LoadBalancer

cnrs:
  domain_name: "${tap_iterate_domain}"
${CNRS_INGRESS_CONFIG}
${CNRS_TLS_CONFIG}
EOF

tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION --values-file $TAP_ITERATE_CLUSTER_NAME-values.yaml -n "${TAP_NAMESPACE}"

# These steps need to be done after TAP installation, as it depends on cert-manager
if [[ -n ${TLS_CERT_FILE} && -n ${TLS_KEY_FILE} ]] ; 
then
  # Create TLSCertificateDelegation for CNRS for the TAP Iterate profile if custom certs are used
  echo "Creating TLSCertificateDelegation for CNRS..."
  cat <<EOF | tee tap-iterate-tlscertdelegation.yaml
apiVersion: projectcontour.io/v1
kind: TLSCertificateDelegation
metadata:
  name: default-delegation
  namespace: ${TAP_DEV_NAMESPACE}
spec:
  delegations:
    - secretName: cnrs-cert
      targetNamespaces:
        - "${TAP_DEV_NAMESPACE}"
EOF
  kubectl apply -f tap-iterate-tlscertdelegation.yaml
else
  # Create LetsEncrypt Certificate Issuer for the TAP Iterate profile IF NO custom certs are used
  echo  "Creating ClusterIssuer!"
  cat <<EOF | tee tap-iterate-clusterissuer.yaml
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
  kubectl apply -f tap-iterate-clusterissuer.yaml
fi

tanzu package installed get tap -n "${TAP_NAMESPACE}"
# check all iterate cluster package installed succesfully
tanzu package installed list -A

# check ingress external ip
kubectl get svc -n tanzu-system-ingress

#echo "pick external ip from service output  and configure DNS wild card(*) into your DNS server like aws route 53 etc"
#echo "example - *.iter.customer0.io ==> <ingress external ip/cname>"