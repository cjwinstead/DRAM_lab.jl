using DRAM_lab, Test, Unitful
using DRAM_lab: SchematicSVG

@testset "DRAM_lab" begin
    @testset "cells" begin
        for n in keys(CELLS)
            txt = subckt(n)
            @test startswith(txt, ".subckt $(CELLS[n].name) " * join(CELLS[n].terminals, " "))
            @test occursin(".ends", txt)
        end
        @test occursin("Wp=4.0e-6", subckt(:inv; Wp=4e-6))
        @test occursin("ami06N", library())
    end
    @testset "figures" begin
        for n in [collect(keys(DRAM_lab.FIGURES)); collect(keys(CELLS))]
            @test occursin("<svg", SchematicSVG.to_svg(figure(n)))
        end
        @test_throws ArgumentError figure(:nope)
    end
    @testset "decoder" begin
        @test count('*', DECODER_BLANK) == 4            # only the enable connections
        @test count('*', DECODER_KEY) == 12
        @test [r.high for r in decoder_test().table] == [[0], [1], [2], [3]]
        @test occursin(".subckt decoder a1 a1n a0 a0n en wl0 wl1 wl2 wl3", decoder_subckt(DECODER_KEY))
    end
    @testset "calibration" begin
        v1, v2 = inverter_sweep([2u"μm", 3u"μm"])
        @test 2u"V" < v1 < v2 < 3.2u"V"
        y1, y2 = ota_sweep([40u"kΩ", 80u"kΩ"])
        @test y1 < y2
    end
    @testset "sequence" begin
        q = sequence([Write(2, 0b1010), Read(2)])
        @test DRAM_lab.duration(q) == 200u"ns"
        @test maximum(last.(q.signals["a1"])) == 1 && maximum(last.(q.signals["a0"])) == 0
        @test maximum(last.(q.signals["pre"])) == 1
        @test_throws ArgumentError sequence([Write(4, 0)])
        @test_throws ArgumentError sequence([Write(0, 16)])
    end
    @testset "memory" begin
        r = simulate_dram(; Wp=2.35u"μm", Rref=70u"kΩ",
                          ops=[Write(1, 0b0110), Write(2, 0b1001), Read(1), Read(2)])
        @test all(x -> x.ok, read_results(r))
        b = bumps(r)
        @test all(x -> (x.stored == 1) == (x.bump > 0), b)
        p = predicted_bumps(CBL=1u"pF", Cd=30u"fF", Vth=1.7u"V")
        @test p.zero ≈ -72.8u"mV" atol = 0.1u"mV"
        @test occursin("XC00 bl0 wl0 dramcell", dram_netlist(; Wp=2.35u"μm", Rref=70u"kΩ"))
    end
end
