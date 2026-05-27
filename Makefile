UYA ?= $(HOME)/uya/uya/bin/uya
SRC := src/hgx/main.uya
BIN := bin/hgx
C99 := build/hgx.c

.PHONY: check build c99 test clean

check:
	$(UYA) check $(SRC)

build: $(BIN)

$(BIN): $(SRC)
	mkdir -p bin
	$(UYA) build $(SRC) -o $(BIN)

c99:
	mkdir -p build
	$(UYA) build $(SRC) -o $(C99) --c99

test:
	$(UYA) test src/hypergit/test_object_model.uya
	$(UYA) test src/hypergit/test_object_codec.uya
	$(UYA) test src/hypergit/test_manifest_path.uya
	$(UYA) test src/hypergit/test_manifest_trie.uya
	$(UYA) test src/hypergit/test_manifest_shard.uya
	$(UYA) test src/hypergit/test_manifest_query.uya
	$(UYA) test src/hypergit/test_manifest_diff.uya
	$(UYA) test src/hypergit/test_stage_state.uya
	$(UYA) test src/hypergit/test_stage_file.uya
	$(UYA) test src/hypergit/test_loose_store.uya
	$(UYA) test src/hgx/test_repo_layout.uya
	$(UYA) test src/hgx/test_cli_args.uya
	./tests/test_cli_golden.sh
	./tests/test_repo_init.sh
	./tests/test_status_empty.sh
	./tests/test_loose_store_concurrent.sh

clean:
	rm -f $(BIN) $(C99)
