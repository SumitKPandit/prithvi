# Thin wrappers around the real commands. Everything runs from ansible/ per repo
# convention. Run `make` with no target to see this list.

.PHONY: deps bootstrap check apply verify lint fmt secrets-init secrets-edit apt-upgrade

deps: ## Install Ansible collections and pre-commit hook
	ansible-galaxy collection install -r ansible/requirements.yml
	pre-commit install 2>/dev/null || true

bootstrap: ## One-time setup of a fresh Ubuntu install (SSH key + passwordless sudo)
	scripts/bootstrap.sh

check: ## Dry run: show what would change, change nothing
	cd ansible && ansible-playbook site.yml --check --diff

apply: ## Apply everything for real
	cd ansible && ansible-playbook site.yml --diff

verify: ## Run the verification playbook (fails loudly if anything is wrong)
	cd ansible && ansible-playbook verify.yml

lint: ## yamllint + ansible-lint
	yamllint .
	ansible-lint

secrets-init: ## Create the age key (outside the repo) and the encrypted secrets file
	scripts/secrets-init.sh

secrets-edit: ## Edit ansible/secrets.sops.yaml with SOPS
	sops ansible/secrets.sops.yaml

apt-upgrade: ## Manual OS + Docker/Tailscale package upgrades on the server
	ssh g3plus 'sudo apt update && sudo apt full-upgrade && systemctl is-active docker tailscaled'
