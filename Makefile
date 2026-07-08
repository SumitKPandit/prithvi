lint:
    ansible-lint

yaml:
    yamllint .

syntax:
    cd ansible && ansible-playbook --syntax-check playbooks/day0.yml

diagnose:
    cd ansible && ansible-playbook playbooks/diagnose.yml

bootstrap:
    cd ansible && ansible-playbook playbooks/day0.yml -K