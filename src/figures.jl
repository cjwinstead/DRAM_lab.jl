# ───────────────────────── reading figures ─────────────────────────
#
# Drawings for the reading part of the notebook. The cells (inverter, NAND, NOR, TG,
# D latch, driver, DRAM cell, sense amplifier) are in cells.jl; these are figures only.
# The clock generator is also simulated (nonoverlap_clocks).

const PULLUP_ART = """
           vdd
            |
     vg---|N1
            |
            *--@vs
            |
            C1
            |
           gnd
"""

const TG_SYMBOL_ART = """
       pg
       |
  a----TG1----b
       |
       ng
"""

const MUX2T_ART = """
            in
            |
      +-----*-----+
      |           |
s---|N1           P1|---s
      |           |
     out1        out0
"""

const TGMUX_ART = """
            sn
            |
      +-----TG1-----out1
      |     |
in----+     s
      |
      |     s
      |     |
      +-----TG2-----out0
            |
            sn
"""

const DYNAMIC_AND_ART = """
              vdd
               |
       clk1---|P1
               |
               *--@qn---INV1---q
               |
       a-----|N1
               |
       b-----|N2
               |
       clk2---|N3
               |
              gnd
"""

const DFF_ART = """
d-------[d    X1/dlatch    q]---------[d    X2/dlatch    q]---q
        [                   ]         [                   ]
clk1----[en                 ]  clk2---[en                 ]
        [                   ]         [                   ]
nclk1---[enn                ]  nclk2--[enn                ]
"""

const TFF_ART = """
       +--------------------------------+
       |                                |
t------XOR1---[d    X1/DFF    q]--------*---q
"""

const COMPARATOR_ART = """
                                  nclk2
                                  |
                         +--------TG2--------+
                         |        |          |
         nclk2           |        clk2       |
         |               |                   |
bl-------TG3-------------*------INV1---------*---q
         |               | @f1               |
         clk2            |                   |
                  nclk1  |                   |
                  |      |                   |
     +---INV2-----TG1----+                   |
     |            |                          |
     |            clk1                       |
     |                                       |
     +---------------------------------------+
"""

const CLKGEN_ART = """
ref---*-----NOR1---INV1---R1---*---INV3---*---clk2
      |     |                  |          |
      |     |                  C1         |
      |     |                  |          |
      |     |                 gnd         |
      |     |   +-------------------------+
      |     |   |
      |     +---)------------------------------------+
      |         |                                    |
      +--INV0---NOR2---INV2---R2---*---INV4----------*---clk1
                                   |
                                   C2
                                   |
                                  gnd
"""

const COUNTER_ART = """
vdd---[t  X0/TFF  q]----*-------------------------------------------------------------------q0
                        |
                        |
                        *-----------------------[t  X1/TFF  q]---*--------------------------q1
                        |                                        |
                        AND1----+                                |
                        |       |                                |
                        +-------)--------------------------------+
                                |
                                *---------------[t  X2/TFF  q]---*--------------------------q2
                                |                                |
                                AND2----+                        |
                                |       |                        |
                                +-------)------------------------+
                                        |
                                        +-------[t  X3/TFF  q]------------------------------q3
"""

const ORGANIZATION_ART = """

     [                     ]               |                 |                 |                 |
a1---[a1                wl0]-*-------------)---*-------------)---*-------------)---*-------------)----
     [                     ] |             |   |             |   |             |   |             |
     [                     ] +--[C00]------*   +--[C01]------*   +--[C02]------*   +--[C03]------*
     [                     ]               |                 |                 |                 |
a0---[a0                wl1]-*-------------)---*-------------)---*-------------)---*-------------)----
     [                     ] |             |   |             |   |             |   |             |
     [    X1/decoder       ] +--[C10]------*   +--[C11]------*   +--[C12]------*   +--[C13]------*
     [                     ]               |                 |                 |                 |
en---[en                wl2]-*-------------)---*-------------)---*-------------)---*-------------)----
     [                     ] |             |   |             |   |             |   |             |
     [                     ] +--[C20]------*   +--[C21]------*   +--[C22]------*   +--[C23]------*
     [                     ]               |                 |                 |                 |
     [                  wl3]-*-------------)---*-------------)---*-------------)---*-------------)----
     [                     ] |             |   |             |   |             |   |             |
                             +--[C30]------*   +--[C31]------*   +--[C32]------*   +--[C33]------*
                                           |                 |                 |                 |
                                           bl0               bl1               bl2               bl3
"""

const FIGURES = Dict{Symbol,Any}(
    :pullup => PULLUP_ART, :tg_symbol => TG_SYMBOL_ART, :mux2t => MUX2T_ART,
    :tgmux => TGMUX_ART, :dynamic_and => DYNAMIC_AND_ART, :dff => DFF_ART, :tff => TFF_ART,
    :counter => COUNTER_ART, :clkgen => CLKGEN_ART, :comparator => COMPARATOR_ART,
    :organization => ORGANIZATION_ART, :nand_decoder => DECODER_KEY,
    :nor_decoder => NOR_DECODER,
)

"""
    figure(name; kw...) -> Schematic

A drawing for the reading: `:pullup`, `:tg_symbol`, `:mux2t`, `:tgmux`, `:dynamic_and`,
`:dff`, `:tff`, `:counter`, `:clkgen`, `:comparator`, `:organization`, `:nand_decoder`,
`:nor_decoder`, or any cell name (`:inv`, `:nand2`, `:nor2`, `:tg`, `:dlatch`, `:driver`,
`:cell`, `:senseamp`). Keywords go to `ascii_schematic`.
"""
function figure(name::Symbol; kw...)
    haskey(CELLS, name) && return cell_schematic(name; kw...)
    haskey(FIGURES, name) || throw(ArgumentError("no figure $name; try one of " *
                                    join(sort([collect(keys(FIGURES)); collect(keys(CELLS))]), ", ")))
    Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do   # figures need no netlist checks
        ascii_schematic(FIGURES[name]; kw...)
    end
end

"""
    nonoverlap_clocks(; period=100u"ns") -> (t, ref, clk1, clk2)

Simulate the clock generator (the `:clkgen` figure, built from NOR gates, inverters and
RC delays) driven by a square wave `ref`. Times in s, voltages in V.
"""
function nonoverlap_clocks(; period=100u"ns", R=1u"kΩ", C=1u"pF")
    s = figure(:clkgen; elements=Dict("R1" => R, "R2" => R, "C1" => C, "C2" => C))
    sub = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
        spice_subcircuit(s; name="clkgen", terminals=["ref", "clk1", "clk2"])
    end
    T = ustrip(u"ns", period)
    ref = pwl_string([(t * u"ns", v * u"V") for (t, v) in
                      [(0.0, 0.0); vcat([[(k * T / 2 + 0.5, VDD * (k % 2 == 0)), ((k + 1) * T / 2, VDD * (k % 2 == 0))]
                                         for k in 0:5]...)]])
    net = bench("VREF ref 0 $ref\nXCG ref clk1 clk2 clkgen"; title="clock generator", extra=sub)
    quiet() do
        load_netlist(net)
        simulate(:tran; tstep=0.05u"ns", tmax=3period)
    end
    g(n) = NgHerb.getrealvec(n)
    (t=g("time"), ref=g("ref"), clk1=g("clk1"), clk2=g("clk2"))
end
