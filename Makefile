# usage:
# `make` or `make test` runs all the tests
# `make google` runs just the test/google.coffee test

TESTS=google google_batch

test: $(TESTS)

$(TESTS):
	node_modules/mocha/bin/mocha --reporter spec --bail --timeout 60000 --compilers ./node_modules/.bin/coffee:coffee-script/register test/$@.coffee

