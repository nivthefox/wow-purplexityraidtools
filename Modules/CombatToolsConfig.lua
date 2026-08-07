local PRT = PurplexityRaidTools

PRT:RegisterTab("Combat Tools", function(parent)
    return PRT.Components.GetSubTabGroup(parent, {
        { name = "Cooldowns", setup = PRT.CooldownRoster.SetupConfig },
        { name = "Battle Res", setup = PRT.BattleResCounter.SetupConfig },
        { name = "Timer", setup = PRT.CombatTimer.SetupConfig },
    })
end)
