#!/bin/bash

sudo pip3 install yq

delete_ocs_cluster() {
    CLUSTER_NAME=ostest

    #
    # Delete OCS cluster
    #

    printf "\n>>>>> Deleting OCS cluster...\n"

    oc delete -f ocs-storage-cluster.yaml

    CEPH_MON_COUNT="$(oc get pods -n openshift-storage | grep -c rook-ceph-mon)"

    while [[ "$CEPH_MON_COUNT" != "0" ]]; do
        CEPH_MON_COUNT="$(oc get pods -n openshift-storage | grep -c rook-ceph-mon)"
        sleep 5
    done

    CEPH_OSD_COUNT="$(oc get pods -n openshift-storage | grep -c rook-ceph-osd)"

    while [[ "$CEPH_OSD_COUNT" != "0" ]]; do
        CEPH_OSD_COUNT="$(oc get pods -n openshift-storage | grep -c rook-ceph-osd)"
        sleep 5
    done

    echo "<<<<< OCS cluster deleted!"

    #
    # Delete OCS operator
    #

    printf "\n>>>>> Deleting OCS subscription and operators...\n"

    oc delete -f ocs-sub.yaml

    OCS_OPERATOR_COUNT="$(oc get pods -n openshift-storage | grep -c ocs-operator)"

    while [[ "$OCS_OPERATOR_COUNT" != "0" ]]; do
        OCS_OPERATOR_COUNT="$(oc get pods -n openshift-storage | grep -c ocs-operator)"
        sleep 5
    done

    CEPH_OPERATOR_COUNT="$(oc get pods -n openshift-storage | grep -c rook-ceph-operator)"

    while [[ "$CEPH_OPERATOR_COUNT" != "0" ]]; do
        CEPH_OPERATOR_COUNT="$(oc get pods -n openshift-storage | grep -c rook-ceph-operator)"
        sleep 5
    done

    NOOBAA_OPERATOR_COUNT="$(oc get pods -n openshift-storage | grep -c noobaa-operator)"

    while [[ "$NOOBAA_OPERATOR_COUNT" != "0" ]]; do
        NOOBAA_OPERATOR_COUNT="$(oc get pods -n openshift-storage | grep -c noobaa-operator)"
        sleep 5
    done

    FS_PLUGIN_COUNT="$(oc get pods -n openshift-storage | grep -v csi-cephfsplugin-provisioner | grep -c csi-cephfsplugin)"

    while [[ "$FS_PLUGIN_COUNT" != "0" ]]; do
        FS_PLUGIN_COUNT="$(oc get pods -n openshift-storage | grep -v csi-cephfsplugin-provisioner | grep -c csi-cephfsplugin)"
        sleep 5
    done

    RBD_PLUGIN_COUNT="$(oc get pods -n openshift-storage | grep -v csi-rbdplugin-provisioner | grep -c csi-rbdplugin)"

    while [[ "$RBD_PLUGIN_COUNT" != "0" ]]; do
        RBD_PLUGIN_COUNT="$(oc get pods -n openshift-storage | grep -v csi-rbdplugin-provisioner | grep -c csi-rbdplugin)"
        sleep 5
    done

    echo "<<<<< OCS operators deleted!"
}

delete_local_storage() {
    CLUSTER_NAME=ostest

    #
    # Delete local storage volumes
    #

    printf "\n>>>>> Deleting local storage PVs...\n"

    oc delete -f local-storage-volumes.yaml

    for i in $(oc get pv | grep local-pv | awk {'print $1'}); do
        oc delete pv/$i
    done

    PV_COUNT="$(oc get pv | grep -c local-pv)"

    while [[ "$PV_COUNT" != "0" ]]; do
        PV_COUNT="$(oc get pv | grep -c local-pv)"
    done

    echo "<<<<< Local storage PVs deleted!"

    #
    # Delete local storage operator
    #

    printf "\n>>>>> Deleting local storage subscription and operator...\n"

    oc delete -f local-storage-sub.yaml

    LOCAL_STORAGE_OPERATOR_COUNT="$(oc get pods -n local-storage | grep -c local-storage-operator)"

    while [[ "$LOCAL_STORAGE_OPERATOR_COUNT" != "0" ]]; do
        LOCAL_STORAGE_OPERATOR_COUNT="$(oc get pods -n local-storage | grep -c local-storage-operator)"
        sleep 5
    done

    oc delete project/local-storage

    echo "<<<<< Local storage operator deleted!"

    #
    # Remove storage label from storage nodes
    #

    printf "\n>>>>> Removing 'cluster.ocs.openshift.io/openshift-storage' label from %s storage nodes...\n" "$CLUSTER_NAME"

    for i in $(oc get nodes | grep storage | awk {'print $1'}); do
        oc label nodes "$i" cluster.ocs.openshift.io/openshift-storage-
    done

    echo "<<<<< Labeling of $CLUSTER_NAME storage nodes deleted!"
}

create_local_storage() {
    CLUSTER_NAME=ostest

    printf "\n>>>>> Labeling %s storage nodes as 'cluster.ocs.openshift.io/openshift-storage'...\n" "$CLUSTER_NAME"

    for i in $(oc get nodes | grep storage | awk {'print $1'}); do
        oc label nodes "$i" cluster.ocs.openshift.io/openshift-storage=''
    done

    echo "<<<<< Labeling $CLUSTER_NAME storage nodes done!"

    #
    # Deploy local storage operator
    #

    printf "\n>>>>> Creating local storage subscription and deploying operator...\n"

    oc new-project local-storage
    oc annotate project local-storage openshift.io/node-selector=''

    oc apply -f local-storage-sub.yaml

    COUNT_RUNNING="$(oc get pods -n local-storage | grep local-storage-operator | grep -c Running)"

    while [[ "$COUNT_RUNNING" != "1" ]]; do
        COUNT_RUNNING="$(oc get pods -n local-storage | grep local-storage-operator | grep -c Running)"
        sleep 5
    done

    echo "<<<<< Local storage operator ready!"

    #
    # Create local storage volumes
    #

    printf "\n>>>>> Creating local storage PVs...\n"

    oc apply -f local-storage-volumes.yaml

    PV_COUNT_TOTAL="$(($(($(yq '.spec.storageClassDevices[0].devicePaths' local-storage-volumes.yaml | wc -l)-2))*$(($(grep -c "kind: BareMetalHost" bmhs.yaml)))))"
    PV_COUNT_GOOD="$(($(oc get pv | grep local-pv | grep -c Available)+$(oc get pv | grep local-pv | grep -c Bound)))"

    while [[ "$PV_COUNT_GOOD" != "$PV_COUNT_TOTAL" ]]; do
        PV_COUNT_GOOD="$(($(oc get pv | grep local-pv | grep -c Available)+$(oc get pv | grep local-pv | grep -c Bound)))"
        sleep 5
    done

    echo "<<<<< Local storage PVs ready!"
}

create_ocs_cluster() {
    CLUSTER_NAME=ostest

    #
    # Deploy OCS operator
    #

    printf "\n>>>>> Creating OCS subscription and deploying operators...\n"

    oc apply -f ocs-sub.yaml

    COUNT_RUNNING="$(oc get pods -n openshift-storage | grep ocs-operator | grep -c Running)"

    while [[ "$COUNT_RUNNING" != "1" ]]; do
        COUNT_RUNNING="$(oc get pods -n openshift-storage | grep ocs-operator | grep -c Running)"
        sleep 5
    done

    COUNT_RUNNING="$(oc get pods -n openshift-storage | grep rook-ceph-operator | grep -c Running)"

    while [[ "$COUNT_RUNNING" != "1" ]]; do
        COUNT_RUNNING="$(oc get pods -n openshift-storage | grep rook-ceph-operator | grep -c Running)"
        sleep 5
    done

    COUNT_RUNNING="$(oc get pods -n openshift-storage | grep noobaa-operator | grep -c Running)"

    while [[ "$COUNT_RUNNING" != "1" ]]; do
        COUNT_RUNNING="$(oc get pods -n openshift-storage | grep noobaa-operator | grep -c Running)"
        sleep 5
    done

    echo "<<<<< OCS operators ready!"

    #
    # Deploy OCS cluster
    #

    printf "\n>>>>> Deploying OCS cluster...\n"

    oc apply -f ocs-storage-cluster.yaml

    NODE_COUNT="$(oc get nodes | grep -v NAME | wc -l)"
    STORAGE_DEVICE_COUNT="$(yq '.spec.storageDeviceSets[0].count' ocs-storage-cluster.yaml)"
    STORAGE_DEVICE_REPLICAS="$(yq '.spec.storageDeviceSets[0].replicas' ocs-storage-cluster.yaml)"

    FS_PLUGIN_COUNT="$(oc get pods -n openshift-storage | grep csi-cephfsplugin | grep -v csi-cephfsplugin-provisioner | grep -c Running)"

    while [[ "$FS_PLUGIN_COUNT" != "$NODE_COUNT" ]]; do
        FS_PLUGIN_COUNT="$(oc get pods -n openshift-storage | grep csi-cephfsplugin | grep -v csi-cephfsplugin-provisioner | grep -c Running)"
        sleep 5
    done

    RBD_PLUGIN_COUNT="$(oc get pods -n openshift-storage | grep csi-rbdplugin | grep -v csi-rbdplugin-provisioner | grep -c Running)"

    while [[ "$RBD_PLUGIN_COUNT" != "$NODE_COUNT" ]]; do
        RBD_PLUGIN_COUNT="$(oc get pods -n openshift-storage | grep csi-rbdplugin | grep -v csi-rbdplugin-provisioner | grep -c Running)"
        sleep 5
    done

    CEPH_MON_COUNT="$(oc get pods -n openshift-storage | grep rook-ceph-mon | grep -c Running)"

    while [[ "$CEPH_MON_COUNT" != "$STORAGE_DEVICE_COUNT" ]]; do
        CEPH_MON_COUNT="$(oc get pods -n openshift-storage | grep rook-ceph-mon | grep -c Running)"
        sleep 5
    done

    CEPH_OSD_COUNT="$(oc get pods -n openshift-storage | grep rook-ceph-osd | grep -v prepare | grep -c Running)"

    while [[ "$CEPH_OSD_COUNT" != "$((STORAGE_DEVICE_COUNT*STORAGE_DEVICE_REPLICAS))" ]]; do
        CEPH_OSD_COUNT="$(oc get pods -n openshift-storage | grep rook-ceph-osd | grep -v prepare | grep -c Running)"
        sleep 5
    done

    echo "<<<<< OCS cluster deployed!"
}

if [[ "$1" != "clean" ]]; then
    create_local_storage
    create_ocs_cluster
else
    delete_ocs_cluster
    delete_local_storage
fi
