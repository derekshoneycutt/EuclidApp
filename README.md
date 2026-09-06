# Euclid

Euclid is a desktop visualization application for viewing geometric constructions based on
pen, compass, and plane constructions. We focus on Euclid's Elements, and we also include
sections such as Proclus's Commentaries, Hilbert's Foundations of Geometry, and algebraic
demonstrations.

This is primarily a Julia-focused application, utilizing the interactive nature of the
langauge for animations and a REPL-like Scratchpad. Featuring the
[JuliaMono](https://juliamono.netlify.app/) font, available under the OFL/SIL license.

The code and documentation of this project is under The Unlicense, being public domain.

The core application is coded in Odin, with Raylib used for rendering.

1. [Building from Source](#building-from-source)
1. [Questions?](#questions)
    1. [Q: Why?](#q-why)
    1. [Q: What's the utility?](#q-whats-the-utility)
    1. [Q: What about AI?](#q-what-about-ai)
    1. [Q: What is the "Scratchpad"?](#q-what-is-the-scratchpad)
    1. [Q: Wait, Save Gif?](#q-wait-save-gif)
    1. [Q: You support LaTeX?](#q-you-support-latex)
    1. [Q: Any performance hacks for users?](#q-any-performance-hacks-for-users)
    1. [Q: Why 2 languages?](#q-why-2-languages)
    1. [Q: Are there any more build and verification options?](#q-are-there-any-more-build-and-verification-options)
    1. [Q: Where should I start if I want in the code?](#q-where-should-i-start-if-i-want-in-the-code)
    1. [Q: What's this about hot-reload?](#q-whats-this-about-hot-reload)
    1. [Q: What is all this verification output?](#q-what-is-all-this-verification-output)

<p align="center">
<img src="./screen.gif" >
</p>

## Building from Source

Source builds require CMake 3.28 or newer, Ninja, Odin, and Julia, with each tool
available on PATH. HarfBuzz and its runtime dependencies use `HarfBuzz_jll` from the
Julia project by default, so a separate HarfBuzz installation is not required.

Unix source and distribution builds may intentionally select system HarfBuzz with
`EUCLID_HARFBUZZ_PROVIDER=system`. This mode also requires `pkg-config` and the
HarfBuzz development package: install `harfbuzz-devel` on Fedora,
`libharfbuzz-dev` on Debian/Ubuntu, or `harfbuzz` and `pkg-config` through Homebrew
on macOS. Use the `system-harfbuzz` CMake preset to select and validate this mode.

Windows source builds require Odin, Julia, `gendef`, and the Visual Studio C++
Build Tools. Windows supports only the default `HarfBuzz_jll` provider.

Clone the repository, configure one preset, then build it. CMake verifies the
toolchain and bootstraps the required Julia environments before invoking the
project-specific Julia driver.

### Configure and build

```bash
git clone https://github.com/derekshoneycutt/Euclid.git
cd Euclid
cmake --preset default
cmake --build --preset default
cmake --build --preset default --target run
```

The same commands work from Unix shells and PowerShell. Presets keep CMake metadata
isolated under `.build/cmake/` while preserving Euclid's existing outputs under
`bin/` and `.build/debug/`.

### Presets

```bash
cmake --preset default
cmake --preset debug
cmake --preset strict
cmake --preset system-harfbuzz  # Unix only
```

Build the matching configuration with `cmake --build --preset PRESET`. The debug
preset retains synchronized diagnostics and `.build/debug/` outputs. The strict
preset enables Odin vet, strict style, disallowed `do`, and warnings-as-errors.

### Build and test targets

```bash
cmake --build --preset default --target assets
cmake --build --preset default --target unit
cmake --build --preset default --target vet
cmake --build --preset default --target check
cmake --build --preset default --target harness
cmake --build --preset default --target sysimage
cmake --build --preset default --target wiki
cmake --build --preset default --target check-wiki
```

`check` is the canonical complete verification gate. CMake reserves `test` for
CTest's selectable suites:

```bash
ctest --preset unit
ctest --preset all
```

The generator-owned `clean` target removes CMake-known outputs. The `clean-all`
target invokes Euclid's comprehensive generated-artifact cleanup without deleting
the active `.build/cmake/` trees.

### Parameterized commands

Keep using the Julia driver directly when an operation takes paths or frequently
changing options:

```bash
julia tools/make.jl check src/dynview
julia tools/make.jl stats src/main.odin --line=310
julia tools/make.jl evidence capabilities
julia tools/make.jl unit odin
julia tools/make.jl run --debug -- --diagnostics=.build/debug/euclid.log
```

Additionally, on Linux you might need to build the STB font vendor packages in Odin to get
an appropriate build. This can typically be done by locating the Odin directory and
running something like this:

```sh
sudo /usr/lib64/odin/vendor/stb/src/build_stb.sh
```

### Windows requires a few more additions before this will work

- `MSVC Toolchain` : Odin will require MSVC tools installed on the system.
- `gendef` : used in the script to bridge the fact that Julia is not built with
  the same toolchain as Odin uses to build binaries. `gendef` can be installed via e.g.
  Strawberry Perl or MSYS2.

## Questions?

### Q: Why?

Because Euclid is *fun*, and rendering fun drawings of Elements is *fun*. It is also quite
educational and works out the brain a bit. You should try such things sometimes.

### Q: What's the utility?

Well, it is educational!

It's also seriously just *fun*.

### Q: What about AI?

First, my general policy on it is this: I will not accept code in this project that cannot
be thoroughly explained and followed up on by a human coder. I do read and work on every
line of code in this project myself, regardless of where that code has come from--be it
the old depths of stack overflow, my brain, someone else's brain, some AI tool or another,
or some other tool.

This is not going to be as strong as some would wish. For a project being released into
the public domain, I just do not have the energy for a stronger stance in this project.
A public domain project is really not the place for many of the ethical and political
discussions. I will not be fighting that in this project. This will not be a project that
is concerned with any stronger stance than demanding a human take full responsibility.

I do see this as an educational project. I am certainly expanding my understanding of
geometry as I explore it, and I am learning a lot about graphics programming. Sometimes my
code sucks, and even AI will gladly point it out the second someone points a code review
agent at it. The code suggested by AI is quite often not very good without modification.

Finally, yes, there is code that has used AI in this. Again, my conclusion remains: They
really are not very good on their own. I do need to point out I often continue to
experiment with the AIs in order to show potential employers that I know how to use the
things. Additionally, I am getting my Masters in Computer Science, specializing in AI. So
yes, I do practice in this codebase. Again, I take full responsibility and hand-work on
all code. I have added a comprehensive, opinionated static analysis engine; I did this
*even moreso* because I forget things and do embarrassingly stupid things even when I am
coding by hand, but it helps against bad AI code, too. If an AI driver cannot explain how
they have gotten code through this static analysis in this project, I'm not really
interested in their code. I think that is a strong enough stance.

### Q: What is the "Scratchpad"?

Before continuing, the point of the Scratchpad is indeed to make the application even more
*fun*. Once again, the point is to be *fun*. Nonetheless, it is a bit technical, including
computer code. Reader beware. Caution to the wind, this does also provide some educational
benefit for the tinkerers out there, I think, which is a beneficial addition.

The code of this project is designed with a core engine coded in Odin, but all of the
animations are executed as Julia scripts. Julia is a fast, JIT compiled language in this
use. Julia users will also be familiar with the REPL, where they can enter in Julia code
essentially line-by-line and see how it works in a live environment. The Scratchpad in
this project is like this. It provides an emptied drawing surface and a line input for
Julia code input. `2+2` will show `4` in the output directly above, for example. In fact,
via using Julia's `REPL` package directly, even scope issues should follow similar Julia
REPL standards for those already familiar.

`:help` will show most of the important information for how to use the Scratchpad in
practice. You can also type `?` to immediately enter the standard Julia REPL help mode,
navigating the code documentation in the project.

A quick cheatsheet for drawing the standard Euclidean matters:

- `point!([x, y, z])` e.g. `point!([0.5f0, 0.5f0, 0f0])`
  : Animates drawing a single point.
- `line!([x1, y1, z1], [x2, y2, z2])` e.g.
  `line!([0.1f0, 0.1f0, 0f0], [0.1f0, 0.9f0, 0f0])`
  : Animates drawing a line from [x1, y1, z1] to [x2, y2, z2].
- `circle!([x, y, z], r)` e.g. `circle!([0.5f0, 0.5f0, 0f0], 0.25f0)`
  : Animates drawing a circle centered at [x, y, z], with a radius of r.

#### Some details about using the Scratchpad

The `state_ptr` variable is *always* available from the Scratchpad. This is the first
parameter that is sent to all `OdinJuliaBridge` functions, and it holds a value of type
`Ptr{Cvoid}`, pointing back to the Odin state structure in memory.

Coordinate reminders:

- Use normalized surface coordinates: `x, y ∈ [0.0, 1.0]`.
- Treat `z = 0.0` as the draw surface; positive `z` is up (pen lift/travel).
- Follow a right-hand orientation for 3D thinking: on screen, +X trends up-right and +Y
  trends up-left on the surface; set your right thumb to +X and index to +Y, and your
  middle finger gives +Z (up/elevation). See
  [Right hand rule](https://en.wikipedia.org/wiki/Right-hand_rule)
  with the knowledge that we are always x pointed up-right, y pointed up-left in our
  projections for this project.

This is meant for prototype drawing, as opposed to dedicated animations. However, fast
one-off animations are possible via the frame loop hooks that are included. See the list
of helpers in `:help`. If you bracket the beginning and end of an animation with
`OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)`, you can even use the Save
Gif feature to save a gif of your one-off animations. You will be responsible for managing
the state machine of such animations. You can use REPL variables or the OdinJuliaBridge
metadata storage functions used by most static animations.

### Q: Wait, Save Gif?

Yup, you can save an animation to a gif file! This is available via the camera icon in the
top right of the window. This requires that an animation notify when it begins and ends,
meaning the top animation for many sections will not be allowed to be saved. Most other
animations can be saved to a gif file, directly from your viewpoint. Click the camera icon
to enter the Gif Export view, and click Save Gif. The request will be logged, pending the
start of the next animation. When the next animation starts, notifying the animation cycle
boundary, the gif is initiated, and frames are saved into the gif buffer. When the
animation ends, again notfying the animation cycle boundary, the gif buffer is then saved
to a file.

If animation is paused in the middle of a gif save, the paused time is not included in the
animation. It is all skipped and the gif proceeds as if it was never paused. If the
animation is reset, the gif is canceled.

I have some thoughts about other potential export formats that could be done from the
camera tab, but for today, it is just gifs. The current code was ported from several
pieces of C code walking through saving a gif, and something like ffmpeg could probably
significantly improve on even that, as well as adding other formats. Such are
considerations for the future.

### Q: You support LaTeX?

Yes. Somehow, I ended up writing a little mini-LaTeX math renderer in this project. It was
kind of a pain in the ass for half a week, and it does not yet support everything one
might hope to find in a more thorough LaTeX rendering engine. This is basically a work in
progress. The code is kind of a mess, I know it. No shame... well, there's a little bit of
shame about it, but we're just gonna sit in that and learn.

Check out [LaTeX Support](docs/wiki/Guides/LaTeXSupport.md) for exactly what we do support
today.

The fun thing is that the REPL will render LaTeX if the output is fully a LaTeX MIME type.
For example, LaTeXStrings gives the `L"..."` syntax, which will render a LaTeX string as
much as is supported. `LaTeXStrings` is automatically included in the REPL, so you can use
this to play with what is supported.

Currently, only math mode is supported. Maybe I'll add more? Hmm...

### Q: Any performance hacks for users?

There are a few!

At the top right of the screen, you can go into the Settings panel. Here, you can reduce
the maximum number of dust particles that are allowed on the drawing surface, which can
improve performance. You can also turn the FPS display on/off, enable or disable drawing
sound, and turn FPS limiting on/off. Turning the FPS limit on/off may have no real effect
if vsync is on (the default). Additionally, you can toggle SIMD use for use in isometric
projection, which is on by default. The SIMD has little effect either way on most modern
computers, to be honest, especially given LLVM may make this optimization in either case.
The single biggest performance tweak is the default-enabled GPU Dust Instancing, which
will draw the dust particles with the GPU.

The optional sysimage with `make.jl` bakes stable Julia runtime modules and representative
LaTeX/Scratchpad compiler workloads into a platform-specific shared library beside the
executable. Build and run it with `julia tools/make.jl sysimage`, then
`julia tools/make.jl run-only`. Ordinary build or asset
commands remove an existing sysimage to prevent stale baked code from being used.

Additionally, there are some startup options that can affect application performance.

```text
Usage: ./euclid [options]

Options:
  -v, --vsync              Enable VSYNC. (default)
  -V, --no-vsync           Disable VSYNC.
  -a, --antialiasing       Enable anti-aliasing. (default)
  -A, --no-antialiasing    Disable anti-aliasing.
  --dust-particle-max=N    Set maximum dust particles, 0-8192. (default: 8192)
  -f, --limit-fps          Limit rendering to 60 FPS. (default)
  -F, --no-limit-fps       Disable the 60 FPS limit.
  -s, --simd               Enable SIMD projection when available. (default)
  -S, --no-simd            Disable SIMD projection.
  -g, --gpu-dust-instancing Enable GPU dust instancing when available. (default)
  -G, --no-gpu-dust-instancing Disable GPU dust instancing.
  --semantic-trace         Enable semantic trace output.
  --semantic-trace-output=PATH  Write semantic trace JSONL to PATH.
  --semantic-trace-events=LIST   Limit trace categories (runtime,animation,geometry,tools,particles,view).
  --semantic-trace-strict  Fail the run when trace overflow or serialization fails.
  -h, --help               Show this help text.

Short options can be combined, for example: -vasg or -VAFSG
```

### Q: Why 2 languages?

Because saying "Odin-Julia Bridge" is *fun*.

This whole thing began using Julia with Makie to draw Euclid's Elements inside Jupyter
notebooks. Ultimately, it became quite clear that what I was looking for was not a great
fit to that model, and I froze on it a bit.

I had some thoughts about making a C application for this project, but I was not very
excited about it at any given moment. Julia has lagged a bit in getting a stand-alone
executable route, so it seemed unlikely to go purely Julia for quite a while. This has
been changing as Julia community continues pursuing their one language paradigm, but alas,
here I am. As I was doing another project exploring 76 different programming languages, I
encountered Odin and enjoyed working with it. On a whim, I was playing with a basic
kinematic system in Odin when it occurred to me it would be a great basis for this
Euclid project.

Ultimately, having a strong solid application base with manual memory management and
potential for optimizations at a relatively low level combined with an intentionally fast,
JIT compiled, GC managed language on the individual animation level has its own
advantages. I probably would not actually choose this without the unique history of this
project, but it is actually quite an enjoyable programming experience between the two.
They are different languages, but both offer language-level tools for the kind of maths
used in this project that just make it an enjoyable experience!

### Q: Are there any more build and verification options?

The Julia build driver provides focused parameterized commands when the CMake
targets above are not enough.

```text
Usage: julia tools/make.jl COMMAND [ARGUMENTS]

Commands:
  help                         Show this help text.
  build [--debug] [--strict]   Build the application and assets.
  run [--debug] [--strict] [-- APP_ARGS]
                 Build and run the application.
  run-only [--debug] [-- APP_ARGS]
                 Run an existing application binary.
  assets                       Build assets.pkg only.
  sysimage [--debug] [--strict]
                 Build the application, assets, and Julia sysimage.
  harness                      Build and run the deterministic headless harness.
  unit [julia|odin] [OPTS]     Run all application tests or one language suite.
  vet [OPTS]                   Build and analyze the repository.
  test [OPTS]                  Run the complete verification gate.
  check [PATH] [OPTS]          Analyze PATH; defaults to the repository.
  stats FILE [OPTS]            Show targeted source statistics.
  analyzer-test                Run the analyzer's own test suite.
  wiki                         Generate the publishable Wiki artifact.
  check-wiki                   Verify that the Wiki artifact is current.
  clean                        Delete generated build artifacts.

Verification options (forwarded by vet and test):
    --verbosity=0|1|2   Summary, details, or complete trace output.
    --verbose           Alias for --verbosity=2.
    --color=auto|always|never
    --format=text|json  Select human or complete machine output.
    --settings=PATH     Load analyzer settings from PATH.
    --report=PATH       Write the compact Markdown analysis report.
    --full-report=PATH  Write the comprehensive Markdown analysis report.
```

The harness target is intended for semantic trace and deterministic scenario work. Its
underlying executable accepts a smaller control surface:

```text
Usage: euclid_harness --asset-root=PATH --animation-id=UUID --steps=N --trace-output=PATH [--scenario=NAME]
```

`julia tools/make.jl harness` builds and runs the default harness scenario and writes the
resulting canonical binary trace to `bin/semantic-trace-harness.bin`. Query that bare
trace or a scenario bundle through the same evidence command:

```sh
julia tools/make.jl evidence query bin/semantic-trace-harness.bin \
  --kind=animation_tick_committed
julia tools/make.jl evidence query .build/scenarios/SCENARIO-RUN --failures
```

Application `--semantic-trace-output=PATH` remains the explicit JSONL export for
human-readable traces.

### Q: Where should I start if I want in the code?

I have added an initial architecture summary and coding standards that can be your guides.

- [Architecture Summary](docs/wiki/Guides/ArchitectureSummary.md): describes the several
  modules, boundaries, etc., and how they fit together. Includes important code files to
  start with.
- [Coding Standards](docs/wiki/Guides/CodingStandards.md): describes how any new code
  should be written

Some additional documentation is also available in the wiki, including the above:

- [Euclid Wiki](https://github.com/derekshoneycutt/Euclid/wiki):
 published project documentation.
- [Code Reference](https://github.com/derekshoneycutt/Euclid/wiki/Code/Home):
 generated Odin and Julia API documentation.

Generate the complete publishable Wiki artifact locally with
`julia tools/make.jl wiki`. The artifact is written to ignored `bin/wiki/`. Run
`julia tools/make.jl check-wiki` to compare it against a fresh generation without
modifying the retained artifact.

### Q: What's this about hot-reload?

The project is structured to hot-reload all Julia code if the assets package is updated.
You can simply call the make script specifying to build only the assets package. Then
copy the built package next to the running instance. If you run from the `bin` folder of
a compilation, this will automatically replace the assets package there.

```bash
julia tools/make.jl assets
```

Euclid will automatically notice the updated package file, unpack it, and reload all
the Julia code, restarting the current animation according to the new code. If the current
animation cannot be found, will simply start the first animation in the tree. This can be
helpful for simple animation updates.

Animation content remains dynamically loaded when using a sysimage. Changes to baked core
modules such as the bridge wrappers, TeX source facade, geometry helpers, animation helpers,
or Scratchpad require rebuilding the sysimage and restarting Euclid.

### Q: What is all this verification output?

Great question! A lot of this only makes any sense if you are really into the software
engineering stuff. We perform several checks in the vet mode to try and improve code
quality and performance.

**FIRST**: Analysis runs through the OdinJuliaAnalysis engine in the
`tools/analysis` submodule, with Euclid policy in `tools/analysis_settings.jl`.
The CMake bootstrap target instantiates the analyzer's own Julia project
(`tools/analysis/Project.toml`), so nothing extra is installed into Julia's
default environment (see [Building from Source](#building-from-source)). The
submodule must be initialized first:

```bash
git submodule update --init --recursive
cmake --preset default
cmake --build --preset default --target configure
```

The application build itself uses standard parameters. Compiler-validation flags
(`-vet -strict-style -disallow-do -warnings-as-errors`) are applied by the analysis
engine's own dedicated analytical Odin build, not by the application build.

Repository-wide statistics (line counts, complexity, COCOMO, and an LLM
regeneration-cost estimate) come from the analyzer's canonical report. No external
code counter (such as `scc`) is required; everything is derived from the same parser
streams the rest of the analysis pipeline uses.

```bash
julia tools/make.jl vet
```

#### Report Output

Vet mode writes the full analysis report to `.build/reports/analysis.md` on every
run. Console output stays summary-first (phase table, code statistics, then any
warnings or failures) and points to that report for full detail.

The gate ends with a verification phase table. A phase is `PASS` when it completed
without blocking findings and `FAIL` when it produced blocking findings or could not
complete. `--verbose` or `--verbosity=2` replays complete captured phase output, and
`--format=json` emits the complete machine report for automation.

Analysis covers the Odin build, Julia and Odin syntax, naming, complexity, return
shape, parameters, documentation, JET entry points, Odin allocations with reviewed
policies, and repository metrics. Reviewed exceptions live in
`tools/analysis_settings.jl` and are drift-checked, so stale suppressions fail.

#### Odin

The analysis engine runs its own dedicated analytical Odin build with strict
compiler flags (`-vet -strict-style -disallow-do -warnings-as-errors`) plus the
Julia linker flags, treating warnings as errors. The application build itself uses
standard parameters; the analytical build is the compiler-validation gate.

The engine also parses every Odin procedure and measures it against the coding
standards: executable lines, cyclomatic complexity, and parameter count. Reviewed
exceptions live in `tools/analysis_settings.jl` as drift-checked policies rather
than inline markers. It additionally traces allocation call sites (`new`, `make`,
`append`, and known allocating helpers) and classifies each by allocator source;
sites are reported in the analysis report's allocation ledger.

The `repo-metrics` section (see below) provides additional repository-wide
statistics.

#### Julia

For Julia, the engine parses the source with JuliaSyntax to catch obvious syntax
errors before anything runs, then measures functions (lines, cyclomatic
complexity, parameters, return shape) and runs JET against configured entry
points. Animation content loops and similar reviewed cases are exact exceptions in
`tools/analysis_settings.jl`, so the blocking rules stay active everywhere else.

The `repo-metrics` section (see below) provides additional repository-wide
statistics.

#### Repository statistics

The report computes repository-wide statistics with the project's own analysis
toolchain, replacing the external `scc` code counter. Because it reuses the same
parsers that power the other checks (JuliaSyntax for Julia, `core:odin/parser`
for Odin), its line and complexity figures are parse-accurate rather than
regex/keyword estimates. It throws no warnings or errors and cannot guarantee code
quality, but it isolates logic hotspots and shows how the code is structured. The
Odin side will typically carry more complexity hotspots simply because it is the
ultimate arbiter of control for the application in many places.

It reports, per language and per top-level directory:

- **Line inventory**: Files, Lines, and the breakdown into Code, Comments, and
  Blank lines. A line counts as *code* when it carries at least one non-comment,
  non-string character; *comment* when it is only comment/string content; *blank*
  when empty.
- **Complexity**: total cyclomatic complexity per bucket, summed from the real
  per-function measures.
- **COCOMO (organic)**: the classic human effort/schedule/staffing estimate,
  including an estimated cost-to-develop in USD.
- **LOCOMO**: an experimental LLM *regeneration*-cost estimate (input/output
  tokens, dollar cost, iteration cycles, generation time, and human review time),
  modeled on the same idea as `scc`'s LOCOMO but fed our parse-accurate
  complexity density. This is a rough ballpark for what it would cost to have an
  LLM retype code it already knows the shape of — not the cost to design it.

A derived **Complexity/Code** ratio is reported for Odin, Julia, and Total. This is
the average number of branch points per line of code. In general, if the Odin code
remains moderately high (0.13-0.18) it is considered pretty good, and we generally
expect the Julia code to remain low-moderate (0.05-0.13). The total being a moderate
0.09-0.13 would be a great expectation. The ratio is most meaningful as a per-language
trend over time rather than a precise side-by-side comparison. For meaningful per-function
and per-file signal, the analyzer's function metric rules are more telling than these
aggregate ratios. Nonetheless, the repository statistics can indicate issues with stupid
code decisions we should feel bad about.
