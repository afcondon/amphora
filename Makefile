# Amphora. `spago build` builds the server and the API description; the
# targets here hold the two together.
#
#   make test            the scenario is well made and covers the description
#   make vectors         write the vector file, the OpenAPI file and the table
#   make check-vectors   fail if any of those is out of date
#   make conformance     replay the scenario against the real server, on a
#                        database of its own
#   make check           all of the above but `vectors`

GENERATE = node -e "import('./output/Test.Generate/index.js').then(m => m.$(1)())"

.PHONY: build test vectors check-vectors conformance check

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

check: check-vectors conformance
