default: \
  ocp_install \
  olm \
  #osp_operators_install \
  #osp_tests_run

all: default

hosts:
	echo -e "localhost ansible_connection=local\n\n[convergence_base]\nlocalhost" > $@

local-defaults.yaml:
	echo -e "vars:" > $@

local-deps:
	ansible-galaxy install -r requirements.yml

ocp_install: hosts local-deps local-defaults.yaml
	ANSIBLE_FORCE_COLOR=true ansible-playbook \
	-i hosts -e @local-defaults.yaml \
	01_prepare_host.yaml \
	03_ocp_dev_scripts.yaml \
	04_local_oc_client.yaml \
	05_default_storageclass.yaml \
	ocp_image_registry.yaml

osp_operators_install: hosts local-defaults.yaml
	ANSIBLE_FORCE_COLOR=true ansible-playbook \
	-i hosts -e @local-defaults.yaml \
	12_setup_worker_osp_machineset.yaml \

osp_tests_run: hosts local-defaults.yaml
	ANSIBLE_FORCE_COLOR=true ansible-playbook \
	-i hosts -e @local-defaults.yaml \
  20_tempest_ocp.yaml \

all_services=mariadb rabbitmq ovn keystone glance neutron-api nova-api nova-cell placement

# Run a specific install playbook without dependencies
install_%: install_%.yaml hosts local-defaults.yaml
	ANSIBLE_FORCE_COLOR=true ansible-playbook \
	-i hosts -e @local-defaults.yaml $<

# Run the install target for a playbook after running its dependencies
_dep_%:
	$(MAKE) install_$$(x="$@"; echo $${x#_dep_}) 

_dep_all=$(patsubst %,_dep_%,$(all_services))

# Define deployment dependencies between control plane services
$(_dep_all): olm
_dep_keystone: _dep_mariadb _dep_rabbitmq
_dep_glance _dep_neutron-api _dep_nova-api _dep_nova-cell _dep_placement: _dep_keystone
_dep_neutron-api: _dep_ovn
_dep_nova-api _dep_nova-cell: _dep_placement

# NOTE: requires 'make olm'
podified-ctlplane: ctlplane
ctlplane: $(_dep_all)

olm: hosts local-defaults.yaml
	ANSIBLE_FORCE_COLOR=true ansible-playbook \
	-v -i hosts -e @local-defaults.yaml \
	install_namespace.yaml \
	olm.yaml

olm_cleanup: hosts local-defaults.yaml
	ANSIBLE_FORCE_COLOR=true ansible-playbook \
	-v -i hosts -e @local-defaults.yaml \
	olm_cleanup.yaml

# XXX: WARNING!!! WARNING!!! DANGER WILL ROBINSON!!!
# YOU PROBABLY SHOULD NOT EXECUTE ANY OF THE FOLLOWING!
#
# Unlike the ansible playbooks, the following all assume you're executing this
# directly on the host.

clean: ocp_cleanup host_cleanup nfs_pvc_cleanup

host_cleanup:
	-echo | sudo tee /etc/exports

nfs_pvc_cleanup:
        -NFS_DATA_DIR=$$(grep nfs_data_dir ./vars/default.yaml |awk -F":" '{print $$2}') ;\
        sudo su - root -c "find $$NFS_DATA_DIR -type d -name 'pv-*' -delete"

ocp_cleanup:
	-sudo su - ocp -c "cd dev-scripts && make clean"
