#!/bin/bash
# Copyright 2022 VMware, Inc.
# SPDX-License-Identifier: BSD-2-Clause

#kubectl config get-contexts
#read -p "Target EKS Context: " target_context

#kubectl config use-context $target_context

#read -p "Enter custom registry url (harbor/azure registry etc): " registry_url
#read -p "Enter custom registry user: " registry_user
#read -p "Enter custom registry password: " registry_password
#read -p "Enter cnrs domain: " tap_cnrs_domain
#read -p "Enter app live view domain: " alv_domain

source var.conf

#export TAP_NAMESPACE="tap-install"
export TAP_REGISTRY_SERVER=$registry_url
export TAP_REGISTRY_USER=$registry_user
export TAP_REGISTRY_PASSWORD=$registry_password
export TAP_CNRS_DOMAIN=$tap_run_domain
##export TAP_VERSION=1.1.0

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
  SHARED_INGRESS_ISSUER_CONFIG='  ingress_issuer: letsencrypt-http01-issuer'
  CNRS_INGRESS_CONFIG='  ingress_issuer: letsencrypt-http01-issuer'

fi

echo  "Installing TAP Packages!"
cat <<EOF | tee $TAP_RUN_CLUSTER_NAME-values.yaml
profile: run
ceip_policy_disclosed: true
shared:
  ingress_domain: "${tap_run_domain}"
${SHARED_INGRESS_ISSUER_CONFIG}

supply_chain: basic

excluded_packages:
  - policy.apps.tanzu.vmware.com

contour:
  infrastructure_provider: aws
  envoy:
    service:
      aws:
        LBType: nlb
cnrs:
  domain_name: "${tap_run_domain}"
${CNRS_INGRESS_CONFIG}
${CNRS_TLS_CONFIG}

appliveview_connector:
  backend:
    sslDisabled: "true"
    ingressEnabled: "true"
    host: appliveview.$tap_view_domain


EOF

tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION --values-file $TAP_RUN_CLUSTER_NAME-values.yaml -n "${TAP_NAMESPACE}"

# These steps need to be done after TAP installation, as it depends on cert-manager
if [[ -n ${TLS_CERT_FILE} && -n ${TLS_KEY_FILE} ]] ; 
then
  # Create TLSCertificateDelegation for CNRS for the TAP Run profile if custom certs are used
  echo "Creating TLSCertificateDelegation for CNRS..."
  cat <<EOF | tee tap-run-tlscertdelegation.yaml
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
  kubectl apply -f tap-run-tlscertdelegation.yaml
else
  # Create LetsEncrypt Certificate Issuer for the TAP Run profile IF NO custom certs are used
  echo  "Creating ClusterIssuer!"
  cat <<EOF | tee tap-run-clusterissuer.yaml
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
  kubectl apply -f tap-run-clusterissuer.yaml
fi

tanzu package installed get tap -n "${TAP_NAMESPACE}"
# check all run cluster packages installed succesfully
tanzu package installed list -A

# check ingress external ip
kubectl get svc -n tanzu-system-ingress

#echo "pick external ip from service output  and configure DNS wild card(*) into your DNS server like aws route 53 etc"
#echo "example - *.run.customer0.io ==> <ingress external ip/cname>"

