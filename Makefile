# Include standard NID (NSO in Docker) package Makefile that defines all
# standard make targets
-include nidpackage.mk

# The following are specific to this repositories packages
testenv-start-extra:
	@echo "Starting repository specific testenv"

testenv-test:
	@echo "TODO: Fill in your tests here"
# Some examples for how to run commands in the ncs_cli:
#	$(MAKE) testenv-runcmd CMD="show packages"
#	$(MAKE) testenv-runcmd CMD="request packages reload"
# Multiple commands in a single session also works - great for configuring stuff:
#	$(MAKE) testenv-runcmd CMD="configure\n set foo bar\n commit"
# We can test for certain output by combining show commands in the CLI with for
# example grep:
#	$(MAKE) testenv-runcmd CMD="show configuration foo" | grep bar
