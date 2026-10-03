ANSIBLE_CONFIG := ansible/ansible.cfg
PLAYBOOK := ansible/site.yml

.PHONY: server check collections vault-edit vault-view

collections:
	ANSIBLE_CONFIG=$(ANSIBLE_CONFIG) ansible-galaxy collection install -r ansible/requirements.yml

server: collections
	ANSIBLE_CONFIG=$(ANSIBLE_CONFIG) ansible-playbook $(PLAYBOOK) --ask-become-pass

check: collections
	ANSIBLE_CONFIG=$(ANSIBLE_CONFIG) ansible-playbook $(PLAYBOOK) --check --diff --ask-become-pass

vault-edit:
	ANSIBLE_CONFIG=$(ANSIBLE_CONFIG) ansible-vault edit ansible/group_vars/all/vault.yml

vault-view:
	ANSIBLE_CONFIG=$(ANSIBLE_CONFIG) ansible-vault view ansible/group_vars/all/vault.yml
