BOOTSTRAP=1
SECRETS=~/values-secret.yaml
NAME=$(shell basename `pwd`)
TARGET_REPO=$(shell git remote show origin | grep Push | sed -e 's/.*URL://' -e 's%:%/%' -e 's%git@%https://%')
TARGET_BRANCH=$(shell git branch --show-current)

# This is to eliminate the need to install and worry about a separate shell script somewhere in the directory structure
# There's a lot of GNU Make magic happening here:
#  .ONESHELL passes the whole task into a single shell instance
#  $$ is a Makefile idiom to preserve the single $ otherwise make consumes them
#  tabs are necessary
#  The patch to oc apply uses JSON because it's not as sensitive to indentation and doesn't need heredoc
.ONESHELL:
SHELL = bash
argosecret:
	target_ns=$(TARGET_NAMESPACE)
	ns=0
	gitops=0

	# Check for Namespaces and Secrets to be ready (it takes the cluster a while to deploy them)
	while [ 1 ]; do
		if [ oc get namespace $$target_ns >/dev/null 2>/dev/null ]; then
			ns=0
		else
			ns=1
		fi

		if [ oc -n openshift-gitops extract secrets/openshift-gitops-cluster --to=- 1>/dev/null 2>/dev/null ]; then
			gitops=0
		else
			gitops=1
		fi

		if [ "$$gitops" == 1 -a "$$ns" == 1 ]; then
			break
		fi
	done

	user=$$(echo admin | base64)
	password=$$(oc -n openshift-gitops extract secrets/openshift-gitops-cluster --to=- 2>/dev/null | base64)

	echo "{ \"apiVersion\": \"v1\", \"kind\": \"Secret\", \"metadata\": { \"name\": \"argocd-env\", \"namespace\": \"$$target_ns\" }, \"data\": { \"ARGOCD_PASSWORD\": \"$$password\", \"ARGOCD_USERNAME\": \"$$user\" }, \"type\": \"Opaque\" }" | oc apply -f-

show:
	helm template install/ --name-template $(NAME) -f $(SECRETS) --set main.git.repoURL="$(TARGET_REPO)" --set main.git.revision=$(TARGET_BRANCH) --set main.options.bootstrap=$(BOOTSTRAP)

init:
	git submodule update --init --recursive

deploy:
	helm install $(NAME) install/ -f $(SECRETS) --set main.git.repoURL="$(TARGET_REPO)" --set main.git.revision=$(TARGET_BRANCH) --set main.options.bootstrap=$(BOOTSTRAP)
ifeq ($(BOOTSTRAP),1)
	bash util/argocd-secret.sh
endif

upgrade:
	helm upgrade $(NAME) install/ -f $(SECRETS) --set main.git.repoURL="$(TARGET_REPO)" --set main.git.revision=$(TARGET_BRANCH) --set main.options.bootstrap=$(BOOTSTRAP)
ifeq ($(BOOTSTRAP),1)
	bash util/argocd-secret.sh
endif

uninstall:
	helm uninstall $(NAME) 

.phony: install
