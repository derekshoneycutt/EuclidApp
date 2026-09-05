package files

import "core:os"
import "core:path/filepath"
import "core:testing"


//   Create a clean per-test sandbox directory under the OS temp directory.
prepare_sandbox_dir :: proc(dir_name: string) -> (string, bool) {
    temp_dir, temp_err := os.temp_directory(context.temp_allocator)
    if temp_err != nil || len(temp_dir) == 0 {
        return "", false
    }

    path, path_err := filepath.join([]string{temp_dir, dir_name}, context.allocator)
    if path_err != nil || len(path) == 0 {
        return "", false
    }

    _ = os.remove_all(path)
    if os.make_directory_all(path) != nil {
        return "", false
    }

    return path, true
}

//   Write one required file entry (with parent dirs) under a test root.
write_required_entry :: proc(root_dir, rel_path: string) -> bool {
    last_separator := -1
    for i in 0..<len(rel_path) {
        if rel_path[i] == '/' {
            last_separator = i
        }
    }

    if last_separator > 0 {
        parent_rel := rel_path[:last_separator]
        parent_dir, parent_join_err := filepath.join(
            []string{root_dir, parent_rel}, context.allocator)
        if parent_join_err != nil {
            return false
        }
        defer delete(parent_dir)
        if os.make_directory_all(parent_dir) != nil {
            return false
        }
    }

    full_path, join_err := filepath.join([]string{root_dir, rel_path}, context.allocator)
    if join_err != nil {
        return false
    }
    defer delete(full_path)

    return os.write_entire_file(full_path, []u8{'x'}) == nil
}

//   Build the full required unpack tree (scripts, icon, fonts, manifest).
build_ready_unpack_tree :: proc(unpack_dir: string) -> bool {
    required := []string{
        "julia/script.jl",
        "compass_icon.png",
        "JuliaMono-Regular.ttf",
        "NewCMSansMath-Regular.otf",
        "manifest.txt",
    }

    for rel_path in required {
        if !write_required_entry(unpack_dir, rel_path) {
            return false
        }
    }

    return true
}

//   Verify is_assets_unpack_ready reports false until every required entry exists.
@(test)
is_assets_unpack_ready_requires_all_entries :: proc(t: ^testing.T) {
    unpack_dir, ok := prepare_sandbox_dir("euclid_unpack_ready")
    defer delete(unpack_dir)
    defer _ = os.remove_all(unpack_dir)
    testing.expect(t, ok)

    testing.expect(t, !is_assets_unpack_ready(unpack_dir))

    testing.expect(t, build_ready_unpack_tree(unpack_dir))
    testing.expect(t, is_assets_unpack_ready(unpack_dir))

    math_path, join_error := filepath.join(
        []string{unpack_dir, "NewCMSansMath-Regular.otf"}, context.allocator)
    defer delete(math_path)
    testing.expect(t, join_error == nil)
    testing.expect(t, os.remove(math_path) == nil)
    testing.expect(t, !is_assets_unpack_ready(unpack_dir))
}

//   Verify should_continue_unpack across the missing/partial/complete/forced matrix.
@(test)
should_continue_unpack_matrix :: proc(t: ^testing.T) {
    sandbox, ok := prepare_sandbox_dir("euclid_unpack_should_continue")
    defer delete(sandbox)
    defer _ = os.remove_all(sandbox)
    testing.expect(t, ok)

    archive_path, archive_join_err := filepath.join(
        []string{sandbox, "assets.pkg"}, context.allocator)
    unpack_dir, unpack_join_err := filepath.join(
        []string{sandbox, "unpack"}, context.allocator)
    defer delete(archive_path)
    defer delete(unpack_dir)
    testing.expect(t, archive_join_err == nil)
    testing.expect(t, unpack_join_err == nil)

    continue_unpack, result := should_continue_unpack(
        archive_path, unpack_dir, false)
    testing.expect(t, !continue_unpack)
    testing.expect(t, !result)

    testing.expect(t, os.make_directory_all(unpack_dir) == nil)
    continue_unpack, result = should_continue_unpack(
        archive_path, unpack_dir, false)
    testing.expect(t, !continue_unpack)
    testing.expect(t, result)

    testing.expect(t, os.write_entire_file(archive_path, []u8{'a'}) == nil)

    continue_unpack, result = should_continue_unpack(
        archive_path, unpack_dir, false)
    testing.expect(t, continue_unpack)
    testing.expect(t, !result)

    testing.expect(t, build_ready_unpack_tree(unpack_dir))
    continue_unpack, result = should_continue_unpack(
        archive_path, unpack_dir, false)
    testing.expect(t, !continue_unpack)
    testing.expect(t, result)

    continue_unpack, result = should_continue_unpack(
        archive_path, unpack_dir, true)
    testing.expect(t, continue_unpack)
    testing.expect(t, !result)
}

//   Verify prepare_unpack_directory clears stale contents and recreates the directory.
@(test)
prepare_unpack_directory_clears_and_recreates :: proc(t: ^testing.T) {
    sandbox, ok := prepare_sandbox_dir("euclid_prepare_unpack")
    defer delete(sandbox)
    defer _ = os.remove_all(sandbox)
    testing.expect(t, ok)

    nested_file := "inner/data.bin"
    testing.expect(t, write_required_entry(sandbox, nested_file))

    nested_file_path, nested_err := filepath.join(
        []string{sandbox, nested_file}, context.allocator)
    defer delete(nested_file_path)
    testing.expect(t, nested_err == nil)
    testing.expect(t, os.exists(nested_file_path))

    testing.expect(t, prepare_unpack_directory(sandbox))
    testing.expect(t, os.is_directory(sandbox))
    testing.expect(t, !os.exists(nested_file_path))
}

//   Verify resolve_writable_gif_output_dir rejects empty input and creates the dir.
@(test)
resolve_writable_gif_output_dir_behaviour :: proc(t: ^testing.T) {
    output_dir, ok := resolve_writable_gif_output_dir("")
    testing.expect(t, !ok)
    testing.expect_value(t, output_dir, "")

    base_dir, base_ok := prepare_sandbox_dir("euclid_gif_output")
    defer delete(base_dir)
    defer _ = os.remove_all(base_dir)
    testing.expect(t, base_ok)

    expected_output, expected_err := filepath.join(
        []string{base_dir, GIF_OUTPUT_DIR_NAME}, context.allocator)
    defer delete(expected_output)
    testing.expect(t, expected_err == nil)

    output_dir, ok = resolve_writable_gif_output_dir(base_dir)
    testing.expect(t, ok)
    testing.expect_value(t, output_dir, expected_output)
    testing.expect(t, os.is_directory(output_dir))
}
