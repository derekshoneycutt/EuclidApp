# Tool Rendering

## Material Target

The pen and compass are polished but used bare titanium alloy, tinted by the
established tool color. Their highlights communicate strength and polish without
hiding geometric color or creating a separate glowing rim.

## Ownership

- `src/view/elements.odin` owns tool geometry, draw order, light conversion,
  bounded occluder selection, material upload, and shader fallback behavior.
- `src/view/shaders/stroke3d.vs` forwards batched vertex color data.
- `src/view/shaders/stroke3d.fs` owns coverage, reconstructed normals, shadows,
  linear-light shading, and the titanium response.
- `src/core/core.odin` owns shader handles and cached uniform locations only.

Scene geometry remains frame-local. The render state does not retain tool
occluders or allocate per frame.

## Geometry Contract

Straight pen and compass rods use conservative screen-space capsule coverage.
The fragment shader clips that coverage analytically, reconstructing cylindrical
body normals and hemispherical endpoint normals.

The compass hinge uses one continuous 48-segment triangle strip. Vertex color
encodes the interpolated view-space tangent and signed side coordinate. The
texture-coordinate channel carries centerline view depth and normalized arc
position. A uniform carries the actual source color. The fragment shader
reconstructs a tube frame orthogonal to the tangent, which keeps lighting
directional around the loop.

The arc receives both compass legs in fixed slots. Leg 1 owns the arc start and
leg 2 owns the arc end. Each leg supplies projected capsule endpoints, endpoint
view depths, radius, and a view-space tangent. Canonical view depth increases
toward the camera.

Away from the owned endpoints, projected arc/leg crossings compare interpolated
surface depths. The arc remains opaque when it is in front, reveals the already
drawn leg when it is behind, and uses a brush-scaled transition near equal depth.
Near an owned endpoint, a brush-scaled attachment mask overrides clipping and
blends the two tube normals into a welded union without false seam darkening.

Semantic active-end circles remain a separate unshaded layer. They are not
physical caps.

If the tool shader cannot load or its complete uniform contract is unavailable,
straight rods fall back to `DrawLineEx` and the hinge falls back to segmented
`DrawLineEx` rendering. This fallback remains draw-order based and does not
provide depth-aware crossings or welded attachment shading.

## Lighting Contract

World light is transformed into the orthonormal isometric view basis before
upload. All diffuse, shadow, and material arithmetic occurs in linear light:

1. Decode the source color from sRGB.
2. Apply diffuse form, tube shaping, and bounded contextual darkening.
3. Add the two-lobe titanium reflection with Schlick Fresnel.
4. Clamp once and encode to sRGB for output.

The application uses one material definition:

- roughness: `0.34`;
- normal-incidence Fresnel: `0.48`;
- source-color specular tint: `0.45`;
- maximum contextual darkening: `0.30`.

The narrow lobe represents polish. The weaker broad lobe represents ordinary
surface wear. Both lobes use derivative stabilization.

## Shadow Contract

Compass self-shadow and pen/compass interaction use at most two projected capsule
occluders. Cache draw order determines caster and receiver. Expanded screen-space
bounds reject distant pairs before uniform upload. Shadow and contact terms are
composed additively and capped by the material shadow limit.

This is an intentional screen-space approximation. It supports the reconstructed
stroke surface without claiming full world-space ray accuracy.

## Verification

`src/view/elements_test.odin` covers expanded bounds, fixed context capacity,
cache-order depth gating, world-to-view basis projection, canonical view-depth
ordering, arc parameter endpoints, attachment scaling, and stable leg slots.
Runtime shader compilation is validated through the CMake `run` target. The
complete repository gate is the CMake `check` target.

## Decision Record

- Rounded capsule endpoints: accepted.
- Derivative edge and specular stabilization: accepted.
- Compass self-shadow and pen/compass interaction shadows: accepted.
- Continuous 48-segment hinge strip: accepted after restoring view-space tangent
  normals and two-sided strip submission.
- Depth-aware incidental arc/leg crossings and welded endpoint unions: accepted.
- Exact linear-light shading: accepted; the temporary encoded-space branch was
  removed.
- Material: polished, used bare titanium alloy matching the tool color.
- Deferred: active marker integration and a world-space analytic shadow model.
