# ───────────────────────── the 4×4 DRAM and its control ─────────────────────────

const VDD = 5.0

"A memory operation: write `data` (a 4-bit word, bit j to column j) to word `addr`."
struct Write
    addr::Int
    data::Int
end
"A memory operation: read word `addr`."
struct Read
    addr::Int
end
const Operation = Union{Write,Read}

Base.show(io::IO, w::Write) = print(io, "Write(", w.addr, ", 0b", string(w.data; base=2, pad=4), ")")
Base.show(io::IO, r::Read) = print(io, "Read(", r.addr, ")")

"""
    Timing(; period=100u"ns", edge=1u"ns", ...)

When each control signal changes within one operation, measured from the start of the
operation. A WRITE turns the bit-line drivers on (`wr_on`), raises the word line
(`wl_on`), lowers it (`wl_off`) and turns the drivers off (`wr_off`). A READ pre-charges
the bit lines to VDD/2 (`pre_on` to `pre_off`), raises the word line (`wl_on`), opens the
output latches while the bump settles (`sense_on` to `sense_off`) and lowers the word line
(`wl_off`). Address and data change at the start of each operation.
"""
Base.@kwdef struct Timing
    period::typeof(1.0u"ns") = 100u"ns"
    edge::typeof(1.0u"ns") = 1u"ns"
    wr_on::typeof(1.0u"ns") = 5u"ns"
    wr_off::typeof(1.0u"ns") = 90u"ns"
    pre_on::typeof(1.0u"ns") = 5u"ns"
    pre_off::typeof(1.0u"ns") = 35u"ns"
    wl_on::typeof(1.0u"ns") = 40u"ns"
    wl_off::typeof(1.0u"ns") = 80u"ns"
    sense_on::typeof(1.0u"ns") = 60u"ns"
    sense_off::typeof(1.0u"ns") = 70u"ns"
end

# Named control signals (each also gets an inverted copy where the circuit needs one).
const CONTROLS = ["a1", "a0", "en", "d0", "d1", "d2", "d3", "wr", "pre", "sense"]
const INVERTED = Dict("a1" => "a1n", "a0" => "a0n", "wr" => "wrn", "pre" => "pren",
                      "sense" => "sensen")

"""
    Sequence

The control waveforms for a list of operations: `ops`, the `timing`, and for each signal
name its piecewise-linear `(time, level)` points with levels 0 or 1.
"""
struct Sequence
    ops::Vector{Operation}
    timing::Timing
    signals::Dict{String,Vector{Tuple{typeof(1.0u"ns"),Int}}}
end

"""
    sequence(ops; timing=Timing()) -> Sequence

Ideal control waveforms for the operations `ops`, one `timing.period` each:
`sequence([Write(0, 0b1010), Read(0)])`.
"""
function sequence(ops::AbstractVector; timing::Timing=Timing())
    tm = timing
    levels = Dict(s => Tuple{typeof(1.0u"ns"),Int}[] for s in CONTROLS)
    # level of each signal over time: a list of (time, value) steps
    steps = Dict(s => Tuple{typeof(1.0u"ns"),Int}[(0.0u"ns", 0)] for s in CONTROLS)
    set!(s, t, v) = push!(steps[s], (t, v))
    for (k, op) in enumerate(ops)
        op isa Operation || throw(ArgumentError("not an operation: $op"))
        0 <= op.addr <= 3 || throw(ArgumentError("address $(op.addr) is not 0–3"))
        t0 = (k - 1) * tm.period
        set!("a1", t0, (op.addr >> 1) & 1)
        set!("a0", t0, op.addr & 1)
        if op isa Write
            0 <= op.data <= 15 || throw(ArgumentError("data $(op.data) is not a 4-bit word"))
            for j in 0:3
                set!("d$j", t0, (op.data >> j) & 1)
            end
            set!("wr", t0 + tm.wr_on, 1); set!("wr", t0 + tm.wr_off, 0)
        else
            set!("pre", t0 + tm.pre_on, 1); set!("pre", t0 + tm.pre_off, 0)
            set!("sense", t0 + tm.sense_on, 1); set!("sense", t0 + tm.sense_off, 0)
        end
        set!("en", t0 + tm.wl_on, 1); set!("en", t0 + tm.wl_off, 0)
    end
    # steps → PWL points with finite edges
    for s in CONTROLS
        pts = levels[s]
        v = 0
        push!(pts, (0.0u"ns", 0))
        for (t, x) in sort(steps[s]; by=first)
            x == v && continue
            t > 0u"ns" && push!(pts, (t, v))
            push!(pts, (t + tm.edge, x))
            v = x
        end
    end
    Sequence(collect(Operation, ops), tm, levels)
end

duration(q::Sequence) = length(q.ops) * q.timing.period

"Times (from the start) at which each read's latch closes: the read results are valid then."
sense_times(q::Sequence) = [(k - 1) * q.timing.period + q.timing.sense_off + 2q.timing.edge
                            for (k, op) in enumerate(q.ops) if op isa Read]

"""
    DEFAULT_OPS

Four writes and then four reads, so every word is read back after all of them have been
written.
"""
const DEFAULT_OPS = Operation[Write(0, 0b0101), Write(1, 0b0011), Write(2, 0b1110), Write(3, 0b1001),
                              Read(0), Read(1), Read(2), Read(3)]

pwl(points) = pwl_string([(t, v * VDD * u"V") for (t, v) in points])

"""
    dram_netlist(; Wp, Rref, decoder=DECODER_KEY, ops=DEFAULT_OPS, CBL=1u"pF", Cd=30u"fF",
                 timing=Timing()) -> String

The SPICE netlist of the 4×4 DRAM with its control sequence: the address decoder drawn
in `decoder`, four bit-line drivers, the 16 cells (storage capacitance `Cd`), a
capacitance `CBL` on each bit line (the load of the many cells a real bit line has), and
four sense amplifiers (reference resistor `Rref`, output inverter PMOS width `Wp`: the
values found in the calibration exercises), each followed by a D latch that holds the
result of the last read.

Nodes: `a1 a0 en wl0…wl3 d0…d3 bl0…bl3 s0…s3` and the cells' storage nodes `xc<word><bit>.sn`.
"""
function dram_netlist(; decoder::AbstractString=DECODER_KEY, ops=DEFAULT_OPS, CBL=1u"pF",
                      Cd=30u"fF", Wp, Rref, timing::Timing=Timing())
    q = sequence(ops; timing)
    io = IOBuffer()
    println(io, "* 4x4 DRAM: ", join(string.(q.ops), ", "))
    println(io, ".include ", model_library())
    println(io, ".global vdd")
    println(io, "VDD vdd 0 DC ", qstr(VDD * u"V"))
    println(io, "VH vh 0 DC ", qstr(VDD / 2 * u"V"))
    println(io)
    println(io, library())
    println(io, decoder_subckt(decoder))
    println(io, "* control")
    for s in CONTROLS
        println(io, "V", uppercase(s), " ", s, " 0 ", pwl(q.signals[s]))
        if haskey(INVERTED, s)
            n = INVERTED[s]
            println(io, "V", uppercase(n), " ", n, " 0 ", pwl([(t, 1 - v) for (t, v) in q.signals[s]]))
        end
    end
    println(io, "* array")
    println(io, "XDEC a1 a1n a0 a0n en wl0 wl1 wl2 wl3 decoder")
    for j in 0:3
        println(io, "XDRV$j d$j bl$j wr wrn pre pren vh driver")
        println(io, "CBL$j bl$j 0 ", qstr(CBL))
        for i in 0:3
            println(io, "XC$i$j bl$j wl$i dramcell Cd=", qstr(Cd))
        end
        println(io, "XSA$j bl$j y$j so$j senseamp Rref=", qstr(Rref), " Wpi=", qstr(Wp))
        println(io, "XLAT$j so$j s$j sense sensen dlatch")
    end
    println(io, ".end")
    String(take!(io))
end

"""
    DRAMResult

A simulated run: `t` (s), the `sequence`, and voltage vectors by node name in `v`
(`v["bl0"]`, `v["wl2"]`, `v["s3"]`, `v["xc12.sn"]`, …), plus the parameters used.
"""
struct DRAMResult
    t::Vector{Float64}
    v::Dict{String,Vector{Float64}}
    sequence::Sequence
    params::NamedTuple
end

quiet(f) = redirect_stdout(f, devnull)

"""
    simulate_dram(; kw...) -> DRAMResult

Simulate the DRAM (see [`dram_netlist`](@ref) for the keywords) and collect the word
lines, data, bit lines, sense outputs and storage nodes.
"""
function simulate_dram(; decoder::AbstractString=DECODER_KEY, ops=DEFAULT_OPS, CBL=1u"pF",
                       Cd=30u"fF", Wp, Rref, timing::Timing=Timing(),
                       tstep=0.2u"ns")
    net = dram_netlist(; decoder, ops, CBL, Cd, Wp, Rref, timing)
    q = sequence(ops; timing)
    quiet() do
        load_netlist(net)
        simulate(:tran; tstep, tmax=duration(q))
    end
    getv(n) = NgHerb.getrealvec(n)
    names = [["a1", "a0", "en"]; ["wl$i" for i in 0:3]; ["d$j" for j in 0:3]; ["bl$j" for j in 0:3];
             ["y$j" for j in 0:3]; ["s$j" for j in 0:3]; ["xc$i$j.sn" for i in 0:3 for j in 0:3];
             ["wr", "pre", "sense"]]
    v = Dict(n => getv(n) for n in names)
    DRAMResult(getv("time"), v, q, (; CBL, Cd, Wp, Rref))
end

# Value of vector `y` at time `t` (s), linearly interpolated.
function at(r::DRAMResult, name::AbstractString, t)
    ts = ustrip(u"s", t)
    y = r.v[name]
    k = clamp(searchsortedlast(r.t, ts), 1, length(r.t) - 1)
    f = (ts - r.t[k]) / (r.t[k+1] - r.t[k])
    y[k] + f * (y[k+1] - y[k])
end

"""
    read_results(r::DRAMResult) -> Vector{NamedTuple}

For each READ: the address, the word written there last (or `nothing`), the word sensed
(from the latch outputs `s0…s3`) and whether they agree.
"""
function read_results(r::DRAMResult)
    q = r.sequence
    stored = Dict{Int,Int}()
    out = NamedTuple[]
    times = sense_times(q)
    k = 0
    for op in q.ops
        if op isa Write
            stored[op.addr] = op.data
        else
            k += 1
            t = times[k]
            word = sum((at(r, "s$j", t) > VDD / 2 ? 1 : 0) << j for j in 0:3)
            expect = get(stored, op.addr, nothing)
            push!(out, (addr=op.addr, written=expect, read=word, ok=expect == word))
        end
    end
    out
end

"""
    bumps(r::DRAMResult) -> Vector{NamedTuple}

The bump voltage `V_BL − VDD/2` on every bit line of every READ, measured just before the
latch closes, with the bit that was stored: `(addr, bit, stored, bump)` (bump in V).
"""
function bumps(r::DRAMResult)
    q = r.sequence
    stored = Dict{Int,Int}()
    out = NamedTuple[]
    k = 0
    times = sense_times(q)
    for op in q.ops
        if op isa Write
            stored[op.addr] = op.data
        else
            k += 1
            t = times[k] - 3q.timing.edge
            for j in 0:3
                b = haskey(stored, op.addr) ? (stored[op.addr] >> j) & 1 : missing
                push!(out, (addr=op.addr, bit=j, stored=b, bump=at(r, "bl$j", t) - VDD / 2))
            end
        end
    end
    out
end

"""
    predicted_bumps(; CBL, Cd, VDD=5u"V", Vth) -> (zero, one)

The bump voltages predicted by charge sharing: a cell holding 0 V, or `VDD − Vth`, is
connected to a bit line pre-charged to VDD/2.
"""
function predicted_bumps(; CBL, Cd, VDD=VDD * u"V", Vth)
    zero = -Cd * VDD / 2 / (CBL + Cd)
    one = (VDD / 2 - Vth) * Cd / (CBL + Cd)
    (zero=uconvert(u"mV", zero), one=uconvert(u"mV", one))
end
