UYA ?= $(if $(wildcard $(HOME)/xyglasses/uya/bin/uya),$(HOME)/xyglasses/uya/bin/uya,$(HOME)/uya/uya/bin/uya)
SRC := src/hgx/main.uya
BIN := bin/hgx
C99 := build/hgx.c

.PHONY: check build c99 test clean

check:
	$(UYA) check $(SRC)

build:
	mkdir -p bin
	$(UYA) build $(SRC) -o $(BIN)

c99:
	mkdir -p build
	$(UYA) build $(SRC) -o $(C99) --c99

test:
	$(UYA) test src/hypergit/test_object_model.uya
	$(UYA) test src/hypergit/test_policy_placeholder.uya
	$(UYA) test src/hypergit/test_object_codec.uya
	$(UYA) test src/hypergit/test_compiler_regressions.uya
	$(UYA) test src/hypergit/test_git_interop.uya
	$(UYA) test src/hypergit/test_large_chunker.uya
	$(UYA) test src/hypergit/test_large_chunk_hash.uya
	$(UYA) test src/hypergit/test_large_chunk_store.uya
	$(UYA) test src/hypergit/test_large_chunk_manifest.uya
	$(UYA) test src/hypergit/test_large_config.uya
	$(UYA) test src/hypergit/test_large_prepare.uya
	$(UYA) test src/hypergit/test_large_range_read.uya
	$(UYA) test src/hypergit/test_exec_task.uya
	$(UYA) test src/hypergit/test_exec_queue.uya
	$(UYA) test src/hypergit/test_exec_control.uya
	$(UYA) test src/hypergit/test_exec_worker_pool.uya
	$(UYA) test src/hypergit/test_protocol_frame.uya
	$(UYA) test src/hypergit/test_protocol_request_id.uya
	$(UYA) test src/hypergit/test_protocol_fetch.uya
	$(UYA) test src/hypergit/test_protocol_push.uya
	$(UYA) test src/hypergit/test_protocol_ref_cas.uya
	$(UYA) test src/hypergit/test_protocol_published_view.uya
	$(UYA) test src/hypergit/test_protocol_http_remote.uya
	chmod +x tests/test_http_remote_smoke.sh
	$(UYA) test src/hypergit/test_merge_planner.uya
	$(UYA) test src/hypergit/test_merge_text_merge.uya
	$(UYA) test src/hypergit/test_merge_result_manifest.uya
	$(UYA) test src/hypergit/test_manifest_path.uya
	$(UYA) test src/hypergit/test_manifest_trie.uya
	$(UYA) test src/hypergit/test_manifest_shard.uya
	$(UYA) test src/hypergit/test_manifest_root.uya
	$(UYA) test src/hypergit/test_manifest_query.uya
	$(UYA) test src/hypergit/test_manifest_load.uya
	$(UYA) test src/hypergit/test_manifest_flat_diff.uya
	$(UYA) test src/hypergit/test_manifest_diff.uya
	$(UYA) test src/hypergit/test_commit_build.uya
	$(UYA) test src/hypergit/test_commit_graph.uya
	$(UYA) test src/hypergit/test_stage_state.uya
	$(UYA) test src/hypergit/test_stage_file.uya
	$(UYA) test src/hypergit/test_small_blob_hash.uya
	$(UYA) test src/hypergit/test_blake3_compat.uya
	$(UYA) test src/hypergit/test_workspace_scan.uya
	$(UYA) test src/hypergit/test_workspace_state_file.uya
	$(UYA) test src/hypergit/test_local_change_file.uya
	$(UYA) test src/hypergit/test_local_view.uya
	$(UYA) test src/hypergit/test_sparse_profile.uya
	$(UYA) test src/hypergit/test_workspace_reconcile.uya
	$(UYA) test src/hypergit/test_loose_store.uya
	$(UYA) test src/hypergit/test_segment_pack.uya
	$(UYA) test src/hypergit/test_composite_store.uya
	$(UYA) test src/hypergit/test_checkout_plan.uya
	$(UYA) test src/hgx/test_repo_layout.uya
	$(UYA) test src/hgx/test_head_ref.uya
	$(UYA) test src/hgx/test_file_remote.uya
	$(UYA) test src/hgx/test_hydrate_missing_object.uya
	$(UYA) test src/hgx/test_add_parallel.uya
	$(UYA) test src/hgx/test_commit_partial_stage.uya
	$(UYA) test src/hgx/test_checkout_security.uya
	$(UYA) test src/hgx/test_cli_args.uya
	./tests/test_cli_golden.sh
	./tests/test_version_flag.sh
	./tests/test_add_stage.sh
	./tests/test_add_stage_concurrent.sh
	./tests/test_add_fast_path.sh
	./tests/test_add_pathspec_scan.sh
	./tests/test_add_skip_repo_metadata.sh
	./tests/test_add_permission_error.sh
	./tests/test_add_reserved_name_error.sh
	./tests/test_add_delete.sh
	./tests/test_add_delete_file_pathspec.sh
	./tests/test_add_large_file.sh
	./tests/test_add_large_file_small_edit.sh
	./tests/test_add_parallel_small_blob.sh
	./tests/test_add_parallel_mixed_blob.sh
	./tests/test_add_stale_stage_lock.sh
	./tests/test_add_symlink.sh
	./tests/test_commit_first.sh
	./tests/test_commit_large_staged.sh
	./tests/test_commit_second_parent.sh
	./tests/test_log_first.sh
	./tests/test_diff_add.sh
	./tests/test_diff_delete.sh
	./tests/test_diff_modify.sh
	./tests/test_diff_pathspec.sh
	./tests/test_diff_pathspec_scan.sh
	./tests/test_diff_binary.sh
	./tests/test_diff_large_file.sh
	./tests/test_checkout_content.sh
	./tests/test_checkout_restore_workspace.sh
	./tests/test_checkout_parallel_apply.sh
	./tests/test_checkout_dirty.sh
	./tests/test_checkout_state_recovery.sh
	./tests/test_sparse_checkout.sh
	./tests/test_dehydrate_dirty.sh
	./tests/test_hydrate_large_file.sh
	./tests/test_hydrate_restore.sh
	./tests/test_repo_init.sh
	./tests/test_file_remote_clone.sh
	./tests/test_push_cas_failure.sh
	./tests/test_fetch_sparse_profile.sh
	./tests/test_http_remote_smoke.sh
	./tests/test_status_empty.sh
	./tests/test_status_clean.sh
	./tests/test_status_large_staged.sh
	./tests/test_status_reserved_name_error.sh
	./tests/test_status_split.sh
	./tests/test_loose_store_concurrent.sh

clean:
	rm -f $(BIN) $(C99)
