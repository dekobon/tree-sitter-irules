# Help
## ==============================
TREE_SITTER := ./node_modules/.bin/tree-sitter

help: ## Show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {sub("\\\\n",sprintf("\n%22c"," "), $$2);printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: build
build: parser/irules.so ## Build the tree-sitter-irules parser

parser/irules.so: src/parser.c src/scanner.c | deps ## Compile parser C files into shared object
	$(RM) $@
	mkdir -p parser
	$(TREE_SITTER) build -o $@

src/parser.c: grammar.js | deps ## Generate parser source from grammar.js
	$(TREE_SITTER) generate

# tree-sitter-cli's highlight-test runner can spin in an unbounded
# allocation on a malformed assertion comment (issue #32). Capping the
# test process's address space turns that runaway into a fast SIGABRT
# pointing at the issue, instead of an OOM-kill that looks like a hang.
# The legit suite needs well under this; override with
# `make test TEST_MEM_KB=...`. `ulimit -v` is a no-op where unsupported
# (e.g. macOS) — the CI job timeout is the backstop there.
TEST_MEM_KB ?= 2000000

.PHONY: test
test: parser/irules.so ## Run tree-sitter tests (address-space capped; see #32)
	@ulimit -v $(TEST_MEM_KB) 2>/dev/null || true; \
	$(TREE_SITTER) test; status=$$?; \
	if [ $$status -ge 128 ]; then \
		printf '\n%s\n' "tree-sitter test was killed by a signal (exit $$status)."; \
		printf '%s\n' "If this aborted/OOM'd under the ~$(TEST_MEM_KB) KB address-space cap, you"; \
		printf '%s\n' "likely hit issue #32: an unbounded allocation in tree-sitter-cli's"; \
		printf '%s\n' "highlight-test assertion loop, triggered by a stray '^' or '<-'"; \
		printf '%s\n' "annotation in a test/highlight/*.irules comment."; \
		printf '%s\n' "See https://github.com/dekobon/tree-sitter-irules/issues/32"; \
	fi; \
	exit $$status

.PHONY: clean
clean: ## Clean local environment
	rm -rf build node_modules parser

node_modules: package.json package-lock.json
	npm install
	touch node_modules

.PHONY: deps
deps: node_modules ## Install npm dependencies if needed

.PHONY: version
version: deps ## Tag new tree-sitter-irules semver
	read -p "version: " version && \
	$(TREE_SITTER) version $$version

## Linting
.PHONY: lint
lint: deps ## Run eslint
	npm run lint
