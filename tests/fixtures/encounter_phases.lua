return {
    phases = {
        { id = 1, name = "Opening" },
        { id = 2, name = "Intermission" },
        { id = 3, name = "Finale" },
    },
    observations = {
        { event = "NOISE", phase = nil },
        { event = "PHASE_TWO", phase = 2 },
        { event = "PHASE_TWO", phase = 2 },
        { event = "PHASE_ONE", phase = 1 },
        { event = "PHASE_THREE", phase = 3 },
    },
}
