# Amphora. `spago build` builds the server and the API description; the
# targets here hold the two together.
#
#   make test            the scenario is well made and covers the description
#   make vectors         write the vector file, the OpenAPI file and the table
#   make check-vectors   fail if any of those is out of date
#   make conformance     replay the scenario against the real server, on a
#                        database of its own; then the PureScript client
#                        against it
#   make check           all of the above but `vectors`

GENERATE = node -e "import('./output/Test.Generate/index.js').then(m => m.$(1)())"

.PHONY: build test vectors check-vectors conformance check lint-openapi

build:
	spago build

test:
	spago test -p amphora-api

vectors: test
	$(call GENERATE,vectors) > conformance/vectors/amphora-api.json.tmp
	mv conformance/vectors/amphora-api.json.tmp conformance/vectors/amphora-api.json
	$(call GENERATE,openapi) > conformance/openapi.json.tmp
	mv conformance/openapi.json.tmp conformance/openapi.json
	node conformance/table.mjs write

check-vectors: test
	$(call GENERATE,vectors) | diff -u conformance/vectors/amphora-api.json -
	$(call GENERATE,openapi) | diff -u conformance/openapi.json -
	node conformance/table.mjs check

conformance: build
	node conformance/replay.mjs
	node conformance/client.mjs

check: check-vectors conformance

# The exported OpenAPI file through a standard tool. Fetches Redocly's CLI
# from npm, so it needs the network and is not part of `check`. Expect it to
# say the description is valid, with warnings that are true and left alone:
# the six list operations declare no 4XX (they have none), the server is
# localhost, and the licence has no URL.
lint-openapi:
	npx --yes @redocly/cli@latest lint conformance/openapi.json
