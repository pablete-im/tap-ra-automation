#!/bin/bash
# Copyright 2022 VMware, Inc.
# SPDX-License-Identifier: BSD-2-Clause
source var.conf

cat <<EOF | tee tap-gui-viewer-service-account-rbac.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: tap-gui
---
apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: tap-gui
  name: tap-gui-viewer
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tap-gui-read-k8s
subjects:
- kind: ServiceAccount
  namespace: tap-gui
  name: tap-gui-viewer
roleRef:
  kind: ClusterRole
  name: k8s-reader
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k8s-reader
rules:
- apiGroups: ['']
  resources: ['pods', 'pods/log', 'services', 'configmaps', 'limitranges']
  verbs: ['get', 'watch', 'list']
- apiGroups: ['metrics.k8s.io']
  resources: ['pods']
  verbs: ['get', 'watch', 'list']
- apiGroups: ['apps']
  resources: ['deployments', 'replicasets', 'statefulsets', 'daemonsets']
  verbs: ['get', 'watch', 'list']
- apiGroups: ['autoscaling']
  resources: ['horizontalpodautoscalers']
  verbs: ['get', 'watch', 'list']
- apiGroups: ['networking.k8s.io']
  resources: ['ingresses']
  verbs: ['get', 'watch', 'list']
- apiGroups: ['networking.internal.knative.dev']
  resources: ['serverlessservices']
  verbs: ['get', 'watch', 'list']
- apiGroups: [ 'autoscaling.internal.knative.dev' ]
  resources: [ 'podautoscalers' ]
  verbs: [ 'get', 'watch', 'list' ]
- apiGroups: ['serving.knative.dev']
  resources:
  - configurations
  - revisions
  - routes
  - services
  verbs: ['get', 'watch', 'list']
- apiGroups: ['carto.run']
  resources:
  - clusterconfigtemplates
  - clusterdeliveries
  - clusterdeploymenttemplates
  - clusterimagetemplates
  - clusterruntemplates
  - clustersourcetemplates
  - clustersupplychains
  - clustertemplates
  - deliverables
  - runnables
  - workloads
  verbs: ['get', 'watch', 'list']
- apiGroups: ['source.toolkit.fluxcd.io']
  resources:
  - gitrepositories
  verbs: ['get', 'watch', 'list']
- apiGroups: ['source.apps.tanzu.vmware.com']
  resources:
  - imagerepositories
  - mavenartifacts
  verbs: ['get', 'watch', 'list']
- apiGroups: ['conventions.apps.tanzu.vmware.com']
  resources:
  - podintents
  verbs: ['get', 'watch', 'list']
- apiGroups: ['kpack.io']
  resources:
  - images
  - builds
  verbs: ['get', 'watch', 'list']
- apiGroups: ['scanning.apps.tanzu.vmware.com']
  resources:
  - sourcescans
  - imagescans
  - scanpolicies
  - scantemplates
  verbs: ['get', 'watch', 'list']
- apiGroups: ['app-scanning.apps.tanzu.vmware.com']
  resources:
  - imagevulnerabilityscans
  verbs: ['get', 'watch', 'list']
- apiGroups: ['tekton.dev']
  resources:
  - taskruns
  - pipelineruns
  verbs: ['get', 'watch', 'list']
- apiGroups: ['kappctrl.k14s.io']
  resources:
  - apps
  verbs: ['get', 'watch', 'list']
- apiGroups: [ 'batch' ]
  resources: [ 'jobs', 'cronjobs' ]
  verbs: [ 'get', 'watch', 'list' ]
- apiGroups: ['conventions.carto.run']
  resources:
  - podintents
  verbs: ['get', 'watch', 'list']
- apiGroups: ['appliveview.apps.tanzu.vmware.com']
  resources:
  - resourceinspectiongrants
  verbs: ['get', 'watch', 'list', 'create']

EOF

#switch to tap build cluster to get token 
echo "login to build cluster to apply tap-gui-viewer-service-account-rbac.yaml"
aws eks --region $aws_region update-kubeconfig --name ${TAP_BUILD_CLUSTER_NAME}
kubectl apply -f tap-gui-viewer-service-account-rbac.yaml

CLUSTER_URL_BUILD=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: tap-gui-viewer
  namespace: tap-gui
  annotations:
    kubernetes.io/service-account.name: tap-gui-viewer
type: kubernetes.io/service-account-token
EOF

CLUSTER_TOKEN_BUILD=$(kubectl -n tap-gui get secret tap-gui-viewer -o=json \
| jq -r '.data["token"]' \
| base64 --decode)

#switch to tap run cluster to get token 
echo "login to run cluster to apply tap-gui-viewer-service-account-rbac.yaml"
aws eks --region $aws_region update-kubeconfig --name ${TAP_RUN_CLUSTER_NAME}
kubectl apply -f tap-gui-viewer-service-account-rbac.yaml

CLUSTER_URL_RUN=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: tap-gui-viewer
  namespace: tap-gui
  annotations:
    kubernetes.io/service-account.name: tap-gui-viewer
type: kubernetes.io/service-account-token
EOF


CLUSTER_TOKEN_RUN=$(kubectl -n tap-gui get secret tap-gui-viewer -o=json \
| jq -r '.data["token"]' \
| base64 --decode)

echo  "Login to View Cluster !!! "
#login to kubernets eks view cluster
aws eks --region $aws_region update-kubeconfig --name ${TAP_VIEW_CLUSTER_NAME}

echo CLUSTER_URL_RUN: $CLUSTER_URL_RUN
echo CLUSTER_TOKEN_RUN: $CLUSTER_TOKEN_RUN

echo CLUSTER_URL_BUILD: $CLUSTER_URL_BUILD
echo CLUSTER_TOKEN_BUILD: $CLUSTER_TOKEN_BUILD

# TLS CERTIFICATES
kubectl create ns api-portal
kubectl create ns tap-gui
kubectl create ns app-live-view
kubectl create ns metadata-store
kubectl create ns learningcenter

API_PORTAL_OVERLAY_CONFIG=""
TAP_GUI_TLS_CONFIG=""
APP_LIVE_VIEW_TLS_CONFIG=""
METADATA_STORE_TLS_CONFIG=""
SHARED_INGRESS_ISSUER_CONFIG=""
if [[ -n ${TLS_CERT_FILE} && -n ${TLS_KEY_FILE} ]] ; 
then
  echo  "Creating configurations for custom wildcard certificate!"
  # If Custom wildcard certificate is used, configure secrets on a per-component basis
  ## api-portal
  kubectl create secret tls api-portal-cert --cert $TLS_CERT_FILE --key $TLS_KEY_FILE -n api-portal;
  kubectl apply -f - <<APIPORTALCUSTOM
apiVersion: v1
kind: Secret
metadata:
  name: api-portal-httpproxy-overlay
  namespace: tap-install
stringData:
  api-portal-httpproxy-overlay.yaml: |
    #@ load("@ytt:overlay", "overlay")
    #@overlay/match by=overlay.subset({"apiVersion": "projectcontour.io/v1", "kind": "HTTPProxy","metadata":{"name":"api-portal"}}),    expects="0+"
    ---
    spec:
      #@overlay/match-child-defaults missing_ok=True
      virtualhost:
        tls:
          secretName: api-portal-cert 
APIPORTALCUSTOM
  PACKAGE_OVERLAYS_CONFIG=$'package_overlays:\n  - name: "api-portal"\n    secrets:\n    - name: "api-portal-httpproxy-overlay"'
  ## tap-gui
  kubectl create secret tls tap-gui-cert --cert $TLS_CERT_FILE --key $TLS_KEY_FILE -n tap-gui;
  TAP_GUI_TLS_CONFIG=$'  tls:\n    namespace: tap-gui\n    secretName: tap-gui-cert'
  ## app-live-view
  kubectl create secret tls app-live-view-cert --cert $TLS_CERT_FILE --key $TLS_KEY_FILE -n app-live-view;
  APP_LIVE_VIEW_TLS_CONFIG=$'  tls:\n    namespace: app-live-view\n    secretName: app-live-view-cert'
  ## metadata-store
  kubectl create secret tls metadata-store-cert --cert $TLS_CERT_FILE --key $TLS_KEY_FILE -n metadata-store;
  METADATA_STORE_TLS_CONFIG=$'  tls:\n    namespace: metadata-store\n    secretName: metadata-store-cert'
  ## learning-center
  kubectl create secret tls learning-center-cert-secret --cert $TLS_CERT_FILE --key $TLS_KEY_FILE -n learningcenter;

else
  echo  "Creating secrets and service accounts for the default lets encrypt ClusterIssuer!"
  # If Custom wilcard certificate is not used, we need to create Secrets and SAs for the 
  # Cluster Issuer HTTP01 challenge pods
  ## api-portal
kubectl apply -f - <<APIPORTAL
apiVersion: v1
kind: Secret
metadata:
  name: tap-registry
  namespace: api-portal
  annotations:
    secretgen.carvel.dev/image-pull-secret: ""
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: e30K
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tap-acme-http01-solver
  namespace: api-portal 
imagePullSecrets:
 - name: tap-registry
APIPORTAL
  ## tap-gui
kubectl apply -f - <<TAPGUI
apiVersion: v1
kind: Secret
metadata:
  name: tap-registry
  namespace: tap-gui
  annotations:
    secretgen.carvel.dev/image-pull-secret: ""
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: e30K
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tap-acme-http01-solver
  namespace: tap-gui 
imagePullSecrets:
- name: tap-registry
TAPGUI
   ## app-live-view
kubectl apply -f - <<APPLIVEVIEW
apiVersion: v1
kind: Secret
metadata:
  name: tap-registry
  namespace: app-live-view
  annotations:
    secretgen.carvel.dev/image-pull-secret: ""
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: e30K
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tap-acme-http01-solver
  namespace: app-live-view 
imagePullSecrets:
 - name: tap-registry
APPLIVEVIEW
  ## metadata-store
kubectl apply -f - <<METADATASTORE
apiVersion: v1
kind: Secret
metadata:
  name: tap-registry
  namespace: metadata-store
  annotations:
    secretgen.carvel.dev/image-pull-secret: ""
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: e30K
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tap-acme-http01-solver
  namespace: metadata-store 
imagePullSecrets:
 - name: tap-registry
METADATASTORE
  ## learning-center
kubectl apply -f - <<LEARNINGCENTER
apiVersion: v1
kind: Secret
metadata:
  name: tap-registry
  namespace: learningcenter
  annotations:
    secretgen.carvel.dev/image-pull-secret: ""
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: e30K
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tap-acme-http01-solver
  namespace: learningcenter 
imagePullSecrets:
 - name: tap-registry
LEARNINGCENTER
  #Shared Ingress is needed when not using custom certificates
  SHARED_INGRESS_ISSUER_CONFIG="  ingress_issuer: letsencrypt-http01-issuer"
fi

# TAP PACKAGES CONFIGURATION
echo  "Installing TAP Packages!"
cat <<EOF | tee tap-values-view.yaml
profile: view
ceip_policy_disclosed: true

shared:
  ingress_domain: "${tap_view_domain}" 
${SHARED_INGRESS_ISSUER_CONFIG}
${PACKAGE_OVERLAYS_CONFIG}
contour:
  envoy:
    service:
      type: LoadBalancer
learningcenter:
  ingressDomain: "learning.${tap_view_domain}"
  ingressClass: contour
  ingressSecret:
    secretName: learning-center-cert-secret
tap_gui:
  service_type: ClusterIP
${TAP_GUI_TLS_CONFIG}
  app_config:
    catalog:
      locations:
        - type: url
          target: ${tap_git_catalog_url}     
    auth:
      allowGuestAccess: true
    kubernetes:
      serviceLocatorMethod:
        type: "multiTenant"
      clusterLocatorMethods:
        - type: "config"
          clusters:
            - url: $CLUSTER_URL_RUN
              name: $TAP_RUN_CLUSTER_NAME
              authProvider: serviceAccount
              skipTLSVerify: true
              skipMetricsLookup: true
              serviceAccountToken: $CLUSTER_TOKEN_RUN
            - url: $CLUSTER_URL_BUILD
              name: $TAP_BUILD_CLUSTER_NAME
              authProvider: serviceAccount
              skipTLSVerify: true
              skipMetricsLookup: true
              serviceAccountToken: $CLUSTER_TOKEN_BUILD

metadata_store:
  app_service_type: LoadBalancer
${METADATA_STORE_TLS_CONFIG}
appliveview:
  ingressEnabled: "true"
${APP_LIVE_VIEW_TLS_CONFIG}

EOF

tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION --values-file tap-values-view.yaml -n "${TAP_NAMESPACE}"

# Create LetsEncrypt Certificate Issuer for the TAP View profile IF NO custom certs are used
# Create Learning Center Certificate IF NO custom certs are used
# These steps need to be done after TAP installation, as it depends on cert-manager
if [[ -z ${TLS_CERT_FILE} || -z ${TLS_KEY_FILE} ]] ; 
then
  echo  "Creating ClusterIssuer and default certificate for Learning Center!"
  cat <<EOF | tee tap-view-clusterissuer.yaml
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
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  namespace: learningcenter
  name: learning-center-cert
spec:
  commonName: learningcenter-guided.learning.${tap_view_domain}
  dnsNames:
    - learningcenter-guided.learning.${tap_view_domain}
  issuerRef:
    name: letsencrypt-http01-issuer
    kind: ClusterIssuer
  secretName: learning-center-cert-secret
EOF
  kubectl apply -f tap-view-clusterissuer.yaml
fi

tanzu package installed get tap -n "${TAP_NAMESPACE}"
# ensure all view cluster packages are installed succesfully
tanzu package installed list -A

kubectl get svc -n tanzu-system-ingress

# pick an external ip from service output and configure DNS wildcard records
# example - *.ui.customer0.io ==> <ingress external ip/cname>