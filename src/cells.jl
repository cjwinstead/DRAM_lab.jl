# ───────────────────────── transistor-level cells ─────────────────────────
#
# Each cell is an ASCII drawing (SchematicSVG) plus the device sizes. The same drawing is
# the figure in the notebook and, through `spice_subcircuit`, the SPICE subcircuit used in
# every simulation, so what students see is what is simulated.
#
# Process: AMI 0.6 μm CMOS (ami06N / ami06P in the Microelectronics model library),
# λ = 0.3 μm, L = 0.6 μm unless noted. Diffusions are 5λ = 1.5 μm long.

const LMIN = 0.6e-6

# Source/drain areas and perimeters for a device of width W (a number in metres, or a
# Symbol naming a subcircuit parameter): 1.5 μm long diffusions.
function diffusion(W)
    if W isa Symbol
        a, p = "{$(W)*1.5u}", "{2*$(W)+3u}"
    else
        a, p = W * 1.5e-6, 2W + 3e-6
    end
    (AD=a, AS=a, PD=p, PS=p)
end

"Element value for an AMI NMOS of width `W` and length `L` (body at ground)."
nfet(W; L=LMIN) = (model="ami06N", W=W, L=L, diffusion(W)..., body="0")
"Element value for an AMI PMOS of width `W` and length `L` (body at vdd)."
pfet(W; L=LMIN) = (model="ami06P", W=W, L=L, diffusion(W)..., body="vdd")

"""
    Cell(name, art, terminals, params, elements, about)

A subcircuit drawn as ASCII art: its SPICE `name`, the drawing, the terminal order,
parameter defaults (`name => value` pairs), the element values keyed by drawn names, and
a one-line description.
"""
struct Cell
    name::String
    art::String
    terminals::Vector{String}
    params::Vector{Pair{String,Any}}
    elements::Dict{String,Any}
    about::String
end

const INV_ART = """
           vdd
            |
      +---|P1
      |     |
  in--+     *---out
      |     |
      +---|N1
            |
           gnd
"""

const NAND2_ART = """
         vdd          vdd
          |            |
   a----|P1     b----|P2
          |            |
          +------*-----+
                 |
                 *---out
                 |
         a-----|N1
                 |
         b-----|N2
                 |
                gnd
"""

const NAND3_ART = """
         vdd          vdd          vdd
          |            |            |
   a----|P1     b----|P2     c----|P3
          |            |            |
          +------------*------------+
                       |
                       *---out
                       |
               a-----|N1
                       |
               b-----|N2
                       |
               c-----|N3
                       |
                      gnd
"""

const NOR2_ART = """
            vdd
             |
     a-----|P1
             |
     b-----|P2
             |
             *---out
             |
      +------*------+
      |             |
a---|N1      b----|N2
      |             |
     gnd           gnd
"""

const TG_ART = """
            a
            |
      +-----*-----+
      |           |
ng--|N1           P1|--pg
      |           |
      +-----*-----+
            |
            b
"""

# Gate-level cells: inverters and transmission gates, netlisted as X instances.
const DLATCH_ART = """
       enn
        |
d-------TG1---+---INV1---INV2---+---q
        |     |                 |
        en    |     en          |
              |     |           |
              +-----TG2---------+
                    |
                    enn
"""

const DRIVER_ART = """
                         wrn
                          |
d---INV1---INV2-----------TG1---+---bl
                          |     |
                          wr    |
                                |
                         pren   |
                          |     |
vh------------------------TG2---+
                          |
                          pre
"""

const CELL_ART = """
           bl
           |
    wl---|N1
           |
           *--@sn
           |
           CD
           |
          gnd
"""

# The OTA sense amplifier: a differential pair (N3, N4) with a PMOS mirror load (P5, P6),
# a tail mirror (N1, N2) biased through Rref, and a reference input of VDD/2 from R1, R2.
# An inverter restores the logic level.
const SENSEAMP_ART = """
  vdd                vdd               vdd                    vdd
   |                  |                 |                      |
   R1                 P5|-----+--------|P6                     Rref
   |                  |       |         |                      |
   +--------+         *-------+         *--@y--INV1---dout     |
   |        |         |                 |                      |
   R2       +-------|N3         bl----|N4                      |
   |                  |                 |                      |
  gnd                 +--------*--------+                      |
                               |                               |
                              N2|------------------------------*---+
                               |                               |   |
                              gnd                              N1|-+
                                                               |
                                                              gnd
"""

const CELLS = Dict{Symbol,Cell}(
    :inv => Cell("inv", INV_ART, ["in", "out"], ["Wp" => 3e-6, "Wn" => 1.5e-6],
                 Dict("P1" => pfet(:Wp), "N1" => nfet(:Wn)),
                 "static CMOS inverter"),
    :nand2 => Cell("nand2", NAND2_ART, ["a", "b", "out"], ["Wp" => 3e-6, "Wn" => 3e-6],
                   Dict("P1" => pfet(:Wp), "P2" => pfet(:Wp), "N1" => nfet(:Wn), "N2" => nfet(:Wn)),
                   "static CMOS two-input NAND gate"),
    :nand3 => Cell("nand3", NAND3_ART, ["a", "b", "c", "out"], ["Wp" => 3e-6, "Wn" => 4.5e-6],
                   Dict("P1" => pfet(:Wp), "P2" => pfet(:Wp), "P3" => pfet(:Wp),
                        "N1" => nfet(:Wn), "N2" => nfet(:Wn), "N3" => nfet(:Wn)),
                   "static CMOS three-input NAND gate"),
    :nor2 => Cell("nor2", NOR2_ART, ["a", "b", "out"], ["Wp" => 6e-6, "Wn" => 1.5e-6],
                  Dict("P1" => pfet(:Wp), "P2" => pfet(:Wp), "N1" => nfet(:Wn), "N2" => nfet(:Wn)),
                  "static CMOS two-input NOR gate"),
    :tg => Cell("tg", TG_ART, ["a", "b", "ng", "pg"], ["Wp" => 3e-6, "Wn" => 1.5e-6],
                Dict("P1" => pfet(:Wp), "N1" => nfet(:Wn)),
                "CMOS transmission gate (on when ng is high and pg low)"),
    :dlatch => Cell("dlatch", DLATCH_ART, ["d", "q", "en", "enn"], [], Dict{String,Any}(),
                    "dynamic D latch: transparent while en is high, holds while it is low"),
    :driver => Cell("driver", DRIVER_ART, ["d", "bl", "wr", "wrn", "pre", "pren", "vh"], [],
                    Dict{String,Any}("INV2" => (model="inv", Wp=12e-6, Wn=6e-6),
                                     "TG1" => (model="tg", Wp=24e-6, Wn=12e-6),
                                     "TG2" => (model="tg", Wp=12e-6, Wn=12e-6)),
                    "bit-line driver: writes d (wr high) or pre-charges to vh (pre high)"),
    :cell => Cell("dramcell", CELL_ART, ["bl", "wl"], ["Cd" => 30e-15],
                  Dict("N1" => nfet(1.2e-6), "CD" => :Cd),
                  "one-transistor DRAM cell; its storage node is sn"),
    :senseamp => Cell("senseamp", SENSEAMP_ART, ["bl", "y", "dout"],
                      ["Rref" => 30e3, "Wpi" => 3e-6],
                      Dict("R1" => 1e3, "R2" => 1e3, "Rref" => :Rref,
                           "N1" => nfet(24e-6; L=1e-6), "N2" => nfet(48e-6; L=1e-6),
                           "N3" => nfet(24e-6; L=2e-6), "N4" => nfet(24e-6; L=2e-6),
                           "P5" => pfet(6.7e-6; L=3e-6), "P6" => pfet(6.7e-6; L=3e-6),
                           "INV1" => (model="inv", Wp=:Wpi)),
                      "OTA sense amplifier with an inverter output stage"),
)

"""
    cell_schematic(name; kw...) -> Schematic

The drawing of cell `name` (`:inv`, `:nand2`, `:nand3`, `:nor2`, `:tg`, `:dlatch`,
`:driver`, `:cell`, `:senseamp`). Keywords go to `ascii_schematic`.
"""
cell_schematic(name::Symbol; kw...) = ascii_schematic(CELLS[name].art; kw...)

"""
    subckt(name; kw...) -> String

The SPICE subcircuit of cell `name`, from its drawing. Keywords override parameter
defaults: `subckt(:inv; Wp=4e-6)`.
"""
function subckt(name::Symbol; kw...)
    c = CELLS[name]
    params = [k => get(kw, Symbol(k), v) for (k, v) in c.params]
    s = ascii_schematic(c.art)
    spice_subcircuit(s; name=c.name, terminals=c.terminals, params=params, elements=c.elements)
end

"All the subcircuits the DRAM uses, as SPICE text."
library() = join((subckt(n) for n in (:inv, :nand2, :nand3, :nor2, :tg, :dlatch, :driver,
                                       :cell, :senseamp)), "\n")
