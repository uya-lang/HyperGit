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
	$(UYA) test src/hypergit/test_manifest_root.uya
	$(UYA) test src/hypergit/test_manifest_query.uya
	$(UYA) test src/hypergit/test_manifest_diff.uya
	$(UYA) test src/hypergit/test_commit_build.uya
	$(UYA) test src/hypergit/test_commit_graph.uya
	$(UYA) test src/hypergit/test_stage_state.uya
	$(UYA) test src/hypergit/test_stage_file.uya
	$(UYA) test src/hypergit/test_small_blob_hash.uya
	$(UYA) test src/hypergit/test_workspace_scan.uya
	$(UYA) test src/hypergit/test_workspace_state_file.uya
	$(UYA) test src/hypergit/test_local_change_file.uya
	$(UYA) test src/hypergit/test_sparse_profile.uya
	$(UYA) test src/hypergit/test_workspace_reconcile.uya
	$(UYA) test src/hypergit/test_loose_store.uya
	$(UYA) test src/hypergit/test_segment_pack.uya
	$(UYA) test src/hypergit/test_checkout_plan.uya
	$(UYA) test src/hgx/test_repo_layout.uya
	$(UYA) test src/hgx/test_head_ref.uya
	$(UYA) test src/hgx/test_hydrate_missing_object.uya
	$(UYA) test src/hgx/test_commit_partial_stage.uya
	$(UYA) test src/hgx/test_cli_args.uya
	./tests/test_cli_golden.sh
	./tests/test_add_stage.sh
	./tests/test_add_delete.sh
	./tests/test_commit_first.sh
	./tests/test_commit_second_parent.sh
	./tests/test_log_first.sh
	./tests/test_diff_add.sh
	./tests/test_diff_delete.sh
	./tests/test_diff_modify.sh
	./tests/test_diff_pathspec.sh
	./tests/test_diff_binary.sh
	./tests/test_checkout_content.sh
	./tests/test_checkout_dirty.sh
	./tests/test_checkout_state_recovery.sh
	./tests/test_sparse_checkout.sh
	./tests/test_dehydrate_dirty.sh
	./tests/test_hydrate_restore.sh
	./tests/test_repo_init.sh
	./tests/test_status_empty.sh
	./tests/test_status_clean.sh
	./tests/test_status_split.sh
	./tests/test_loose_store_concurrent.sh

clean:
	rm -f $(BIN) $(C99)
