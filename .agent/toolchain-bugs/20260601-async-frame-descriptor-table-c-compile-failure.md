## Summary
`uya test` 在编译 `workspace.vfs` 相关测试时，会生成引用 `struct AsyncFrameDescriptorTable` 的 C 代码，但未带入该结构体定义，导致宿主 `cc` 在 C 编译阶段失败。向 `src/hypergit/workspace/vfs.uya` 显式加入 `use std.async_frame;` 后，问题可暂时绕过。

## Status
Resolved as of 2026-06-02 by the Uya C99 async-frame descriptor emission fix. The corrected repro script now compiles, links, and runs successfully; the generated test reports `minimal vfs workspace plan build ... OK`.

## Affected Tasks
- FUSE / 平台 VFS / 内核级虚拟工作区。
- 定义 VFS provider / placeholder entry / materialization request 数据结构与规划器，并补齐单元测试。
- 将 sparse / hydrate / dehydrate / workspace local view 接入 VFS 规划层，并补齐回归测试。

## Toolchain Command
`/home/winger/uya/uya/bin/uya test src/hypergit/test_workspace_vfs.uya`

## Actual Error
`cc` 在编译生成的 `/tmp/uya_output_*.c` 时失败，关键报错是：

- `struct AsyncFrameDescriptorTable _uya_async_frame_descriptors = {`
- `error: variable ‘_uya_async_frame_descriptors’ has initializer but incomplete type`
- `error: ‘struct AsyncFrameDescriptorTable’ has no member named ‘entries’`
- `错误：C 源编译失败`
- `错误：宿主工具链链接失败`

## Expected Behavior
`uya test` 应完成 C 代码生成、对象编译、链接并运行测试，和 `test_local_view` 一样正常通过。

## Repro File
`.agent/toolchain-bugs/repros/20260601-vfs-workspace-plan-c-compile-bug.sh`

## Repro Code
```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_UYA="$ROOT/src/hypergit/repro_vfs_workspace_plan.uya"

trap 'rm -f "$TMP_UYA"' EXIT

cat >"$TMP_UYA" <<'EOF'
use std.runtime.entry;
use std.testing.run_test;
use std.testing.test_suite_begin;
use std.testing.test_suite_end;
use std.mem.arena.Arena;
use std.mem.arena.arena_init;

use core.ids.Hash32;
use core.ids.object_id_from_hash;
use core.ids.policy_id_from_object;
use manifest.trie.ManifestLeafInputEntry;
use manifest.trie.ManifestLeafInputList;
use manifest.trie.manifest_leaf_input_list_from_slice;
use object.types.ContentType;
use object.types.EntryKind;
use object.types.ByteList;
use workspace.state.ChangeStatus;
use workspace.state.LocalChange;
use workspace.state.LocalChangeList;
use workspace.state.local_change_list_from_slice;
use workspace.sparse_profile.SparseProfile;
use workspace.sparse_profile.sparse_profile_default;
use workspace.vfs.VfsProviderKind;
use workspace.vfs.VfsWorkspacePlan;
use workspace.vfs.vfs_workspace_plan_build;

fn make_hash(seed: byte) Hash32 {
    var hash: Hash32 = Hash32{ bytes: [] };
    var i: usize = 0 as usize;
    while i < 32 as usize {
        hash.bytes[i] = seed + i as byte;
        i = i + 1 as usize;
    }
    return hash;
}

fn test_vfs_workspace_plan_build_minimal() !void {
    var arena_buf: [byte: 4096] = [];
    var arena: Arena = Arena{ buffer: &arena_buf[0], size: 0, used: 0 };
    arena_init(&arena, &arena_buf[0], 4096 as usize);

    var alpha_path: [byte: 9] = ['a' as byte, 'l' as byte, 'p' as byte, 'h' as byte, 'a' as byte, '.' as byte, 't' as byte, 'x' as byte, 't' as byte];
    var beta_path: [byte: 8] = ['b' as byte, 'e' as byte, 't' as byte, 'a' as byte, '.' as byte, 't' as byte, 'x' as byte, 't' as byte];

    var full_inputs: [ManifestLeafInputEntry: 2] = [
        ManifestLeafInputEntry{
            path: ByteList{ ptr: alpha_path[0: 9].ptr, len: 9 as usize },
            kind: EntryKind.File,
            mode: 33188u32,
            object_id: object_id_from_hash(make_hash(20 as byte)),
            logical_size: 5u64,
            content_type: ContentType.Unknown,
            policy_id: policy_id_from_object(object_id_from_hash(make_hash(21 as byte))),
        },
        ManifestLeafInputEntry{
            path: ByteList{ ptr: beta_path[0: 8].ptr, len: 8 as usize },
            kind: EntryKind.File,
            mode: 33188u32,
            object_id: object_id_from_hash(make_hash(22 as byte)),
            logical_size: 4u64,
            content_type: ContentType.Unknown,
            policy_id: policy_id_from_object(object_id_from_hash(make_hash(23 as byte))),
        },
    ];
    var current_changes: [LocalChange: 1] = [
        LocalChange{
            path: ByteList{ ptr: alpha_path[0: 9].ptr, len: 9 as usize },
            base_object: full_inputs[0].object_id,
            working_hash: make_hash(26 as byte),
            status: ChangeStatus.Materialized,
            last_seen_inode: 1u64,
            last_seen_mtime_ns: 1i64,
            last_seen_logical_size: 5u64,
            watcher_seq: 1u64,
            reconcile_epoch: 1u64,
        },
    ];
    var target_changes: [LocalChange: 1] = [
        LocalChange{
            path: ByteList{ ptr: beta_path[0: 8].ptr, len: 8 as usize },
            base_object: full_inputs[1].object_id,
            working_hash: make_hash(27 as byte),
            status: ChangeStatus.Virtual,
            last_seen_inode: 0u64,
            last_seen_mtime_ns: 0i64,
            last_seen_logical_size: 0u64,
            watcher_seq: 2u64,
            reconcile_epoch: 2u64,
        },
    ];

    const full_list: ManifestLeafInputList = manifest_leaf_input_list_from_slice(full_inputs[0: 2]);
    const current_change_list: LocalChangeList = local_change_list_from_slice(current_changes[0: 1]);
    const target_change_list: LocalChangeList = local_change_list_from_slice(target_changes[0: 1]);
    const profile: SparseProfile = try sparse_profile_default(&arena);
    const plan: VfsWorkspacePlan = try vfs_workspace_plan_build(
        &arena,
        VfsProviderKind.UserSpace,
        &full_list,
        &profile,
        &current_change_list,
        &target_change_list,
    );

    _ = plan;
}

export fn main() i32 {
    test_suite_begin("HyperGit VFS Workspace Plan Repro");
    run_test("minimal vfs workspace plan build", test_vfs_workspace_plan_build_minimal);
    return test_suite_end();
}
EOF

chmod +x "$TMP_UYA"
/home/winger/uya/uya/bin/uya test "$TMP_UYA"
```

## Notes
- 这是 Uya C99 后端在某些输入图下漏发 `AsyncFrameDescriptorTable` / `_uya_async_frame_descriptors` 定义，而不是 `workspace.vfs` 语义错误。
- 回归覆盖已加入 Uya：`tests/verify_c99_async_frame_empty_descriptors.sh` 验证无 `@async_fn` 时仍会发射空 descriptor 表和 `int32_t _uya_async_frame_descriptor_count = 0;`。
