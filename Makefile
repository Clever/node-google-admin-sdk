# usage:
# `make` or `make test` runs all the tests
# `make google` runs just the test/google.coffee test

TESTS=google google_batch

test: $(TESTS)

$(TESTS):
	node_modules/mocha/bin/mocha -r coffee-errors --reporter spec --bail --timeout 60000 test/$@.coffee
 
#.PHONY: test unit unit-w all $(TESTS)

