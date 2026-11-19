"""
    DRAM_lab

Circuits and simulations for the ECE 5420 DRAM lab: a 4-word × 4-bit dynamic memory in
the AMI 0.6 μm CMOS process, simulated with ngspice through Microelectronics.jl. Every
cell is an ASCII drawing (SchematicSVG) that is both the figure and the netlist.

- Cells: [`cell_schematic`](@ref), [`subckt`](@ref), [`library`](@ref)
- Address decoder: [`DECODER_BLANK`](@ref), [`decoder_schematic`](@ref),
  [`decoder_subckt`](@ref), [`decoder_test`](@ref)
- Calibration: [`inverter_vtc`](@ref), [`crossover`](@ref), [`inverter_sweep`](@ref),
  [`ota_output`](@ref), [`ota_sweep`](@ref), [`ota_transfer`](@ref)
- The memory: [`Write`](@ref), [`Read`](@ref), [`sequence`](@ref),
  [`dram_netlist`](@ref), [`simulate_dram`](@ref), [`read_results`](@ref),
  [`bumps`](@ref), [`predicted_bumps`](@ref), [`plot_dram`](@ref)
- Reading figures: [`figure`](@ref)
"""
module DRAM_lab

using SchematicSVG
using Microelectronics
using Microelectronics: NgHerb
using Unitful
using Printf
import Plots

export cell_schematic, subckt, library, CELLS
export DECODER_BLANK, DECODER_KEY, decoder_schematic, decoder_subckt, decoder_test
export inverter_vtc, crossover, inverter_sweep, ota_output, ota_sweep, ota_transfer
export Write, Read, Timing, sequence, DEFAULT_OPS, dram_netlist, simulate_dram
export read_results, bumps, predicted_bumps, plot_dram, plot_read, plot_sequence, figure
export nonoverlap_clocks, plot_clocks, NOR_DECODER, png_plots

include("cells.jl")
include("decoder.jl")
include("system.jl")
include("testbenches.jl")
include("plots.jl")
include("figures.jl")

end # module
