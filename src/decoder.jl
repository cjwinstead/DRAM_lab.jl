# ───────────────────────── the address decoder ─────────────────────────
#
# A static NAND crossbar: each word line is the output of a three-input NAND gate (one
# address line for each bit, plus en) and an inverter. In the drawing, '*' connects an
# address line to a gate input row and ')' crosses it without connecting, so the decoder
# is programmed by editing characters.

# Rows of the crossbar: for word line k, the line taken for bit 1 and for bit 0.
const DECODER_LINES = ("a1", "a1n", "a0", "a0n")

# The drawing for a given choice of address lines, one (bit-1 line, bit-0 line) pair per
# word line (`nothing` leaves the row unconnected).
function decoder_art(choice; gate="NAND", inverter=true, enable="en")
    cols = Dict(l => 4 + 5 * (i - 1) for (i, l) in enumerate(DECODER_LINES))   # columns of the lines
    ecol = 24                                                                   # en
    gcol = 30                                                                   # gate inputs
    width = gcol - 1
    blank() = fill(' ', width)
    function vert!(row)
        for c in values(cols)
            row[c] = '|'
        end
        row[ecol] = '|'
        row
    end
    io = IOBuffer()
    hdr = blank()
    for (l, c) in cols
        hdr[c:c+length(l)-1] .= collect(l)
    end
    hdr[ecol:ecol+length(enable)-1] .= collect(enable)
    println(io, rstrip(String(hdr)))
    println(io, rstrip(String(vert!(blank()))))
    for k in 0:3
        sel = choice[k+1]
        # the input row from above: the bit-1 line
        r1 = vert!(blank())
        for c in values(cols)
            r1[c] = ')'
        end
        r1[ecol] = ')'
        for c in 1:width
            r1[c] == ' ' && c > cols["a1"] && (r1[c] = '-')
        end
        sel === nothing || (r1[cols[sel[1]]] = '*')
        println(io, String(r1), "+")
        println(io, String(vert!(blank())), "|")
        # the input row from the left: the bit-0 line
        r2 = vert!(blank())
        for c in values(cols)
            r2[c] = ')'
        end
        r2[ecol] = ')'
        for c in 1:width
            r2[c] == ' ' && c > cols["a1"] && (r2[c] = '-')
        end
        sel === nothing || (r2[cols[sel[2]]] = '*')
        println(io, String(r2), inverter ? "$gate$k---INV$k---wl$k" : "$gate$k---wl$k")
        # the input from below: en
        r3 = vert!(blank())
        for c in ecol+1:width
            r3[c] = '-'
        end
        r3[ecol] = '*'
        println(io, String(r3), "+")
        k < 3 && println(io, rstrip(String(vert!(blank()))))
    end
    String(take!(io))
end

"""
    DECODER_BLANK

The address decoder with no address lines connected: every crossing is `)`. Change the
crossings that should connect to `*`.
"""
const DECODER_BLANK = decoder_art(fill(nothing, 4))

# The working decoder: word line k is selected by address k (a1 a0 = k in binary).
const DECODER_KEY = decoder_art([("a1n", "a0n"), ("a1n", "a0"), ("a1", "a0n"), ("a1", "a0")])

# For the reading: a NOR crossbar. A NOR output is high only when all its inputs are low,
# so word line k takes the complements of the lines the NAND decoder uses, and the
# active-low enable enn.
const NOR_DECODER = decoder_art([("a1", "a0"), ("a1", "a0n"), ("a1n", "a0"), ("a1n", "a0n")];
                                gate="NOR", inverter=false, enable="enn")

const DECODER_TERMINALS = ["a1", "a1n", "a0", "a0n", "en", "wl0", "wl1", "wl2", "wl3"]

"""
    decoder_schematic(art=DECODER_KEY; kw...) -> Schematic

The drawing of a decoder (by default the working one).
"""
decoder_schematic(art::AbstractString=DECODER_KEY; kw...) = ascii_schematic(art; kw...)

"""
    decoder_subckt(art) -> String

The SPICE subcircuit `decoder a1 a1n a0 a0n en wl0 wl1 wl2 wl3` for a decoder drawing.
"""
function decoder_subckt(art::AbstractString)
    s = ascii_schematic(art)
    # an unconnected address line or gate input is the student's to fix, not a warning
    Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
        spice_subcircuit(s; name="decoder", terminals=DECODER_TERMINALS)
    end
end
