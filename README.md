# DRAM_lab

Circuits and simulations for the ECE 5420 DRAM lab: a 4-word × 4-bit dynamic memory in the
AMI 0.6 μm CMOS process (`ami06N`/`ami06P`), simulated with ngspice through
Microelectronics.jl. Every cell is an ASCII drawing (SchematicSVG) that is both the
notebook figure and the SPICE subcircuit.

```julia
using DRAM_lab, Microelectronics, Plots
figure(:senseamp)                                  # any cell or reading figure
crossover(Wp=2.33u"μm")                            # inverter calibration
ota_output(Rref=70u"kΩ")                           # sense-amplifier calibration
decoder_test(DECODER_KEY).table                    # address decoder check
r = simulate_dram(Wp=2.33u"μm", Rref=70.1u"kΩ")    # 4 writes, then 4 reads
plot_dram(r); read_results(r); bumps(r)
```

Requires Microelectronics ≥ 1.4.7 (the AMI models) and SchematicSVG ≥ 0.12.8 (logic gates).

## Registering in LEFT_registry

1. Release Microelectronics (with `Microelectronics-ami-models.patch`) and SchematicSVG
   (with the logic-gates and MOSFET-body patches) first, so the compat bounds resolve.
2. Put this folder in its own GitHub repository and push it.
3. Register and check:

   ```julia
   using LocalRegistry
   register("path/to/DRAM_lab"; registry="LEFT_registry")
   ```
   Then push the registry, and in a fresh environment:
   ```julia
   import Pkg
   Pkg.Registry.update()
   Pkg.add("DRAM_lab")
   Pkg.test("DRAM_lab")
   ```
4. Add `DRAM_lab` to the package list in `transition_to_LEFT.jl` and `LEFT_setup.ipynb`.
