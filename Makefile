# Thin wrappers around the real commands. Everything runs from ansible/ per repo
# convention. Run `make` with no target to see this list.

.PHONY: deps bootstrap check apply verify lint fmt secrets-init secrets-edit secrets-check apt-upgrade teardown verify-clean baseline nas-format hosts-snippet caddy-root-cert

deps: ## Install Ansible collections and pre-commit hook
	# --force also installs into ~/.ansible/collections when the collections
	# already exist inside some other Python env, which ansible-lint cannot see.
	ansible-galaxy collection install -r ansible/requirements.yml --force
	pre-commit install 2>/dev/null || true

bootstrap: ## One-time setup of a fresh Ubuntu install (SSH key + passwordless sudo)
	scripts/bootstrap.sh

check: ## Dry run: show what would change, change nothing
	cd ansible && ansible-playbook site.yml --check --diff

apply: ## Apply everything for real
	cd ansible && ansible-playbook site.yml --diff

verify: ## Run the verification playbook (fails loudly if anything is wrong)
	cd ansible && ansible-playbook verify.yml

lint: ## yamllint + ansible-lint + VPN compose render check
	yamllint .
	ansible-lint
	cd ansible && ansible-playbook vpn-check.yml -e vpn_enabled=true && docker compose --project-directory /tmp/vpncheck config -q && rm -rf /tmp/vpncheck

secrets-init: ## Create the age key (outside the repo) and the encrypted secrets file
	scripts/secrets-init.sh

secrets-edit: ## Edit ansible/secrets.sops.yaml with SOPS
	sops ansible/secrets.sops.yaml

secrets-check: ## List EMPTY secrets (names only) and what each unlocks
	sh scripts/secrets-check.sh

apt-upgrade: ## Manual OS + Docker/Tailscale package upgrades on the server
	ssh g3plus 'sudo apt update && sudo apt full-upgrade && systemctl is-active docker tailscaled'

teardown: ## Remove everything deployed by the repo (confirms; asks about data deletion)
	@echo "WARNING: This will remove all deployed services and configurations!"
	@read -p "Type 'yes' to confirm: " CONFIRM; \
	if [ "$$CONFIRM" = "yes" ]; then \
		read -p "ALSO delete DATA and BACKUPS (/data, /opt/appdata, /opt/backups, docker volumes)? Type 'yes' to confirm: " DATACONFIRM; \
		if [ "$$DATACONFIRM" = "yes" ]; then \
			cd ansible && ansible-playbook teardown.yml -e confirm_teardown=yes -e teardown_data=yes; \
		else \
			cd ansible && ansible-playbook teardown.yml -e confirm_teardown=yes; \
		fi; \
	else \
		echo "Teardown aborted"; \
		exit 1; \
	fi

verify-clean: ## Diff the current server state against the baseline in baseline/ (allowed: updates, newer kernels, bootstrap files)
	@echo "Verifying server state is clean (matches baseline)..."
	@if [ ! -d "baseline" ] || [ ! "$$(ls baseline 2>/dev/null)" ]; then \
		echo "ERROR: baseline/ directory is empty or missing. Capture it from a fresh Ubuntu 26.04 install first (see README 'verify-clean')."; \
		exit 1; \
	fi
	@if [ ! -f "baseline/manifest.yaml" ]; then \
		echo "ERROR: baseline/manifest.yaml is missing (it documents where the baseline came from)."; \
		exit 1; \
	fi
	sh scripts/verify-clean.sh

baseline: ## Capture baseline state from a FRESH Ubuntu install (run on server, not on g3plus)
	sh scripts/capture-baseline.sh

nas-format: ## DESTRUCTIVE: format the NAS disks (prompts; needs nas_format_confirm=yes)
	@echo "WARNING: this wipes the disks listed in nas_data_disks/nas_parity_disks!"
	@read -p "Type 'yes' to wipe and format every listed disk: " CONFIRM; \
	if [ "$$CONFIRM" = "yes" ]; then \
		cd ansible && ansible-playbook nas-format.yml -e nas_format_confirm=yes; \
	else \
		echo "Format aborted"; \
		exit 1; \
	fi

hosts-snippet: ## Print /etc/hosts lines for the private hostnames (no DNS needed)
	python3 scripts/hosts-snippet.py

caddy-root-cert: ## Export Caddy's internal root CA to trust on Mac/iOS (see script for steps)
	sh scripts/caddy-root-cert.sh
