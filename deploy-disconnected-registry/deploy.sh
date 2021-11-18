#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
set -m

# variables
# #########
# uncomment it, change it or get it from gh-env vars (default behaviour: get from gh-env)echo 

echo ">>>> Enable internal registry"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>"

oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed"}}'; sleep 10
oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"pvc":{"claim":null}}}}'; sleep 10
oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge --patch '{"spec":{"defaultRoute":true}}'; sleep 30
echo ">>>> Get the pull secret from hub to file ./pull-secret.json"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"

oc get secret -n openshift-config pull-secret -ojsonpath='{.data.\.dockerconfigjson}' | base64 -d > ./pull-secret.json
PULL_SECRET=./pull-secret.json

echo ">>>> Get the registry cert and update pull secret"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
OPENSHIFT_RELEASE_IMAGE=$(oc get clusterversion -o jsonpath={'.items[0].status.desired.image'})
OCP_RELEASE=$(oc get clusterversion -o jsonpath={'.items[0].status.desired.version'})-x86_64
LOCAL_REG=$(oc get route -n openshift-image-registry | awk '{print $2}' | tail -1)
oc get secret -n openshift-ingress  router-certs-default -o go-template='{{index .data "tls.crt"}}' | base64 -d > /etc/pki/ca-trust/source/anchors/internal-registry.crt
update-ca-trust extract


sed -i "s%CHANGE_OCP_RELEASE%$OC_OCP_VERSION%g" olm-mirror.sh 
sed -i "s%CHANGE_PULLSECRET_FILE%$PULL_SECRET%g" olm-mirror.sh
sed -i "s%CHANGE_ROUTE_REGISTRY%$LOCAL_REG%g" olm-mirror.sh

#TODO: change user to avoid request the kubeadmin password
oc login -u kubeadmin -p $OC_KUBEADMIN_PASS_SECRET
export REGISTRY_NAME="$(oc get route -n openshift-image-registry default-route -o jsonpath={'.status.ingress[0].host'})"
podman login $REGISTRY_NAME -u kubeadmin -p $(oc whoami -t) --authfile=./pull-secret-internal-registry.json
oc logout ; oc config use-context admin
oc create ns ocp4

oc adm release mirror -a ./pull-secret-internal-registry.json --from="$OPENSHIFT_RELEASE_IMAGE" --to-release-image="${LOCAL_REG}"/ocp4/openshift4:"${OCP_RELEASE}" --to="${LOCAL_REG}"/ocp4/openshift4

echo ">>>>EOF"
echo ">>>>>>>"


