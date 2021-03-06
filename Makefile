# include .env variable in the current environment
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

export DOCKER_COMPOSE_FILES := $(wildcard docker-compose.*.yml) $(wildcard services-enabled/*.yml)
export DOCKER_COMPOSE_FLAGS := -f docker-compose.yml $(foreach file, $(DOCKER_COMPOSE_FILES), -f $(file))

# look for the second target word passed to make
export SERVICE_PASSED_DNCASED := $(strip $(word 2,$(MAKECMDGOALS)))
export SERVICE_PASSED_UPCASED := $(strip $(subst -,_,$(shell echo $(SERVICE_PASSED_DNCASED) | tr a-z A-Z )))
export ETC_SERVICE := $(subst nfs-,,$(SERVICE_PASSED_DNCASED))


# get the boxes ip address and the current users id and group id
export HOSTIP := $(shell ip route get 1.1.1.1 | grep -oP 'src \K\S+')
export PUID 	:= $(shell id -u)
export PGID 	:= $(shell id -g)
export HOST_NAME := $(or $(HOST_NAME), $(shell hostname))

# check if we should use docker-compose or docker compose
ifeq (, $(shell which docker-compose))
	DOCKER_COMPOSE := docker compose
else
	DOCKER_COMPOSE := docker-compose
endif

# check what editor is available
ifdef VSCODE_IPC_HOOK_CLI
	EDITOR := code
else
	EDITOR := nano
endif

# used to look for the file in the services-enabled folder when [start|stop|pull]-service is used  
SERVICE_FILE = --project-directory ./ -f ./services-enabled/$(SERVICE_PASSED_DNCASED).yml

# use the rest as arguments as empty targets aka: MAGIC
EMPTY_TARGETS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
$(eval $(EMPTY_TARGETS):;@:)

# this is the default target run if no other targets are passed to make
# i.e. if you just type: make
start: build
	$(DOCKER_COMPOSE) $(DOCKER_COMPOSE_FLAGS) up -d
	
remove-orphans: build
	$(DOCKER_COMPOSE) $(DOCKER_COMPOSE_FLAGS) up -d --remove-orphans	

up: build
	$(DOCKER_COMPOSE) $(DOCKER_COMPOSE_FLAGS) up --force-recreate --remove-orphans --abort-on-container-exit

down: 
	-$(DOCKER_COMPOSE) $(DOCKER_COMPOSE_FLAGS) down --remove-orphans
	-docker volume ls --quiet --filter "label=remove_volume_on=down" | xDOCKER_COMPOSE_FLAGS -r docker volume rm

start-service: COMPOSE_IGNORE_ORPHANS = true 
start-service: build enable-service
	$(DOCKER_COMPOSE) $(SERVICE_FILE) up -d --force-recreate $(SERVICE_PASSED_DNCASED)

start-compose: COMPOSE_IGNORE_ORPHANS = true 
start-compose: build 
	$(DOCKER_COMPOSE) $(SERVICE_FILE) up -d --force-recreate

down-service: 
	-$(DOCKER_COMPOSE) $(SERVICE_FILE) stop $(SERVICE_PASSED_DNCASED)

down-compose: 
	-$(DOCKER_COMPOSE) $(SERVICE_FILE) stop

pull-service: 
	$(DOCKER_COMPOSE) $(SERVICE_FILE) pull $(SERVICE_PASSED_DNCASED)

pull-compose: 
	$(DOCKER_COMPOSE) $(SERVICE_FILE) pull

stop-service: down-service

restart-service: down-service build start-service

update-service: down-service build pull-service start-service

start-staging: build
	ACME_CASERVER=https://acme-staging-v02.api.letsencrypt.org/directory $(DOCKER_COMPOSE) $(DOCKER_COMPOSE_FLAGS) up -d --force-recreate
	@echo "waiting 30 seconds for cert DNS propogation..."
	@sleep 30
	@echo "open https://$(HOST_NAME).$(HOST_DOMAIN)/traefik in a browser"
	@echo "and check that you have a staging cert from LetsEncrypt!"
	@echo ""
	@echo "if you don't get the write cert run the following command and look for error messages:"
	@echo "$(DOCKER_COMPOSE) logs | grep acme"
	@echo ""
	@echo "otherwise run the following command if you successfully got a staging certificate:"
	@echo "make down-staging"

down-staging:
	$(DOCKER_COMPOSE) $(DOCKER_COMPOSE_FLAGS) down
	$(MAKE) clean-acme

clean-acme:
	@echo "cleaning up staging certificates"
	sudo rm etc/traefik/letsencrypt/acme.json

pull:
	$(DOCKER_COMPOSE) $(DOCKER_COMPOSE_FLAGS) pull

logs:
	$(DOCKER_COMPOSE) $(DOCKER_COMPOSE_FLAGS) logs -f

restart: down start

update: down pull start

exec:
	$(DOCKER_COMPOSE) $(DOCKER_COMPOSE_FLAGS) exec $(SERVICE_PASSED_DNCASED) sh

build: .env etc/prometheus/conf etc/authelia/configuration.yml

etc/authelia/configuration.yml:
	envsubst '$${HOST_DOMAIN}' < ./etc/authelia/configuration.template > ./etc/authelia/configuration.yml

.env:
	cp .env.sample .env
	$(EDITOR) .env

etc/prometheus/conf:
	mkdir -p etc/prometheus/conf
	cp --no-clobber --recursive	etc/prometheus/conf-originals/* etc/prometheus/conf

list-games:
	@ls -1 ./services-available/games | sed -n 's/\.yml$ //p'

list-services:
	@ls -1 ./services-available/ | sed -e 's/\.yml$ //'

list-external:
	@ls -1 ./etc/traefik/available/ | sed -e 's/\.yml$ //'

etc/$(ETC_SERVICE):
	@mkdir -p ./etc/$(ETC_SERVICE)

enable-game: etc/$(ETC_SERVICE)
	@ln -s ../services-available/games/$(SERVICE_PASSED_DNCASED).yml ./services-enabled/$(SERVICE_PASSED_DNCASED).yml || true

enable-service: etc/$(ETC_SERVICE) services-enabled/$(SERVICE_PASSED_DNCASED).yml

services-enabled/$(SERVICE_PASSED_DNCASED).yml:
	@ln -s ../services-available/$(SERVICE_PASSED_DNCASED).yml ./services-enabled/$(SERVICE_PASSED_DNCASED).yml || true

enable-game-copy: etc/$(SERVICE_PASSED_DNCASED)
	@cp ./services-available/games/$(SERVICE_PASSED_DNCASED).yml ./services-enabled/$(SERVICE_PASSED_DNCASED).yml || true

enable-service-copy: etc/$(SERVICE_PASSED_DNCASED)
	@cp ./services-available/$(SERVICE_PASSED_DNCASED).yml ./services-enabled/$(SERVICE_PASSED_DNCASED).yml || true

enable-external:
	@cp ./etc/traefik/available/$(SERVICE_PASSED_DNCASED).yml ./etc/traefik/enabled/$(SERVICE_PASSED_DNCASED).yml || true

disable-game: disable-service

disable-service:
	rm ./services-enabled/$(SERVICE_PASSED_DNCASED).yml

disable-external:
	rm ./etc/traefik/enabled/$(SERVICE_PASSED_DNCASED).yml

create-service:
	envsubst '$${SERVICE_PASSED_DNCASED},$${SERVICE_PASSED_UPCASED}' < ./services-available/.service.template > ./services-available/$(SERVICE_PASSED_DNCASED).yml
	$(EDITOR) ./services-available/$(SERVICE_PASSED_DNCASED).yml

create-game:
	envsubst '$${SERVICE_PASSED_DNCASED},$${SERVICE_PASSED_UPCASED}' < ./services-available/.service.template > ./services-available/games/$(SERVICE_PASSED_DNCASED).yml
	$(EDITOR) ./services-available/games/$(SERVICE_PASSED_DNCASED).yml

install-node-exporter:
	curl -s https://gist.githubusercontent.com/ilude/2cf7a3b7712378c6b9bcf1e1585bf70f/raw/setup_node_exporter.sh?$(date +%s) | /bin/bash -s | tee build.log

export-backup:
	sudo tar -cvzf traefik-config-backup.tar.gz ./etc ./services-enabled .env docker-compose.*.yml || true

import-backup:
	sudo tar -xvf traefik-config-backup.tar.gz

cloudflare-login:
	$(DOCKER_COMPOSE) run --rm cloudflared login

create-tunnel:
	$(DOCKER_COMPOSE) run --rm cloudflared tunnel create $(CLOUDFLARE_TUNNEL_NAME)
	$(DOCKER_COMPOSE) run --rm cloudflared tunnel route dns $(CLOUDFLARE_TUNNEL_NAME) $(CLOUDFLARE_TUNNEL_HOSTNAME)

delete-tunnel:
	$(DOCKER_COMPOSE) run --rm cloudflared tunnel cleanup $(CLOUDFLARE_TUNNEL_NAME)
	$(DOCKER_COMPOSE) run --rm cloudflared tunnel delete $(CLOUDFLARE_TUNNEL_NAME)

show-tunnel:
	$(DOCKER_COMPOSE) run --rm cloudflared tunnel info $(CLOUDFLARE_TUNNEL_NAME)

# https://stackoverflow.com/questions/7117978/gnu-make-list-the-values-of-all-variables-or-macros-in-a-particular-run
echo:
	@$(MAKE) -pn | grep -A1 "^# makefile"| grep -v "^#\|^--" | grep -e "^[A-Z]+*" | sort

env:
	@env | sort
