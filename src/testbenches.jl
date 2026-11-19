# ───────────────────────── testbenches for the exercises ─────────────────────────

# A netlist around one block: the model library, vdd, the subcircuits and `body`.
function bench(body::AbstractString; title="bench", extra="")
    io = IOBuffer()
    println(io, "* ", title)
    println(io, ".include ", model_library())
    println(io, ".global vdd")
    println(io, "VDD vdd 0 DC ", qstr(VDD * u"V"))
    println(io, library())
    isempty(extra) || println(io, extra)
    println(io, body)
    println(io, ".end")
    String(take!(io))
end

"""
    inverter_vtc(; Wp=3u"μm", Wn=1.5u"μm", step=5u"mV") -> (vin, vout)

The inverter's DC transfer curve (V) for PMOS width `Wp` and NMOS width `Wn`.
"""
function inverter_vtc(; Wp=3u"μm", Wn=1.5u"μm", step=5u"mV")
    net = bench("VIN in 0 DC 0\nX1 in out inv Wp=$(qstr(Wp)) Wn=$(qstr(Wn))"; title="inverter VTC")
    quiet() do
        load_netlist(net)
        simulate(:dc; device="VIN", start=0u"V", stop=VDD * u"V", step)
    end
    NgHerb.getrealvec("in"), NgHerb.getrealvec("out")
end

"""
    crossover(; Wp, Wn=1.5u"μm") -> V

The inverter's crossover voltage: the input voltage at which the output equals VDD/2.
"""
function crossover(; Wp, Wn=1.5u"μm")
    vin, vout = inverter_vtc(; Wp, Wn, step=1u"mV")
    k = findfirst(<(VDD / 2), vout)
    k === nothing && return NaN * u"V"
    f = (vout[k-1] - VDD / 2) / (vout[k-1] - vout[k])
    (vin[k-1] + f * (vin[k] - vin[k-1])) * u"V"
end

"""
    inverter_sweep(Wps; Wn=1.5u"μm") -> Vector of crossover voltages

The inverter crossover voltage for each PMOS width in `Wps` (as in a Cadence parametric
sweep).
"""
inverter_sweep(Wps; Wn=1.5u"μm") = [crossover(; Wp, Wn) for Wp in Wps]

"""
    ota_output(; Rref, vbl=VDD/2) -> V

The sense amplifier's OTA output (node y) with the bit line held at `vbl`: with
`vbl = VDD/2` this is the output offset, which should equal the inverter crossover.
"""
function ota_output(; Rref, vbl=VDD / 2 * u"V")
    net = bench("VBL bl 0 DC $(qstr(vbl))\nX1 bl y dout senseamp Rref=$(qstr(Rref))"; title="OTA offset")
    quiet() do
        load_netlist(net)
        simulate(:op)
    end
    only(NgHerb.getrealvec("y")) * u"V"
end

"""
    ota_sweep(Rrefs) -> Vector of output voltages

The OTA output offset (node y with the bit line at VDD/2) for each `Rref`.
"""
ota_sweep(Rrefs) = [ota_output(; Rref) for Rref in Rrefs]

"""
    ota_transfer(; Rref, Wp=3u"μm", span=100u"mV", step=0.2u"mV") -> (vbl, vy, vdout)

The sense amplifier's response to a bit-line voltage swept across `VDD/2 ± span`: the
OTA output `y` and the inverter output `dout` (all in V).
"""
function ota_transfer(; Rref, Wp=3u"μm", span=100u"mV", step=0.2u"mV")
    net = bench("VBL bl 0 DC 0\nX1 bl y dout senseamp Rref=$(qstr(Rref)) Wpi=$(qstr(Wp))";
                title="sense amplifier transfer")
    quiet() do
        load_netlist(net)
        simulate(:dc; device="VBL", start=VDD / 2 * u"V" - span, stop=VDD / 2 * u"V" + span, step)
    end
    NgHerb.getrealvec("bl"), NgHerb.getrealvec("y"), NgHerb.getrealvec("dout")
end

"""
    decoder_test(art=DECODER_KEY; period=40u"ns") -> NamedTuple

Simulate a decoder drawing as the address counts 0, 1, 2, 3 with en pulsing high once per
address. Returns `t` (s), the word lines `wl` (a vector of four vectors, V), the address
`a1`, `a0` and `en`, and `table`: for each address, the word lines that went high.
"""
function decoder_test(art::AbstractString=DECODER_KEY; period=40u"ns")
    T = ustrip(u"ns", period)
    pts(f) = pwl_string([(t * u"ns", v * u"V") for (t, v) in f])
    bit(b) = vcat([[(k * T + (k > 0 ? 0.5 : 0.0), VDD * ((k >> b) & 1)),
                    ((k + 1) * T, VDD * ((k >> b) & 1))] for k in 0:3]...)
    en = vcat([[(k * T + 0.25T, 0.0), (k * T + 0.25T + 0.5, VDD), (k * T + 0.75T, VDD),
                (k * T + 0.75T + 0.5, 0.0)] for k in 0:3]...)
    inv(p) = [(t, VDD - v) for (t, v) in p]
    body = """
    VA1 a1 0 $(pts(bit(1)))
    VA1N a1n 0 $(pts(inv(bit(1))))
    VA0 a0 0 $(pts(bit(0)))
    VA0N a0n 0 $(pts(inv(bit(0))))
    VEN en 0 $(pts([(0.0, 0.0); en]))
    XDEC a1 a1n a0 a0n en wl0 wl1 wl2 wl3 decoder
    """
    net = bench(body; title="address decoder", extra=decoder_subckt(art))
    quiet() do
        load_netlist(net)
        simulate(:tran; tstep=0.1u"ns", tmax=4period)
    end
    t = NgHerb.getrealvec("time")
    wl = [NgHerb.getrealvec("wl$i") for i in 0:3]
    table = map(0:3) do k
        tk = (k + 0.6) * T * 1e-9
        i = searchsortedfirst(t, tk)
        (address=k, high=[w for w in 0:3 if wl[w+1][i] > VDD / 2])
    end
    (; t, wl, a1=NgHerb.getrealvec("a1"), a0=NgHerb.getrealvec("a0"),
       en=NgHerb.getrealvec("en"), table)
end
