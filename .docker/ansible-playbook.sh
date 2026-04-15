docker container run --rm -v "$HOME/.ssh:/root/.ssh" -v "$(pwd):/apps" -w "/apps" alpine/ansible ansible-playbook "$@" -i inventory/hosts.yml --connection=local -vv
