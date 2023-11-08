#!/bin/bash
# Copyright 2022 VMware, Inc.
# SPDX-License-Identifier: BSD-2-Clause
get_lb_svc_hotname(){ 
    LB_DNS_NAME=\"$(kubectl get svc -n tanzu-system-ingress envoy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')\"
    echo $LB_DNS_NAME
}

get_alb_zone_id(){
    aws elb describe-load-balancers | jq ".LoadBalancerDescriptions[] | select(.DNSName == $1) | .CanonicalHostedZoneNameID"
}

get_nlb_zone_id(){
    aws elbv2 describe-load-balancers | jq ".LoadBalancers[] | select(.DNSName == $1) | .CanonicalHostedZoneId"
}

get_route53_hosted_zone_id(){
    aws route53 list-hosted-zones | jq ".HostedZones[] | select(.Name | contains($1)) | .Id"
}

get_base_domain_from_full_domain(){
    BASE_DOMAIN=\"$(echo $1 | awk -F. '{print $(NF-1)"."$NF}')\"
    echo $BASE_DOMAIN
}

source var.conf
# TAP RUN DNS RECORDS

echo "login to run cluster to obtain envoy service LB information:"
aws eks --region $aws_region update-kubeconfig --name $TAP_RUN_CLUSTER_NAME

export NLB_DNS_NAME_TAP_RUN=$(get_lb_svc_hotname)
export NLB_ZONE_ID_TAP_RUN=$(get_nlb_zone_id $NLB_DNS_NAME_TAP_RUN)

#replace tap_full_domain by MAIN_FQDN
BASE_DOMAIN=$(get_base_domain_from_full_domain $tap_run_domain)
#to be exported
export FULL_DOMAIN_TAP_RUN=\"*.${tap_run_domain}\"
export ROUTE53_HOSTED_ZONE_ID_TAP_RUN=$(get_route53_hosted_zone_id $BASE_DOMAIN)


# TAP ITERATE DNS RECORDS

echo "login to iterate cluster to obtain envoy service LB information:"
aws eks --region $aws_region update-kubeconfig --name $TAP_ITERATE_CLUSTER_NAME

export ALB_DNS_NAME_TAP_ITERATE=$(get_lb_svc_hotname)
export ALB_ZONE_ID_TAP_ITERATE=$(get_alb_zone_id $ALB_DNS_NAME_TAP_ITERATE)

#replace tap_full_domain by MAIN_FQDN
BASE_DOMAIN=\"$(echo $tap_iterate_domain | awk -F. '{print $(NF-1)"."$NF}')\"
    
#to be exported
export FULL_DOMAIN_TAP_ITERATE=\"*.${tap_iterate_domain}\"
export ROUTE53_HOSTED_ZONE_ID_TAP_ITERATE=$(get_route53_hosted_zone_id $BASE_DOMAIN)


# TAP VIEW DNS RECORDS

echo "login to view cluster to obtain envoy service LB information:"
aws eks --region $aws_region update-kubeconfig --name $TAP_VIEW_CLUSTER_NAME

export ALB_DNS_NAME_TAP_VIEW=$(get_lb_svc_hotname)
export ALB_ZONE_ID_TAP_VIEW=$(get_alb_zone_id $ALB_DNS_NAME_TAP_VIEW)

#replace tap_full_domain by MAIN_FQDN
BASE_DOMAIN=\"$(echo $tap_view_domain | awk -F. '{print $(NF-1)"."$NF}')\"
    
#to be exported
export FULL_DOMAIN_TAP_VIEW=\"*.${tap_view_domain}\"
export ROUTE53_HOSTED_ZONE_ID_TAP_VIEW=$(get_route53_hosted_zone_id $BASE_DOMAIN)


# VARIABLE REPLACEMENT IN TERRAFORM TFVARS TEMPLATE

envsubst < ./terraform_dns/terraform.tfvars.template > ./terraform_dns/terraform.tfvars

cd terraform_dns
terraform init
terraform apply -auto-approve