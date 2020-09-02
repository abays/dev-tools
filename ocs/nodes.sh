#!/bin/bash

delete_vbmc() {
    local name="$1"

    if vbmc show "$name" > /dev/null 2>&1; then
        vbmc stop "$name" > /dev/null 2>&1
        vbmc delete "$name" > /dev/null 2>&1
    fi
}

create_vbmc() {
    local name="$1"
    local port="$2"

    vbmc add "$name" --port "$port" --username ADMIN --password ADMIN
    vbmc start "$name" > /dev/null 2>&1

    sudo firewall-cmd --add-port="$port"/udp --zone=public
    sudo firewall-cmd --add-port="$port"/udp --zone=public --permanent
}



for i in {0..2}; do
    name="ostest-storage-$i"

    delete_vbmc "$name"
    sudo virsh destroy $name > /dev/null 2>&1
    sudo virsh vol-delete $name.qcow2 --pool=default
    sudo virsh undefine $name

    sudo virt-install --ram 41943040 --vcpus 12 --os-variant rhel8.0 --cpu host-passthrough --disk size=60,pool=default,device=disk,bus=virtio,format=qcow2 --import --noautoconsole --vnc --network=bridge:provisioning,mac="52:54:00:82:68:6$i" --network=bridge:baremetal,mac="52:54:00:82:69:6$i" --name "$name" --os-type=linux --events on_reboot=restart --boot hd,network

    vm_ready=false
    for k in {1..10}; do 
        if [[ -n "$(sudo virsh list | grep $name | grep running)" ]]; then 
            vm_ready=true
            break; 
        else 
            echo "wait $k"; 
            sleep 1; 
        fi;  
    done
    if [ $vm_ready = true ]; then 
        create_vbmc "$name" "626$i"

        # sudo firewall-cmd --zone=public --add-port=626$i/udp --permanent
        # sudo firewall-cmd --reload

        sleep 2

        ipmi_output=$(ipmitool -I lanplus -U ADMIN -P ADMIN -H 127.0.0.1 -p "626$i" power off)

        RETRIES=0

        while [[ "$ipmi_output" != "Chassis Power Control: Down/Off" ]]; do
            if [[ $RETRIES -ge 2 ]]; then
                echo "FAIL: Unable to start $name vBMC!"
                exit 1
            fi

            echo "IPMI failure detected -- trying to start $name vBMC again..."
            vbmc start "$name" > /dev/null 2>&1
            sleep 1
            ipmi_output=$(ipmitool -I lanplus -U ADMIN -P ADMIN -H 127.0.0.1 -p "626$i" power off)
            RETRIES=$((RETRIES+1))
        done

        echo "$name vBMC started and IPMI command succeeded!"
    fi
done

for i in {1..4}; do
  parted /dev/sdb rm $i;
done

parted /dev/sdb mkpart primary ext2 0% 10%
        parted /dev/sdb mkpart primary ext2 10% 20%
        parted /dev/sdb mkpart primary ext2 20% 30%
        parted /dev/sdb mkpart extended 30% 100%
        parted /dev/sdb mkpart logical ext2 40% 50%
        parted /dev/sdb mkpart logical ext2 50% 60%
        parted /dev/sdb mkpart logical ext2 60% 70%
        parted /dev/sdb mkpart logical ext2 70% 80%
        parted /dev/sdb mkpart logical ext2 80% 90%
        parted /dev/sdb mkpart logical ext2 90% 100%

virsh attach-disk ostest-storage-0 --source /dev/sdb1 --target vdb --persistent
virsh attach-disk ostest-storage-0 --source /dev/sdb2 --target vdc --persistent
virsh attach-disk ostest-storage-0 --source /dev/sdb3 --target vdd --persistent

virsh attach-disk ostest-storage-1 --source /dev/sdb5 --target vdb --persistent
virsh attach-disk ostest-storage-1 --source /dev/sdb6 --target vdc --persistent
virsh attach-disk ostest-storage-1 --source /dev/sdb7 --target vdd --persistent

virsh attach-disk ostest-storage-2 --source /dev/sdb8 --target vdb --persistent
virsh attach-disk ostest-storage-2 --source /dev/sdb9 --target vdc --persistent
virsh attach-disk ostest-storage-2 --source /dev/sdb10 --target vdd --persistent

DHCP_UPDATED=$(grep storage /home/ocp/dev-scripts/dhcp/generated/bm/etc/dnsmasq.d/dnsmasq.hostsfile)

if [[ -z "$DHCP_UPDATED" ]]; then
  printf "\n52:54:00:82:69:60,10.0.1.140,ostest-storage-0.ostest.test.metalkube.org\n52:54:00:82:69:61,10.0.1.141,ostest-storage-1.ostest.test.metalkube.org\n52:54:00:82:69:62,10.0.1.142,ostest-storage-2.ostest.test.metalkube.org\n" >> /home/ocp/dev-scripts/dhcp/generated/bm/etc/dnsmasq.d/dnsmasq.hostsfile
fi

podman stop ipi-dnsmasq-bm
podman start ipi-dnsmasq-bm

DNS_UPDATED=$(grep storage /home/ocp/dev-scripts/dns/generated/db.reverse)

if [[ -z "DNS_UPDATED" ]]; then
  printf "\n140 IN  PTR ostest-storage-0.ostest.test.metalkube.org.\n141 IN  PTR ostest-storage-1.ostest.test.metalkube.org.\n142 IN  PTR ostest-storage-2.ostest.test.metalkube.org.\n" >> /home/ocp/dev-scripts/dns/generated/db.reverse
  printf "\nostest-storage-0                          A 10.0.1.140\nostest-storage-1                          A 10.0.1.141\nostest-storage-2                          A 10.0.1.142\n" >> /home/ocp/dev-scripts/dns/generated/db.zone 
fi

su - ocp bash -c "podman stop ipi-coredns"
su - ocp bash -c "podman start ipi-coredns"

delete_nodes() {
    CLUSTER_NAME=ostest

    #
    # Scale-down machinset to destroy nodes
    #

    printf "\n>>>>> Scaling down machineset %s-storage-0 to 0...\n" "$CLUSTER_NAME"

    oc scale machineset/"$CLUSTER_NAME"-storage-0 --replicas=0  -n openshift-machine-api

    echo "Waiting for $CLUSTER_NAME storage baremetal hosts to de-provision..."

    COUNT_TOTAL="$(oc get bmh -n openshift-machine-api | grep -c storage-)"
    COUNT_READY="$(oc get bmh -n openshift-machine-api | grep storage- | grep -c ready)"

    while [[ "$COUNT_TOTAL" != "$COUNT_READY" ]]; do
        COUNT_READY="$(oc get bmh -n openshift-machine-api | grep storage- | grep -c ready)"
        sleep 5
    done

    echo "<<<<< Machineset $CLUSTER_NAME-storage-0 finished down-scaled to 0!"

    #
    # Delete baremetal hosts
    #

    printf "\n>>>>> Deleting %s storage baremetal hosts...\n" "$CLUSTER_NAME"

    for i in {0..2}; do
      oc delete bmh/$CLUSTER_NAME-storage-$i -n openshift-machine-api
    done

    echo "Waiting for $CLUSTER_NAME storage baremetal hosts to be deleted..."

    while [[ "$COUNT_TOTAL" != "0" ]]; do
        COUNT_TOTAL="$(oc get bmh -n openshift-machine-api | grep -c storage-)"
        sleep 5
    done

    echo "<<<<< $CLUSTER_NAME storage baremetal hosts deleted!"

    #
    # Delete machineset
    #

    printf "\n>>>>> Deleting machineset %s-storage-0...\n" "$CLUSTER_NAME"

    oc delete machineset/$CLUSTER_NAME-storage-0 -n openshift-machine-api

    echo "Waiting for machineset $CLUSTER_NAME-storage-0 to disappear..."

    SUCCESS="$(oc get machineset -n openshift-machine-api | grep $CLUSTER_NAME-storage-0)"

    while [[ -n "$SUCCESS" ]]; do
        SUCCESS="$(oc get machineset -n openshift-machine-api | grep $CLUSTER_NAME-storage-0)"
        sleep 5
    done

    echo "<<<<< Machineset $CLUSTER_NAME-storage-0 deleted!"
}

delete_nodes

create_nodes() {
    CLUSTER_NAME=ostest

    #
    # Create machineset
    #

    printf "\n>>>>> Creating machineset %s-storage-0...\n" "$CLUSTER_NAME"

    oc apply -f machineset.yaml -n openshift-machine-api

    echo "Waiting for machineset $CLUSTER_NAME-storage-0 to appear..."

    SUCCESS="$(oc get machineset -n openshift-machine-api | grep $CLUSTER_NAME-storage-0)"

    while [[ -z "$SUCCESS" ]]; do
        SUCCESS="$(oc get machineset -n openshift-machine-api | grep $CLUSTER_NAME-storage-0)"
        sleep 5
    done

    echo "<<<<< Machineset $CLUSTER_NAME-storage-0 ready!"

    #
    # Create baremetal hosts
    # 

    printf "\n>>>>> Creating %s storage baremetal hosts...\n" "$CLUSTER_NAME"

    oc apply -f bmhs.yaml -n openshift-machine-api

    echo "Waiting for $CLUSTER_NAME storage baremetal hosts to become ready..."

    COUNT_TOTAL="$(oc get bmh -n openshift-machine-api | grep -c storage-)"
    COUNT_READY="$(oc get bmh -n openshift-machine-api | grep storage- | grep -c ready)"

    while [[ "$COUNT_TOTAL" != "$COUNT_READY" ]]; do
        COUNT_READY="$(oc get bmh -n openshift-machine-api | grep storage- | grep -c ready)"
        sleep 5
    done

    echo "<<<<< $CLUSTER_NAME storage baremetal hosts ready!"

    #
    # Scale machineset to deploy nodes
    #

    printf "\n>>>>> Scaling machineset %s-storage-0 to %s...\n" "$CLUSTER_NAME" "$COUNT_TOTAL"

    oc scale machineset/"$CLUSTER_NAME"-storage-0 --replicas=3  -n openshift-machine-api

    echo "Waiting for $CLUSTER_NAME storage baremetal hosts to provision..."

    COUNT_PROVISIONED="$(oc get bmh -n openshift-machine-api | grep storage- | grep -c provisioned)"

    while [[ "$COUNT_TOTAL" != "$COUNT_PROVISIONED" ]]; do
        COUNT_PROVISIONED="$(oc get bmh -n openshift-machine-api | grep storage- | grep -c provisioned)"
        sleep 5
    done

    echo "<<<<< Machineset $CLUSTER_NAME-storage-0 finished scaling to $COUNT_TOTAL!"

    #
    # Wait for nodes to become ready
    #

    printf "\n>>>>> Waiting for %s storage nodes to reach the ready state...\n" "$CLUSTER_NAME"

    COUNT_READY="$(oc get nodes | grep "storage,worker" | grep -c -v NotReady)"

    while [[ "$COUNT_TOTAL" != "$COUNT_READY" ]]; do
        COUNT_READY="$(oc get nodes | grep "storage,worker" | grep -c -v NotReady)"
        sleep 5
    done

    echo "<<<<< $CLUSTER_NAME storage nodes are ready!"
}

create_nodes
