SHELL=/bin/bash
include ../testenv-common.mk

# Enable IPv6 per default, set to false to disable (in Makefile, not here)
IPV6?=true
# start: start the test environment in a configuration that allows
# Python Remote Debugging. Exposes port 5678 on a random port on localhost.
# Per default, the IPv6 prefix is a randomly generated IPv6 network prefix in
# the ULA address space. Override by setting IPV6_NET variable to e.g.:
# IPV6_NET=2001:db8:1234:456:  # which becomes 2001:db8:1234:456::/64
# If the IPv6 prefix is not in the public unicast space (2000::/3), the IPv6
# default route will be removed. This makes it possible to have local IPv6
# connectivity within the network, yet not slow down attempts to reach Internet
# resources (where IPv6 would normally be tried first, and fail due to
# non-public addresses).
start:
	docker network inspect $(CNT_PREFIX) >/dev/null 2>&1 || docker network create $(CNT_PREFIX) $(shell [ "$(IPV6)" = "true" ] && export LC_ALL=C && echo --ipv6 --subnet $${IPV6_NET:-fd00:$$(< /dev/urandom tr -dc a-f0-9 | head -c4):$$(< /dev/urandom tr -dc a-f0-9 | head -c4):$$(< /dev/urandom tr -dc a-f0-9 | head -c4):}:/64)
	docker run -td --name $(CNT_PREFIX)-nso --network-alias nso $(DOCKER_NSO_ARGS) $(IMAGE_PATH)$(PROJECT_NAME)/testnso:$(DOCKER_TAG)
# You may start other containers that are part of the testenv here. For example
# a netsim container or a virtual router.
	-[ "$(IPV6)" = "true" ] && echo $$(docker network inspect --format '{{range .IPAM.Config}}{{- if (gt (split .Subnet ":"|len) 1) -}}{{.Subnet}}{{- end}}{{end}}' $(CNT_PREFIX)) | egrep "^[23]...:" || (echo "Removing IPv6 default route" && docker ps -aq --filter label=com.cisco.nso.testenv.name=$(CNT_PREFIX) | $(XARGS) -I CNT -n1 docker run --rm --net=container:CNT --cap-add=NET_ADMIN $(NSO_IMAGE_PATH)cisco-nso-base:$(NSO_VERSION) ip -6 route del default >/dev/null 2>&1 || true)

	$(MAKE) wait-started-nso

# Place your tests in test. Feel free to define a target per test case
# and call them from test in case you have more than a handful of cases.
# Sometimes when there is a "setup" or "preparation" part of a test, it can be
# useful to separate into its own target as to make it possible to run that
# prepare phase and then manually inspect the state of the system. You can
# achieve this by further refining the make targets you have.
test:
	@echo "\n== Running tests"
	@echo "-- Verify packages are operationally up"
	$(MAKE) runcmdJ CMD="show packages" | docker run -i --rm $(NSO_IMAGE_PATH)cisco-nso-dev:$(NSO_VERSION) bash -c '! grep -P "oper-status (?!up)" >/dev/null' || (echo "ERROR: packages not operationally up:" && $(MAKE) runcmdJ CMD="show packages" && false)
	$(MAKE) test-working
	$(MAKE) test-disable
	$(MAKE) test-emergency-stop
	$(MAKE) test-ha

# Which TBGW instance to test
# tbgw is the default one
# tbgw-ha-always
# tbgw-ha-secondary
TEST_TBGW?=tbgw

ifeq ($(shell test "$(NSO_VERSION_MAJOR)" -ge 6; echo $$?),0)
HA_PRIMARY=primary
HA_SECONDARY=secondary
HA_STATE=tfnm2:ha
else
HA_STATE=ha
HA_PRIMARY=master
HA_SECONDARY=slave
endif

test-ha:
ifeq ($(shell test "$(NSO_VERSION_MAJOR)" -lt 5  -o  \
                   "$(NSO_VERSION_MAJOR)" = 5  -a  \
                   "$(NSO_VERSION_MINOR)" -lt 4  \
                   &&  printf "true"), true)
	@echo "Skipping HA tests on NSO version < 5.4"
else
	$(MAKE) test-ha-none
	$(MAKE) test-ha-primary
	$(MAKE) test-ha-secondary
endif

test-working:
	@echo -e "\n== Verify that the worker is alive by observing the increasing counter"
	$(MAKE) runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) test-counter-working

test-disable:
	@echo -e "\n== Verify that it is possible to disable and re-enable the worker"
	$(MAKE) runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) test-counter-working
	@echo "-- Disable worker"
	$(MAKE) runcmdJ CMD="configure\n set tbgw disabled\n commit"
	$(MAKE) test-counter-stopped
	@echo "-- Enable worker again"
	$(MAKE) runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) test-counter-working

test-restart:
	@echo -e "\n== Verify that restart works"
	$(MAKE) runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) test-counter-working
	@echo "-- Restart the worker"
	$(MAKE) runcmdJ CMD="request tbgw restart"
	$(MAKE) test-counter-working
	@echo "-- Ensure we have right number of Python processes (so we don't leak processes)"
	docker exec -t $(CNT_PREFIX)-nso bash -lc 'ps auxwww' | awk 'BEGIN {c=0} /python/ { c++ } END { print "Got", c, "Python processes (expect 3)"; if (c != 3) { exit 1 }}'

test-restart-disable:
	@echo -e "\n== Verify that restart won't start disabled worker"
	$(MAKE) runcmdJ CMD="configure\n set tbgw disabled\n commit"
	$(MAKE) test-counter-stopped
	@echo "-- Restart the worker"
	$(MAKE) runcmdJ CMD="request tbgw restart" | grep "The background worker is disabled in configuration"
	$(MAKE) test-counter-stopped
	$(MAKE) runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) test-counter-working

test-emergency-stop:
	@echo -e "\n== Verify that the emergency-stop action works"
	$(MAKE) runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) test-counter-working
	@echo "-- Signal the worker to stop immediately"
	$(MAKE) runcmdJ CMD="request tbgw emergency-stop"
	sleep 1
	$(MAKE) test-counter-stopped
	@echo "-- Enable worker again by redeploying"
	$(MAKE) runcmdJ CMD="request packages reload"
	$(MAKE) test-counter-working

test-emergency-stop-and-restart:
	@echo -e "\n== Verify that the emergency-stop action works"
	@echo "-- Ensure worker is enabled in configuration"
	$(MAKE) runcmdJ CMD="configure\n set tbgw enabled\n commit"
	$(MAKE) test-counter-working
	@echo "-- Signal the worker to stop immediately"
	$(MAKE) runcmdJ CMD="request tbgw emergency-stop"
	$(MAKE) test-counter-stopped
	@echo "-- Verify the worker was disabled"
	$(MAKE) runcmdJ CMD="show configuration tbgw enabled" | grep disabled
	@echo "-- Restart the worker"
	$(MAKE) runcmdJ CMD="request tbgw restart"
	$(MAKE) test-counter-working

test-ha-none: export NSO=$@
test-ha-none:
	@echo -e "\n== Ensure bgworker behavior when in HA-mode = none"
	-docker rm -f $(CNT_PREFIX)-nso$@
	docker network inspect $(CNT_PREFIX) >/dev/null 2>&1 || docker network create $(CNT_PREFIX)
	docker run -td --name $(CNT_PREFIX)-nso$@ $(DOCKER_NSO_ARGS) -e ADMIN_PASSWORD=NsoDocker1337 -e HA_ENABLE=true $${NSO_EXTRA_ARGS} $(IMAGE_PATH)$(PROJECT_NAME)/testnso:$(DOCKER_TAG)
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'ncs --wait-started 600'
	$(MAKE) runcmdJ NSO=$@ CMD="show ncs-state $(HA_STATE)"
	@echo "-- Per default we expect bgworker to not run"
	$(MAKE) test-counter-stopped
	@echo "-- The tbgw-ha-always instance should be running though"
	$(MAKE) test-counter-working TEST_TBGW=tbgw-ha-always
	@echo "-- The tbgw-ha-secondary instance should NOT run"
	$(MAKE) test-counter-stopped TEST_TBGW=tbgw-ha-secondary
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'cat /log/ncs-python-vm-test-bgworker.log' | grep "Background worker will not run when HA-when=primary and HA-mode=none"
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'cat /log/ncs-python-vm-test-bgworker.log' | grep "Background worker will not run when HA-when=secondary and HA-mode=none"
	-docker rm -f $(CNT_PREFIX)-nso$@

test-ha-primary: export NSO=$@
test-ha-primary:
	@echo -e "\n== Ensure bgworker behavior when in HA-mode = primary"
	docker network inspect $(CNT_PREFIX) >/dev/null 2>&1 || docker network create $(CNT_PREFIX)
	-docker rm -f $(CNT_PREFIX)-nso$@
	docker run -td --name $(CNT_PREFIX)-nso$@ $(DOCKER_NSO_ARGS) -e ADMIN_PASSWORD=NsoDocker1337 -e HA_ENABLE=true $${NSO_EXTRA_ARGS} $(IMAGE_PATH)$(PROJECT_NAME)/testnso:$(DOCKER_TAG)
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'ncs --wait-started 600'
	$(MAKE) runcmdJ NSO=$@ CMD="show ncs-state $(HA_STATE)"
	$(MAKE) runcmdJ NSO=$@ CMD="configure\nedit high-availability\nset token ohsosecret\nset ha-node localhost address 127.0.0.1 nominal-role $(HA_PRIMARY)\ncommit"
	$(MAKE) runcmdJ NSO=$@ CMD="request high-availability enable"
	$(MAKE) runcmdJ NSO=$@ CMD="request high-availability be-$(HA_PRIMARY)"
	$(MAKE) runcmdJ NSO=$@ CMD="show ncs-state $(HA_STATE)"
	$(MAKE) runcmdJ NSO=$@ CMD="request packages reload"
	@echo "-- Give NSO some time after package reload"
	sleep 10
	@echo "-- The tbgw-ha-always instance should be running too"
	$(MAKE) test-counter-working TEST_TBGW=tbgw-ha-always
	@echo "-- The tbgw-ha-secondary instance should NOT run"
	$(MAKE) test-counter-stopped TEST_TBGW=tbgw-ha-secondary
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'cat /log/ncs-python-vm-test-bgworker.log' | grep "Background worker will not run when HA-when=secondary and HA-mode=primary"
	-docker rm -f $(CNT_PREFIX)-nso$@


HA_PRIMARY_ADDRESS=$$(docker inspect --format '{{range $$p, $$conf := .NetworkSettings.Networks}}{{(index $$conf).IPAddress}}{{end}}' $(CNT_PREFIX)-nso$@primary | head -n1 | cat)
test-ha-secondary: export NSO=$@
test-ha-secondary:
	@echo -e "\n== Ensure bgworker behavior when in HA-mode = secondary"
	docker network inspect $(CNT_PREFIX) >/dev/null 2>&1 || docker network create $(CNT_PREFIX)
	-docker rm -f $(CNT_PREFIX)-nso$@
	-docker rm -f $(CNT_PREFIX)-nso$@primary
	docker run -td --name $(CNT_PREFIX)-nso$@ $(DOCKER_NSO_ARGS) -e ADMIN_PASSWORD=NsoDocker1337 -e HA_ENABLE=true $${NSO_EXTRA_ARGS} $(IMAGE_PATH)$(PROJECT_NAME)/testnso:$(DOCKER_TAG)
	docker run -td --name $(CNT_PREFIX)-nso$@primary $(DOCKER_NSO_ARGS) -e ADMIN_PASSWORD=NsoDocker1337 -e HA_ENABLE=true $${NSO_EXTRA_ARGS} $(IMAGE_PATH)$(PROJECT_NAME)/testnso:$(DOCKER_TAG)
	docker exec -t $(CNT_PREFIX)-nso$@primary bash -lc 'ncs --wait-started 600'
	$(MAKE) runcmdJ NSO=$@primary CMD="configure\nedit high-availability\nset token ohsosecret\nset ha-node primary address $(HA_PRIMARY_ADDRESS) nominal-role $(HA_PRIMARY)\ncommit"
	$(MAKE) runcmdJ NSO=$@primary CMD="request high-availability enable"
	$(MAKE) runcmdJ NSO=$@primary CMD="request high-availability be-$(HA_PRIMARY)"
	$(MAKE) runcmdJ NSO=$@primary CMD="show ncs-state $(HA_STATE)"
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'ncs --wait-started 600'
	$(MAKE) runcmdJ NSO=$@ CMD="show ncs-state $(HA_STATE)"
	$(MAKE) runcmdJ NSO=$@ CMD="configure\nedit high-availability\nset token ohsosecret\nset ha-node secondary address 127.0.0.1 nominal-role $(HA_SECONDARY)\nset ha-node primary address $(HA_PRIMARY_ADDRESS) nominal-role $(HA_PRIMARY)\ncommit"
	$(MAKE) runcmdJ NSO=$@ CMD="request high-availability enable"
	$(MAKE) runcmdJ NSO=$@ CMD="request high-availability be-$(HA_SECONDARY)-to node primary"
	$(MAKE) runcmdJ NSO=$@ CMD="show ncs-state $(HA_STATE)"
	@echo "-- Give NSO some time to become secondary and run tbgw + error out"
	sleep 10
	$(MAKE) runcmdJ NSO=$@ CMD="show ncs-state $(HA_STATE)" | grep "ncs-state $(HA_STATE) mode $(HA_SECONDARY)"
	@echo "-- Expect to see errors in log since we are in read-only mode (secondary) and thus, trying to update counter results in error"
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'cat /log/ncs-python-vm-test-bgworker.log' | grep -A30 "TBGW starting on YANG: tbgw-ha-always" | grep "Unhandled error in test_bgwork"
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'cat /log/ncs-python-vm-test-bgworker.log' | grep -A30 "TBGW starting on YANG: tbgw-ha-secondary" | grep "Unhandled error in test_bgwork"
	docker exec -t $(CNT_PREFIX)-nso$@ bash -lc 'cat /log/ncs-python-vm-test-bgworker.log' | grep "Background worker will not run when HA-when=primary and HA-mode=secondary"
	-docker rm -f $(CNT_PREFIX)-nso$@
	-docker rm -f $(CNT_PREFIX)-nso$@primary

test-counter-working:
	@echo "-- Verify counter is being incremented"
	diff <($(MAKE) runcmdJ CMD="show $(TEST_TBGW) counter" | awk '/^$(TEST_TBGW) counter/ { print $$3 }') <(sleep 3; $(MAKE) runcmdJ CMD="show $(TEST_TBGW) counter" | awk '/^$(TEST_TBGW) counter/ { print $$3 }'); test $$? -eq 1

test-counter-stopped:
	@echo "-- Verify counter is not being incremented"
	diff <($(MAKE) runcmdJ CMD="show $(TEST_TBGW) counter" | awk '/^$(TEST_TBGW) counter/ { print $$3 }') <(sleep 5; $(MAKE) runcmdJ CMD="show $(TEST_TBGW) counter" | awk '/^$(TEST_TBGW) counter/ { print $$3 }')


test-upgrade-load-v1:
	rm -rf test-packages/up
	cp -a upgrade-packages/upv1 test-packages/up
	$(MAKE) clean-build

test-upgrade-load-v2:
	rm -rf test-packages/up
	cp -a upgrade-packages/upv2 test-packages/up
	$(MAKE) clean-build

# Test that the bgworker does not run while NSO is doing schema upgrades. The
# "up" package version 2 has a 10 second sleep, so we ensure that a) the upgrade
# code has been run by checking that the whole test took more than 10 second and
# b) that the background process indeed did not run by looking the python log
# for the tell tale exceptions that happen when the bgworker tries to connect to
# NSO which will reject the connection due to being in upgrade mode.
# Quite hackish, but it works...
test-upgrade:
	@echo "-- Removing old package"
	docker exec -t $(CNT_PREFIX)-nso bash -lc 'rm -rf /var/opt/ncs/packages/up'
	$(MAKE) runcmdJ CMD="request packages reload force"
	@echo "-- Loading version 1 of package"
	$(MAKE) test-upgrade-load-v1
	@echo "-- Getting rid of old log messages"
	docker exec -t $(CNT_PREFIX)-nso bash -lc 'echo "" > /log/ncs-python-vm-test-bgworker.log'
	@echo "-- Adding some data"
	$(MAKE) runcmdJ CMD="configure\n set up a FOO val1 BAR\n commit"
	TIME1=$$(date +"%s"); \
	VAL1=$$($(MAKE) runcmdJ CMD="show $(TEST_TBGW) counter" | awk '/^$(TEST_TBGW) counter/ { print $$3 }' | tr -d '\r'); \
	$(MAKE) test-upgrade-load-v2; \
	TIME2=$$(date +"%s"); \
	VAL2=$$($(MAKE) runcmdJ CMD="show $(TEST_TBGW) counter" | awk '/^$(TEST_TBGW) counter/ { print $$3 }' | tr -d '\r'); \
	DIFF=$$(expr $$VAL2 - $$VAL1); \
	TDIFF=$$(expr $$TIME2 - $$TIME1); \
	if [ $$TDIFF -lt 10 ]; then echo "Not enough time ($$TDIFF) has elapsed, did upgrade code run?"; false; fi && \
	if [ $$DIFF -gt 10 ]; then echo "Diff ($$DIFF) is larger than 10, how did that happen?"; false; fi
	docker exec -t $(CNT_PREFIX)-nso bash -lc '! grep "node is in upgrade mode" /log/ncs-python-vm-test-bgworker.log'
