# ───────────────────────── plots ─────────────────────────

const COLORS = ["#2a78d6", "#eb6834", "#1a9e77", "#9b59b6"]      # one per bit / word line

# An empty plot. (Microelectronics adds a keyword-only `plot` method of its own, so
# `emptyplot(; kw...)` doesn't give an empty plot when it is loaded.)
emptyplot(; kw...) = Plots.plot([NaN], [NaN]; label="", kw...)

# Shade the READ operations and name every operation along the top panel.
function mark_ops!(p, q::Sequence; label=true)
    T = ustrip(u"ns", q.timing.period)
    for (k, op) in enumerate(q.ops)
        t0 = (k - 1) * T
        op isa Read && Plots.vspan!(p, [t0, t0 + T]; color="#eeeeee", alpha=0.6, label="", linewidth=0)
        label && Plots.annotate!(p, t0 + T / 2, Plots.ylims(p)[2], Plots.text(string(op), 7, :bottom, "#333333"))
    end
    p
end

"""
    plot_dram(r::DRAMResult; bits=0:3, zoom=false) -> plot

Waveforms of a DRAM run, one panel each: the word lines, the data inputs, the bit lines,
the sense-amplifier latch outputs and the storage nodes of the cells in column(s) `bits`.
READ operations are shaded. With `zoom=true` the bit-line panel spans VDD/2 ± 150 mV so
the bumps show.
"""
function plot_dram(r::DRAMResult; bits=0:3, zoom::Bool=false, size=(900, 900))
    t = r.t .* 1e9
    q = r.sequence
    panel(ylabel) = emptyplot(; ylabel, legend=:outerright, framestyle=:box, grid=true,
                                 gridalpha=0.15, titlefontsize=10, ylims=(-0.3, 5.5))
    pw = panel("word lines (V)")
    for i in 0:3
        Plots.plot!(pw, t, r.v["wl$i"]; label="WL$i", color=COLORS[i+1], lw=1.5)
    end
    mark_ops!(pw, q)
    pd = panel("data in (V)")
    pb = panel("bit lines (V)")
    ps = panel("sensed (V)")
    pc = panel("cells (V)")
    for j in bits
        Plots.plot!(pd, t, r.v["d$j"] .+ 0.08j; label="D$j", color=COLORS[j+1], lw=1.5)
        Plots.plot!(pb, t, r.v["bl$j"]; label="BL$j", color=COLORS[j+1], lw=1.5)
        Plots.plot!(ps, t, r.v["s$j"] .+ 0.08j; label="S$j", color=COLORS[j+1], lw=1.5)
        for i in 0:3
            Plots.plot!(pc, t, r.v["xc$i$j.sn"]; label=i == 0 ? "bit $j" : "", color=COLORS[j+1],
                        lw=1, alpha=0.4 + 0.15i)
        end
    end
    zoom && Plots.ylims!(pb, VDD / 2 - 0.15, VDD / 2 + 0.15)
    foreach(p -> mark_ops!(p, q; label=false), (pd, pb, ps, pc))
    Plots.xlabel!(pc, "time (ns)")
    Plots.plot(pw, pd, pb, ps, pc; layout=(5, 1), size, link=:x, left_margin=5Plots.mm)
end

"""
    plot_read(r::DRAMResult, k; bits=0:3) -> plot

A close-up of the `k`-th READ: the word line, the bit lines around VDD/2 (with the
measured bumps marked when the latch closes) and the latch outputs.
"""
function plot_read(r::DRAMResult, k::Integer; bits=0:3, size=(900, 600))
    q = r.sequence
    reads = findall(op -> op isa Read, q.ops)
    n = reads[k]
    T = ustrip(u"ns", q.timing.period)
    t0 = (n - 1) * T
    keep = findall(x -> t0 <= x * 1e9 <= t0 + T, r.t)
    t = r.t[keep] .* 1e9
    addr = q.ops[n].addr
    pw = Plots.plot(t, r.v["wl$addr"][keep]; label="WL$addr", color="#333333", lw=1.5,
                    ylabel="V", legend=:outerright, framestyle=:box, title="Read($addr)",
                    titlefontsize=10)
    Plots.plot!(pw, t, r.v["pre"][keep]; label="pre", color="#999999", lw=1, ls=:dash)
    Plots.plot!(pw, t, r.v["sense"][keep]; label="sense", color="#b0b0b0", lw=1, ls=:dot)
    pb = emptyplot(; ylabel="bit lines (V)", legend=:outerright, framestyle=:box,
                    ylims=(VDD / 2 - 0.12, VDD / 2 + 0.12))
    ts = ustrip(u"ns", sense_times(q)[k] - 3q.timing.edge)
    for j in bits
        Plots.plot!(pb, t, r.v["bl$j"][keep]; label="BL$j", color=COLORS[j+1], lw=1.5)
        Plots.scatter!(pb, [ts], [at(r, "bl$j", ts * u"ns")]; label="", color=COLORS[j+1], ms=4)
    end
    Plots.hline!(pb, [VDD / 2]; label="VDD/2", color="#666666", ls=:dash)
    ps = emptyplot(; ylabel="sensed (V)", legend=:outerright, framestyle=:box, xlabel="time (ns)")
    for j in bits
        Plots.plot!(ps, t, r.v["s$j"][keep] .+ 0.08j; label="S$j", color=COLORS[j+1], lw=1.5)
    end
    Plots.plot(pw, pb, ps; layout=(3, 1), size, link=:x, left_margin=5Plots.mm)
end

"""
    plot_sequence(ops=DEFAULT_OPS; timing=Timing()) -> plot

The ideal control waveforms for a list of operations.
"""
function plot_sequence(ops=DEFAULT_OPS; timing::Timing=Timing(), size=(900, 420))
    q = sequence(ops; timing)
    names = ["a1", "a0", "en", "wr", "pre", "sense", "d0", "d1", "d2", "d3"]
    p = emptyplot(; yticks=(-(1:length(names)) .* 1.5, names), legend=false, framestyle=:box,
                   xlabel="time (ns)", size, grid=false)
    for (k, s) in enumerate(names)
        pts = q.signals[s]
        x = [ustrip(u"ns", t) for (t, _) in pts]
        y = [-1.5k + v for (_, v) in pts]
        push!(x, ustrip(u"ns", duration(q))); push!(y, last(y))
        Plots.plot!(p, x, y; color=k <= 6 ? "#333333" : COLORS[k-6], lw=1.5)
    end
    mark_ops!(p, q)
end

"""
    plot_clocks(c=nonoverlap_clocks()) -> plot

The reference clock and the two non-overlapping clock phases, stacked.
"""
function plot_clocks(c=nonoverlap_clocks(); size=(900, 380))
    t = c.t .* 1e9
    p = emptyplot(; xlabel="time (ns)", yticks=([2.5, 8.5, 14.5], ["clk2", "clk1", "ref"]),
                  legend=false, framestyle=:box, size, grid=false)
    Plots.plot!(p, t, c.ref .+ 12; color="#333333", lw=1.5)
    Plots.plot!(p, t, c.clk1 .+ 6; color=COLORS[1], lw=1.5)
    Plots.plot!(p, t, c.clk2; color=COLORS[2], lw=1.5)
    p
end

"""
    png_plots()

Make Jupyter show Plots (GR) figures as PNG images only. By default each plot is stored
in the notebook three times (SVG, PNG and HTML), and a transient simulation's SVG can be
megabytes, so this keeps notebooks small.
"""
function png_plots()
    @eval Base.showable(::MIME"image/svg+xml", ::Plots.Plot{Plots.GRBackend}) = false
    @eval Base.showable(::MIME"text/html", ::Plots.Plot{Plots.GRBackend}) = false
    nothing
end
