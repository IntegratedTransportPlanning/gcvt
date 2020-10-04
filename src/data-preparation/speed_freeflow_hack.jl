using CSV
using Glob

function main()
    for file in glob("../../data/sensitive/GCVT_Scenario_Pack/scenarios/*/links/*.csv")
        t = CSV.read(file)
        t.Speed_Cong_Road[t.LType .!= "Road"]
        mask = t.Speed_Cong_Road .== 0
        t.Speed = t.Speed_Cong_Road
        t.Speed[mask] = t.Speed_Freeflow[mask]
        CSV.write(file, t)
    end
end

main()
