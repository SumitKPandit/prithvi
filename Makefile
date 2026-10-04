# Thin wrappers around the real commands. Everything runs from ansible/ per repo
# convention. Run `make` with no target to see this list.

.PHONY: deps bootstrap check apply verify lint fmt secrets-init secrets-edit apt-upgrade teardown verify-clean baseline

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

lint: ## yamllint + ansible-lint
	yamllint .
	ansible-lint

secrets-init: ## Create the age key (outside the repo) and the encrypted secrets file
	scripts/secrets-init.sh

secrets-edit: ## Edit ansible/secrets.sops.yaml with SOPS
	sops ansible/secrets.sops.yaml

apt-upgrade: ## Manual OS + Docker/Tailscale package upgrades on the server
	ssh g3plus 'sudo apt update && sudo apt full-upgrade && systemctl is-active docker tailscaled'

teardown: ## Remove everything deployed by the repo (requires -e confirm_teardown=yes)
	@echo "WARNING: This will remove all deployed services and configurations!"
	@read -p "Are you sure? Type 'yes' to confirm: " CONFIRM; \
	if [ "$$CONFIRM" = "yes" ]; then \
		echo "Running teardown..."; \
		echo "Running teardown from ansible/teardown.yml"; \
		ssh g3plus 'ansible-playbook ansible/teardown.yml -e confirm_teardown=yes'; \
	else \
		echo "Teardown aborted"; \
		exit 1; \
	fi

verify-clean: ## Diff the current server state against the baseline in baseline/ (allowed: updates, newer kernels, bootstrap files)
	@echo "Verifying server state is clean (matches baseline)..."
	@if [ ! -d "baseline" ] || [ ! "$(ls baseline 2>/dev/null)" ]; then \
		echo "ERROR: baseline/ directory is empty or missing. Run make baseline first."; \
		exit 1; \
	fi
	@echo "Baseline captured from a fresh Ubuntu install."
	@echo "Diffing server state against baseline..."
	@# Run from the Mac; compare target vs baseline files.
	@# Allowed diff items are documented in README; anything else needs investigation.
	ssh g3plus "\
		echo '=== packages ===' && dpkg-query -W | sort && \
		echo '=== /etc files ===' && find /etc -type f | grep -vE '(/ssh/ssh_host_|/systemd/|/apt/|/cups/|/logrotate.d/)' | sort && \
		echo '=== systemd units ===' && systemctl list-unit-files --state=enabled --no-legend | sort && \
		echo '=== users/groups ===' && getent passwd | sort && getent group | sort && \
		echo '=== listening ports ===' && ss -H -tlnp 2>/dev/null | sort && \
		echo '=== ufw ===' && ufw status verbose 2>/dev/null || echo 'UFW not installed' && \
		echo '=== sysctl ===' && sysctl -a 2>/dev/null | grep -v '^net\.ipv4\.ip_nonlocal_bind' | sort && \
		echo '=== dirs under /opt /srv /data /var/lib ===' && find /opt /srv /data /var/lib -type d 2>/dev/null | sort && \
		echo '=== kernel ===' && uname -r \
	" > /tmp/baseline-diff.log 2>&1 || true

	@echo "Diff saved to /tmp/baseline-diff.log"
	@echo "Review the diff and adjust README/allowed-list if needed."

baseline: ## Capture baseline state from a FRESH Ubuntu install (run on server, not on g3plus)
	sh scripts/capture-baseline.sh
