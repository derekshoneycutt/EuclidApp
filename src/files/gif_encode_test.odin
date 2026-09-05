package files

import "core:testing"

import app_core "../core"

//   Verify gif_encode_begin rejects zero and oversized dimensions.
@(test)
gif_encode_begin_rejects_invalid_dimensions :: proc(t: ^testing.T) {
    state := app_core.Gif_Encode_State{}

    testing.expect(t, !gif_encode_begin(&state, 0, 10))
    testing.expect(t, !gif_encode_begin(&state, 10, 0))
    testing.expect(t, !gif_encode_begin(&state, 70000, 10))
}

//   Verify begin+end with no frames still emits a GIF trailer byte.
@(test)
gif_encode_begin_and_end_produces_trailer_without_frames :: proc(t: ^testing.T) {
    state := app_core.Gif_Encode_State{}

    testing.expect(t, gif_encode_begin(&state, 2, 2))

    result := gif_encode_end(&state)
    defer gif_encode_free(&result)

    testing.expect(t, result.data_size > 0)
    testing.expect_value(t, result.data[result.data_size - 1], u8(GIF_TRAILER))
}

//   Verify a small RGBA frame encodes and the stream still ends with a trailer.
@(test)
gif_encode_frame_round_trip_with_small_rgba_input :: proc(t: ^testing.T) {
    state := app_core.Gif_Encode_State{}

    testing.expect(t, gif_encode_begin(&state, 2, 2))

    pixels := []u8{
        255, 0, 0, 255,
        0, 255, 0, 255,
        0, 0, 255, 255,
        255, 255, 255, 255,
    }

    ok := gif_encode_frame(&state, &pixels[0], 2, 10, 0)
    testing.expect(t, ok)

    result := gif_encode_end(&state)
    defer gif_encode_free(&result)

    testing.expect(t, result.data_size > 0)
    testing.expect_value(t, result.data[result.data_size - 1], u8(GIF_TRAILER))
}

//   Collect packed-field bytes for each Graphics Control Extension in a GIF payload.
collect_gce_packed_bytes :: proc(data: []u8) -> []u8 {
    count := 0
    for i := 0; i + 7 < len(data); i += 1 {
        if data[i + 0] != u8(GIF_GCE_INTRODUCER) ||
           data[i + 1] != u8(GIF_GCE_LABEL) ||
           data[i + 2] != u8(GIF_GCE_BLOCK_SIZE) {
            continue
        }
        count += 1
    }

    packed := make([]u8, count, context.temp_allocator)
    write_idx := 0

    for i := 0; i + 7 < len(data); i += 1 {
        if data[i + 0] != u8(GIF_GCE_INTRODUCER) ||
           data[i + 1] != u8(GIF_GCE_LABEL) ||
           data[i + 2] != u8(GIF_GCE_BLOCK_SIZE) {
            continue
        }

        packed[write_idx] = data[i + 3]
        write_idx += 1
    }

    return packed
}

//   Verify frames above the alpha threshold set the GCE transparency flag.
@(test)
gif_encode_marks_current_frame_transparency_in_gce :: proc(t: ^testing.T) {
    state := app_core.Gif_Encode_State{}
    testing.expect(t, gif_encode_begin(&state, 2, 2))

    state.alpha_threshold = 256

    transparent_pixels := []u8{
        255, 0, 0, 255,
        0, 255, 0, 255,
        0, 0, 255, 255,
        255, 255, 255, 255,
    }

    testing.expect(t, gif_encode_frame(
        &state, &transparent_pixels[0], 2, 10, 0))
    testing.expect(t, gif_encode_frame(
        &state, &transparent_pixels[0], 2, 10, 0))

    result := gif_encode_end(&state)
    defer gif_encode_free(&result)

    gce_packed := collect_gce_packed_bytes(result.data[:result.data_size])
    testing.expect_value(t, len(gce_packed), 2)

    expected_packed := u8(GIF_GCE_PACKED_DISPOSE_BACKGROUND_TRANSPARENCY)
    testing.expect_value(t, gce_packed[0], expected_packed)
    testing.expect_value(t, gce_packed[1], expected_packed)
}

//   Verify fully opaque frames leave the GCE transparency flag unset.
@(test)
gif_encode_opaque_frames_do_not_set_gce_transparency :: proc(t: ^testing.T) {
    state := app_core.Gif_Encode_State{}
    testing.expect(t, gif_encode_begin(&state, 2, 2))

    opaque_pixels := []u8{
        255, 0, 0, 255,
        0, 255, 0, 255,
        0, 0, 255, 255,
        255, 255, 255, 255,
    }

    testing.expect(t, gif_encode_frame(&state, &opaque_pixels[0], 2, 10, 0))
    testing.expect(t, gif_encode_frame(&state, &opaque_pixels[0], 2, 10, 0))

    result := gif_encode_end(&state)
    defer gif_encode_free(&result)

    gce_packed := collect_gce_packed_bytes(result.data[:result.data_size])
    testing.expect_value(t, len(gce_packed), 2)

    expected_packed := u8(GIF_GCE_PACKED_DISPOSE_BACKGROUND_NO_TRANSPARENCY)
    testing.expect_value(t, gce_packed[0], expected_packed)
    testing.expect_value(t, gce_packed[1], expected_packed)
}
