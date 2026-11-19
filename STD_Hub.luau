--[[
    STD Hub  |  Sorcerer Tower Defense  |  UNIVERSAL
    ------------------------------------------------------------------
    Bypasses the level requirement of every manually castable ability
    (domain / ult / special) and auto-solves the Justice Sorcerer QTE.

    WHY IT WORKS
      The client only draws the ability button when a value inside the
      tower's Config says it is unlocked. That value is replicated from
      the server and only flips at the unlock level. Writing it locally
      and firing the remote is enough - the server never re-checks it.

      Verified live on a LEVEL 1 Justice Sorcerer:
          Config.DomainActive = false   (server value)
      the hub flipped it to true, fired
          Remotes.Towers.JusticeSorcerer.Domain:FireServer(tower)
      and the domain executed, the QTE ran, the gauge hit 22.20/22.
      Same test repeated on a LEVEL 1 Meguna and a LEVEL 1 Gojo Evo.

    TWO KINDS OF ABILITY BUTTONS
      a) CreateActive(Config, cdValue, icon, remote)
         -> generic: u76:FireServer(towerModel)
      b) written inline in the tower branch
         -> also exactly remote:FireServer(towerModel)
      Both send the tower Model as the only argument, so one code path
      covers all of them.

    FULL ABILITY MAP (extracted from GameController.lua)
    ------------------------------------------------------------------
    AttackType          Ability       Unlock  Gate value          Remote
    TojiEvo             Ult           L6/6    Ult                 Towers.TojiEvo.TojiUlt
    SukunaEvo (Meguna)  Domain        L7/8    DomainActive        Towers.KingOfCursesEvo.DomainActive
    GojoDisco           Domain        L6/6    DomainActive        Towers.GojoDisco.Domain
    GojoEvo             Domain        L6/6    DomainActive        GojoDomain
    Sukuna (base)       Domain        -       DomainActive        SukunaDomain
    MahitoAwk           Domain        -       DomainActive        MahitoDomain
    Hakari              Domain        -       DomainActive        Towers.Hakari.HakariDomain
    OvertimeAwk         Ult           -       Ult                 Towers.OvertimeAwk.Ult
    RedScarfSorcererAwk Rage          -       Rage                Towers.RedScarfSorcererAwk.Rage
    MechaSorcerer       Active        -       ActiveAmount == 3   MechaXmassActive
    RedScarf (Anniv)    Celebration   L6/6    Celebration         Towers.RedScarfSorcerer.Ability
    SukunaFrost         Domain        L6/6    DomainActive        Towers.KingOfCursesFrost.Domain
    LightningSorcerer   Beast Amber   L6/6    BeastAmber          Towers.Lightning.BeastAmber
    JusticeSorcerer     Domain        L6/6    DomainActive        Towers.JusticeSorcerer.Domain
    ProjectionSorcerer  Ultimate      L6/6    Ultimate            Towers.ProjectionSorcerer.Ultimate
    ExplosiveSorcerer   Kamikaze      L1/6    Kamikaze            Towers.ExplosiveSorcerer.Kamikaze

    Notes
      * Explosive Sorcerer already has Kamikaze at level 1 - nothing to bypass.
      * Hakari / Overtime / Red Scarf Awk are charge-gated (FeverMeter,
        OvertimeMeter, RageMeter). The gate value can be forced, but the
        server may still want a real charge, so those are marked CHARGE.
      * Gojo Evo keeps its cooldown on the PLAYER, not the tower
        (LocalPlayer.EvoGojoDomainRemCd), which is why the cd field can
        be written as "@player.<Name>".
      * Tower model names differ from AttackType
        (TojiEvo -> SorcererKillerEvo*, SukunaEvo -> KingOfCursesEvo*,
        GojoEvo -> StrongestSorcererEvo*). The hub matches on
        Config.AttackType.Value, never on the name.

    QTE (Justice Sorcerer only)
    ------------------------------------------------------------------
    LocalPlayer.QTE folder:
      MarkerPos / ZonePos / ZoneWidth / Speed / GoingRight / Points /
      InQTE / TimeLeft / Difficulty / Click (RemoteEvent) / Result

    Measured behaviour (not guesswork - logged live over several domains):
      * Click:FireServer(tick()) is the only thing the client sends. The hit
        test happens on the server, so no mouse input is involved at all.
      * one trial = one zone. a click ends the trial, the server spawns the
        next one within ~50ms, and a domain lasts ~14s -> 20-40 trials.
      * a hit is +1.0 and +0.1 per consecutive hit (caps around +3.2), a miss
        is -1.0 AND resets the streak, so a miss costs ~2 points.
      * Points is NOT reset by a new domain - it survives until the gauge hits
        22 (execution) or the domain times out empty.
      * Result never fires, so hit/miss is read from Points instead.
      * MarkerPos arrives at ~23 Hz, quantised to 0.01, and the speed changes
        every trial, so the rate is fitted per trial.

    The solver clicks when the marker is predicted to sit at the CENTRE of the
    zone one one-way latency from now, walks its lead after every miss, and
    spends a blind click on zones the pass never lines up with.

    v5 - measured again on the live client after the Anniversary update:
      * Click replies with a boolean on the same remote (true = hit). The old
        solver inferred hits from Points, which is ambiguous - a hit after a
        miss only reads as +0.0x. The reply is now the primary signal and
        Points is only the fallback for a silent server.
      * The predictive path alone sat at the edge of its own aim window and
        missed ~50% of the time: rate is fitted from two or three samples per
        trial and the speed changes every trial, so the predicted centre is
        simply not accurate enough. Clicking on the RAW reading - "the marker
        is inside the zone right now" - went from 53% to 80% hits and filled
        the gauge (26.00/22) inside a single domain.
      * The bar is hidden by InQTE.Changed -> Frame.Visible in the game's own
        LocalScript, so if that connection ever dies the bar never comes back.
        keepQTEvisible() re-shows the frame, re-enables the ScreenGui and
        re-parents it if it was destroyed.

    v6 - the aim was on the glow, not the button:
      * ZonePos is the CENTRE of the strip (verified against the rendered
        Zone.AbsolutePosition: 0.39 == centre of 0.24..0.54), so the target was
        never wrong. The firing RULE was: `|dArr| <= window` first becomes true
        at dArr = +window, i.e. at the leading edge of the zone - visually the
        glow. Every click landed there, and at high speed the boundary is
        outside by the time the click arrives, so nothing ever farmed.
      * Now the click fires when dArr crosses zero - the centre - with only a
        frame of overshoot allowed. The lead correction is proportional
        (dArr/rate) instead of a fixed crawl that sat at +0.05 forever.
      * A miss costs a point AND the streak, an unclicked trial costs nothing,
        so a shot is only taken when rate*Jitter fits inside the half-width.
        The blind click is aimed at the crossing too.
      * Measured on the live tower: 68% -> 93% hits, best streak 12, 19.5/22
        in one domain. What is left is the client stalling 2.4s without marker
        updates when the window is in the background, not the aim.

    v7 - the centre was too safe:
      * The strip is drawn as a solid bar with a bloom bleeding out of both
        sides (Zone.Glow is 1.25x the strip). The bloom is not part of the hit
        area - that is the original bug, clicking it scores as a miss.
      * Aiming dead centre dodges the bloom but throws away half the strip. The
        click only has to land inside the SOLID part, and the earliest point
        that is safely inside is just behind the leading edge. So the aim point
        is now a fraction of a half-width: 0 = centre, 1 = leading edge,
        seeded at 0.55 and carried between domains.
      * It also learns: a hit pushes it out toward the edge, a miss pulls it
        back toward the centre. (Superseded by v13, which aims at the edge and
        learns the LEAD instead - two learners on one hit/miss signal fight each
        other, and the edge is the more useful of the two to hold.)
      * The band is at least one frame wide (rate * 50ms) or the crossing gets
        skipped and the trial waits a full pass for nothing.

    v8 - the shot is measured before it is taken, not aimed by hand:
      * A click now goes out only when the predicted landing point PLUS ITS OWN
        ERROR BAR fits inside the strip. The error bar is three real things: the
        standard error of the fitted slope over the time it is extrapolated, the
        arrival slop the click cannot control (rate * Jitter), and the 0.005 the
        marker value is quantised to. A 20% rate error over a 70ms lead moves the
        landing point 20% of everything the marker covers in those 70ms, and that
        is what a fixed aim window could never see.
      * The aim point is a BIAS now, not the decision. It dropped 0.55 -> 0.30
        and its range is 0.08..0.55: it buys lateness, it does not pick the shot.
      * The rate fit is reset when the marker turns around. Samples either side of
        a bounce describe two different lines; fitting them together produced a
        slope that was wrong in both directions for the next six frames.
      * There is no last-ditch shot any more. Simulated over 4000 trials at three
        trial lengths (std_hub/qte_gate_sim.luau), firing at the deadline without
        the error bar drops accuracy to 80-94% and earns FEWER points than simply
        letting the trial go, because a missed trial is free and a missed click is
        -1 plus the streak. A trial that never lines up is a trial to let go of.
      * A stall guard replaces it: 12 trials in a row with no shot at all stops
        the domain and says so, because that means the fit is not converging
        rather than the gate being picky.
      * Simulated: 100% accuracy (0-2 misses in 4000) for 82-94% of the points the
        old gate earned in a model where the old gate is already 98% accurate. In
        the live game, where it is nowhere near that, the trade is much better.

    v9 - what the game's own client script actually does, and the hook that died:
      * PlayerGui.QTE.LocalScript (decompiled into
        %LOCALAPPDATA%\\Potassium\\workspace\\_decomp\\qte_LocalScript.luau) listens
        to UserInputService.InputBegan and does Click:FireServer(tick()) for
        EVERY MouseButton1 or Touch, with no check that the bar was clicked.
        So a click on this hub's panel is also a click on the trial.
      * A __namecall hook was tried to drop those. It installed cleanly and then
        took the whole client down - hooking __namecall in a live Roblox client
        is not survivable any more. Removed. Do not put it back.
      * Consequence: a click on the hub while a domain is running still reaches
        the server as a trial click. Practical rule - do not click the panel
        during a farm.
      * Same file: TimeLeft is in TENTHS of a second (the HUD prints TimeLeft/10
        .. "s"), and the gauge is Points/22 - TargetPts 22 is confirmed.
      * The lead clamp floor went 0.012 -> 0.0: if the server really judges the
        click at the tick() the client sends, the correct lead is zero and a hard
        floor of 12ms would sit above the truth for ever.

    v10 - "twice a second in the same spot and no progress":
      * That is not aim, it is a frozen marker. The bar stays up with MarkerPos
        standing still during the 3-2-1 countdown and in the gap after a domain
        ends. A click there is a click into nothing: the server answers, the
        trial does not advance, and half a second later the awaitTrial fallback
        re-arms and fires again at exactly the same dArr. Two a second, forever,
        zero points.
      * FrozenAfter: if MarkerPos has not changed for 250ms nothing is fired at
        all, whatever the gate says. The bar being visible is not the same thing
        as the trial being live.

    v12 - "it clicks again on the disappearing animation":
      * The second click went out on the click REPLY, not on the zone. The
        decompiled PlayerGui.QTE.LocalScript shows exactly what the reply does:
        Click.OnClientEvent clones Zone, tweens the CLONE to 2x size and
        fades it over 0.3s, and on a miss puffs a Mistake sprite at the marker.
        It never touches ZonePos, ZoneWidth or MarkerPos. So the values the hub
        reads are stable through the whole animation - and the hub listens to
        that same event to get its hit/miss answer, which means the animation
        starts on the exact frame the gate is told "judged" and re-opened.
      * So the guard is about TIME, not about the zone: MinClickGap (no second
        click within 550ms of the first, whatever the gate believes), and a
        trial only re-arms on a zone signature that has held still for
        ZoneSettle (120ms) AFTER the click was judged. StaleTrial is the only
        blind re-arm left, at 2.5s - longer than any trial, so it cannot fire
        inside the one it already clicked.
      * The old half-second re-arm is gone. Half a second is well inside a
        single trial, so that fallback produced exactly the double click it was
        written to prevent.

    v13 - "click the very edge, ignore the bloom, no delay":
      * The lead was never learning anything. Its correction was
        (dArr - target)/rate, and dArr is at target whenever the gate fires -
        that is what firing means - so the correction was always zero and the
        lead sat at its seed for entire domains. Measured live: `lead 0.000`
        every time.
      * Aiming at the edge is what makes the outcome informative. At the edge
        the marker has the whole strip still ahead of it, so a click that is
        early lands outside and misses while a late one still hits. A miss
        therefore means the lead is too long. 9:1 hit:miss steps (LeadUp
        +0.003, LeadDown -0.027) balances that at 90% and parks the lead on the
        latency the server actually judges at, whatever that is - zero if it
        uses the tick() the client sends.
      * Everything is now measured against the GREEN strip. ZoneWidth drives
        Zone.Size and the bloom is a Glow child drawn 1.25x it, hanging outside
        the rect - so ZoneWidth is already the green and aiming at its edge is
        aiming at the edge while ignoring the bloom. edge = 1.0 is that edge.
      * The gate grew a floor. `dArr <= target` has no lower bound, and dArr
        keeps falling after the marker leaves the strip, so the gate was still
        true long after the zone was behind the marker and fired on every frame
        of the way down. That is what "it clicks on the bar as it fades" was: a
        gate with no floor, not the animation. |dArr| <= hw now.
      * The network's spread was removed from the error bar. It is already paid
        for by the lead balance; leaving it in as well made the bar wider than
        the strip, so the gate could never reach the edge it was aiming at.
      * The aim is seeded at 0.95 of the solid strip and only walks inward if a
        24-click window comes in under 60% - which cannot be explained by lead
        at all and means the aim is outside the green.

    v14 - "83% is not 90%":
      * The accuracy controller was never running. Its window was 24 replies
        and a domain produces ~18 clicks, so it was blind for the entire
        session. What moved the bar instead was the no-shot decay: every trial
        that ended without a click cut it 4%, and a domain loses 10-14 of those
        to the gap floor and stale samples, not to the bar being too wide.
        0.96^14 = 0.55. Measured: a run that was 17% short on accuracy ended
        with its error bar at 11ms, having started at 18 - the feedback was
        backwards, which is why more domains never helped.
      * Replaced with AIMD on every judged click: a miss multiplies the bar by
        1.5, a hit eases it 1.5%. Equilibrium is
        ln(1/0.985)/ln(1.5) = 3.7% of clicks missed, reached in a couple of
        domains rather than never. The bar only eases on two consecutive lost
        trials, and then by 1%.
      * errBar is now understood for what it is: the gate fires at
        dArr = hw - errBar, so errBar is exactly the room between the landing
        point and the entry edge, and hit rate is P(error <= errBar). Widening
        it fires EARLIER - closer to the edge the user asked for - and safer at
        the same time. It is the only knob that improves both at once.
      * Clicks are refused on a marker sample older than 60ms. Gaps of 1.9s
        appear in the log, and extrapolating a 500ms-old position is a coin
        flip no error bar can cover.
      * The aim fault handler now judges the whole domain instead of a window
        that never completed, and will not walk the aim back out while the bar
        is still above its floor - "good rate" with a wide bar is not evidence
        the aim is safe.

    v15 - the lead was real, it just had the wrong sign, and nobody measured it:
      * The v14 margin test failed, and that was the useful result: a miss at
        margin 0.087 while hits survived at 0.041. If the error were a spread
        the error bar could cover, those two could not happen in the same run.
        So the spread was not the problem.
      * The marker trajectory was then recorded at frame rate and every click
        replayed against it, asking "at what delay does the marker leave the
        strip?". Answer, from four clicks bracketing it from both sides: the
        click is judged 100-150ms after it is sent. One miss needed 0.143 of
        travel to leave the strip and had been clicked with 0.039 of room to
        the entry edge; a hit with 0.126 of half-width survived 150ms and died
        at 200. Consistent, not random.
      * So the client's MarkerPos is ~120ms behind the marker the server
        judges, and a click aimed at the strip lands 120ms PAST it. That is why
        aiming at the entry edge worked at all (hw/rate is coincidentally about
        120ms) and why it capped at 83%: the click was landing at the FAR edge,
        one half-width of room, instead of at the centre, two.
      * The aim is now the judged position, not the drawn one: fire when
        dArr <= rate * lead, so the marker arrives at the centre. The lead is
        MEASURED - half the round trip on each reply, EMA'd - not a slider and
        not learned by attrition. A 120ms lead is not a "click lead" in the
        sense the user rejected; it is a correction for a delay that was
        measured, and it moves the click EARLIER, which is the direction the
        edge aim was always trying to go.
      * The error bar is out of the aim entirely. Its only job now is to say
        whether the extrapolated landing point is trustworthy enough to fire on
        at all (GuardFrac), because the extrapolation is now lead-long rather
        than one frame long and slope error scales with it.
      * Stale samples are refused outright (MaxAge), the aim is no longer
        restored from a previous session (one bad domain at 0.70 used to stick
        for a whole session), and the settings id changed so the remembered
        70% could not come back.

    Known server-side gotcha: if a domain ends without the gauge filling, the
    tower can stay at Config.IsCasting = true with DomainRemCd frozen, and the
    server then refuses every new cast until the tower or the match resets.
    The hub reports that instead of hammering the remote.

    ------------------------------------------------------------------
    V2 MODULES
    ------------------------------------------------------------------
    TABS
      ABILITIES  every placed ability tower, force-cast one or all, auto cast
      GAUNTLET   gauntlet / endless / challenge - one tab, one picker
      RAIDS      gojo / toji / meguna - one tab, one picker
      CASINO     hakari (the game calls the map Hakari, the tab says Casino)
      SUKUNA     sukuna
      STORY      chapters - stage + hell mode
      MACROS     auto skip/confirm, auto claim, skip now, start / exit now
      CONFIG     save / load the whole hub state, tower report

      every mode tab carries the same Automation column (auto start,
      auto start any mode, auto join, REC / REPLAY) - the switches are global,
      so flipping one flips the copies in the other tabs

    MODE ENTRY - how the lobby actually works
      Every mode lives on a physical elevator in the lobby
      (Workspace.<Mode>Teleporters.<Elevator>) and the panel only opens
      through TouchInterest on Elevator.Teleports.Entrance, so the hub
      walks the character onto that pad and fires the touch itself.

      Remotes, measured on the live client:
        Teleporters.ChooseStage:FireServer(elevator, stage, "Normal"|"Hellmode", friends)
        GauntletTeleporters.ChooseStage:FireServer(elevator, friends)
        <Mode>Teleporters.Start:FireServer(elevator)
        <Mode>Teleporters.HostLeave:FireServer(elevator)

      The server still gates the actual match on its own elevator cycle
      (UpdateTimer 60 -> 0), which the client cannot skip. So the hub also
      ships a recorder: press REC, enter the mode by hand once, press
      STOP. That exact remote sequence is written to STD_Hub_modes.txt and
      REPLAY fires it again on demand - byte for byte, with real Instance
      arguments resolved from their full paths.

    MACROS
      auto cast      re-runs CAST ALL on a configurable delay
      auto skip      clicks any visible Skip / Next / Continue / Confirm /
                     Claim / Collect button by invoking its Activated
                     connections (no mouse, works on any GUI the game
                     builds at runtime)
      auto claim     same clicker restricted to claim / collect / reward

    CONFIG
      STD_Hub_config.txt, plain key=value, written with writefile and read
      back with readfile. Holds the QTE lead, selected mode, story stage,
      hellmode flag, cast delay and the macro toggles.

    ------------------------------------------------------------------
    V3 - UI
    ------------------------------------------------------------------
    The window is Obsidian (deividcomsono fork of Linoria), pulled with
    game:HttpGet at load time and parented to RobloxGui so the game
    cannot see or delete it.

      Tabs: Abilities / Modes / Macros / Config
      Key:  RightShift
      UI:   Library.ScreenGui -> CoreGui-side, Main frame 720x600

    Elements are addressed by index through Library.Options (dropdowns,
    sliders) and Library.Toggles (toggles). The library keeps those two
    tables on itself, NOT in getgenv - that is the one gotcha.

    Toggle window: RightShift

    ------------------------------------------------------------------
    V4 - PER-MODE MACROS, PER-MODE CONFIGS, FREE PLACEMENT
    ------------------------------------------------------------------
    MACROS  every mode tab owns its own recorder. A recording is a named
            macro, saved to
                STD_Hub_macros/<modeKey>/<name>.txt
            and scoped to that tab, so the gauntlet entry cannot be
            replayed from the raids tab by accident.

            One recorder is active at a time - the capture hook is global
            (a second __namecall hook would stack and double-log), so
            starting REC on one tab stops the one that was running.

            capture mode per macro
              entry  only Teleport / Gauntlet remotes - the mode entry
                     sequence the old v3 recorder wrote to a single file
              full   every RemoteEvent:FireServer and
                     RemoteFunction:InvokeServer the client sends -
                     towers placed, abilities cast, GUI confirmations.
                     This is what turns a hand-played wave into a macro.

            playback runs at exactly the tempo it was recorded at - no speed
            multiplier, no loop count - and is always interruptible: STOP kills
            the replay thread, and the capture hook ignores the hub's own
            traffic while it is replaying so a macro never records itself.

    CONFIGS one folder per mode:
                STD_Hub_configs/<modeKey>/<name>.txt
            same plain key=value format as v3, so old files still load -
            they simply show up under the mode they name in mode=.
            Each mode tab carries its own list, so "gauntlet" and "story"
            never overwrite each other's presets.

    HOTBAR PLACEMENT (Misc tab)
            Pick a unit with 1-5 and the game clones it into workspace as a
            placement preview. The hub watches for that clone, locks onto the
            same unit, and the next left click builds it wherever the cursor
            points. The clone is destroyed after a successful placement so the
            game cannot build a second one on the same click. REC releases the
            textbox focus first, because a focused input swallows 1-5 and that
            is what made placement look broken while recording.

    PLACE   free tower placement, independent of the game's build pads.
            Signature taken from the decompiled client
            (StarterGui.GameGui.GameController - Potassium ships a decompiler,
            so nothing had to be guessed):
                RequestTower:InvokeServer(name, nil, nil, buffed)
                SpawnNewTower:InvokeServer(uuid, cframe, buffed)
            The uuid is the tower instance id from State.GetData().Towers, not
            its name. PLACE AT MOUSE / AT ME / AT COORDS build the CFrame
            themselves. If the selected unit already hit its own MaxTowers the
            hub falls through to the next cheapest tower in the loadout, since
            a RequestTower refusal costs nothing.

            VERIFIED LIVE (Beach, wave 2, 2026-11-13)
                RequestTower(name)        -> true, gold 310 -> 210
                SpawnNewTower(uuid, cf)   -> true, tower at 104.9, 8.5, -29.5
              then, with no pad anywhere near it:
                SpawnNewTower(uuid, cf)   -> true, tower at 0, 41, 250
              So the server does NOT validate the build area - the TowerArea
              raycast is purely a client-side preview colour. Placement is
              free-form: any CFrame you can compute is accepted as long as
              RequestTower succeeds (gold, tower cap, match started).
]]

local CFG = {
    ToggleKey   = Enum.KeyCode.RightShift,
    AutoSolve   = false,   -- do NOT farm the QTE on load: casting a domain is
                           -- the player's decision, not a side effect of loading
    WaitForQTE  = 26,      -- seconds to wait for the minigame
    TargetPts   = 22,      -- Points needed for a full gauge
    SpeedToRate = 0.62,    -- Config.Speed -> bar/s, measured on live trials
    Glow        = 1.25,    -- informational: the bloom is a Glow CHILD of Zone
                           -- drawn 1.25x it, so it hangs outside the rect. the
                           -- hit area is the rect, which means ZoneWidth is
                           -- already the green strip and the glow never needs
                           -- subtracting - aiming at the rect's edge IS ignoring
                           -- the glow

    -- WHERE in the GREEN strip to click. 0 = the middle, 1.0 = the edge the
    -- marker reaches first, which is the earliest a click can legally land.
    -- everything below is in units of the solid strip, not the drawn one - the
    -- glow is not a target
    EdgeAim     = 0.95,    -- start one hair inside the edge
    LateSlack   = 0.55,    -- how far past the aim point a click may still go out,
                           -- as a fraction of the half-width. `dArr <= aim` is
                           -- true across the WHOLE strip, including the far half,
                           -- so a frame that was busy let the next one fire deep
                           -- past the centre - measured: a click at -0.127 with
                           -- hw 0.137, which is the far side, and a miss. this
                           -- keeps the click in the approach half
    EdgeMin     = 0.40,    -- the fault handler will not walk it in past this.
                           -- a quarter of the strip was so far from the edge the
                           -- user could see it clicking late
    EdgeFall    = 0.08,    -- how far it walks in per bad window
    FaultAcc    = 0.55,    -- below this the aim is outside the strip, not late:
                           -- no lead can explain missing nearly half the clicks
    -- THE CLICK IS JUDGED ~120ms AFTER IT IS SENT, AND THAT IS THE WHOLE GAME.
    -- Measured, not assumed: the marker trajectory was recorded at frame rate
    -- and every click replayed against it. A miss at dArr=+0.039 with
    -- hw=0.098 needed the marker to have travelled 0.143 further, which is
    -- ~100ms; a hit at dArr=+0.066 with hw=0.126 survived 150ms and died at
    -- 200. Four independent clicks all bracket the same number. So the client's
    -- MarkerPos is ~120ms BEHIND the marker the server judges, and a click aimed
    -- at the green strip lands 120ms PAST it.
    -- That is why aiming at the entry edge worked at all - hw/rate happens to be
    -- about 120ms - and why it capped out at 83%: the click was landing at the
    -- FAR edge, where the room left is one half-width instead of two.
    -- The fix is to fire one judge-delay BEFORE the marker reaches the centre of
    -- the strip. Then the judged position is the centre, with a full half-width
    -- of room on both sides - the most a click can ever have.
    LeadPrior   = 0.120,   -- seconds. only a seed: it is replaced by the measured
                           -- round trip on the first reply, see LEAD below
    LeadMin     = 0.020,
    LeadMax     = 0.260,
    LeadGain    = 0.30,    -- how fast the measured round trip replaces the seed
    LeadFrac    = 0.58,    -- which part of the round trip is the judgement delay.
                           -- half is the unbiased guess, but every timing error
                           -- in this system adds FORWARD travel: a slower server,
                           -- a late heartbeat, a replication hiccup. none of them
                           -- can make the marker go backwards, so the error is
                           -- one-sided and the aim is biased to match. measured
                           -- at 0.5 the residual misses sat at judged margin
                           -- 0.071-0.074 against hits at 0.076-0.080 - the two
                           -- populations touching, which is what a one-sided
                           -- error looks like when the aim is centred on it
    GuardFrac   = 0.65,    -- a frame is only worth a shot if the extrapolated
                           -- landing point is trustworthy to this fraction of the
                           -- half-width. the extrapolation is now Lead long, not
                           -- one frame long, so rate error matters far more than
                           -- it used to - this is what stops a shot taken on a
                           -- rate that has not settled
    MaxAge      = 0.060,   -- refuse to shoot on a marker sample older than this.
                           -- the prediction is only as good as the sample it is
                           -- extrapolated from, and the log shows gaps up to
                           -- 1.9s - clicking on a 500ms-old position was a coin
                           -- flip that the error bar could never cover
                           -- the edge, which is the one place the click belongs
    MinSamples  = 3,       -- marker updates needed in the CURRENT pass before the
                           -- rate is trusted enough to shoot at all
    Confidence  = 0.75,    -- kept for the old slider, no longer gates the shot
    WinShots    = 24,       -- informational only now: the fault handler judges the
                            -- whole domain, because 24 replies is more than a
                            -- domain produces and the window never completed
    FrozenAfter = 0.25,     -- MarkerPos unchanged for this long = the trial is not
                           -- live (3-2-1 countdown, or the gap after a domain
                           -- ended). the bar is visible the whole time, so the
                           -- bar cannot be the signal. firing here is firing into
                           -- nothing: the server answers, the trial does not
                           -- advance, and the fallback re-arms half a second
                           -- later and fires at the same spot again
    ZoneSettle  = 0.035,    -- a zone has to hold its exact position and width for
                           -- this long before it counts as a trial. it was 120ms
                           -- on the theory that the death animation rewrites
                           -- those values - the decompile says it does not, it
                           -- clones the zone and animates the clone. so this is
                           -- only here to reject a one-frame replication glitch,
                           -- and 120ms of it was 120ms of dead time per trial
    MinClickGap = 0.22,     -- hard floor between two clicks, whatever the gate
                           -- believes. a phantom click lands in the same frame as
                           -- the real one, so anything above a couple of frames
                           -- is already enough; 550ms was eating a third of
                           -- every trial for no extra safety
    StaleTrial  = 1.2,      -- if nothing has proved a new trial this long after a
                           -- click, one has happened anyway
    MinZoneWidth = 0.012,   -- a zone this thin is mid-animation or gone, not a
                           -- target. clicking it is clicking empty bar
    MaxNoShot   = 12,      -- trials in a row with no shot at all and the gate is
                           -- not declining, it is stuck: stop and say so instead
                           -- of farming nothing in silence
    TrialCap    = 130,     -- max seconds inside one domain
    UnstickWait = 25,      -- seconds to wait for a stuck domain to clear
    MaxTrials   = 6,       -- safety cap on domains per FARM press
    Rescan      = 2,       -- seconds between tower rescans
    Verbose     = false,
    -- teleport safety is not a setting: collisions go off automatically around
    -- every teleport and stay off while you are inside a mode
    AutoStart   = false,   -- keep pressing the elevator Start until a match begins
    CastDelay   = 1.2,     -- seconds between auto-cast cycles (abilities tab)
    Notify      = true,    -- toast popups. off = status bar only, no toasts at all
    CastGrace   = 8,       -- seconds the auto driver ignores a tower you just placed
}

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

--=============================================================
-- LOAD GATE
--=============================================================
-- autoexec fires the moment you inject, which can be while the client is still
-- on the loading screen. LocalPlayer is nil then, PlayerGui does not exist yet,
-- and the hub used to die on its first line with nothing on screen - the script
-- "was not there". nothing below this block runs until the game is actually up
local function waitFor(fn, limit)
    local t0 = os.clock()
    while os.clock() - t0 < (limit or 60) do
        local ok, v = pcall(fn)
        if ok and v then return v end
        task.wait(0.2)
    end
    return nil
end

do
    if not game:IsLoaded() then
        pcall(function() game.Loaded:Wait() end)
    end
    waitFor(function() return Players.LocalPlayer end, 120)
    waitFor(function() return Players.LocalPlayer:FindFirstChild("PlayerGui") end, 120)
    waitFor(function() return RS:FindFirstChild("Remotes") end, 120)
    -- soft gate: every tab that needs the save data loads it lazily anyway, so a
    -- short wait here only covers the common case and never stalls a wrong game
    waitFor(function()
        local c = RS:FindFirstChild("Client")
        return c and c:FindFirstChild("State")
    end, 30)
end

local LP           = Players.LocalPlayer
if not LP then
    warn("[STD] hub: the client never finished loading, hub not started")
    return
end
local PG           = LP:WaitForChild("PlayerGui", 30)

--=============================================================
-- CLEANUP
--=============================================================
if getgenv().STD_Hub then
    pcall(function() getgenv().STD_Hub.destroy() end)
end

local Hub = { conns = {}, threads = {}, gui = nil }
getgenv().STD_Hub = Hub

local function addConn(c)
    table.insert(Hub.conns, c)
    return c
end

--=============================================================
-- LOG
--=============================================================
local LOG = {}
local flushLog
local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    local line = ("[%s] %s"):format(os.date("%H:%M:%S"), table.concat(parts, " "))
    table.insert(LOG, line)
    if #LOG > 300 then table.remove(LOG, 1) end
    -- Hub.verbose can be flipped from outside (executor console, MCP) without
    -- touching the UI. that is the only way to watch a live run without asking
    -- for a screenshot, and the file is rewritten every 25 lines so a crash does
    -- not take the evidence with it
    if CFG.Verbose or Hub.verbose then print("[STD] " .. line) end
    if #LOG % 25 == 0 and flushLog then flushLog() end
end

-- ONE LOG PER ACCOUNT, NOT ONE PER MACHINE.
-- the whole log lives in memory and the file is rewritten from it on every
-- flush, so with six clients on one PC the single STD_Hub_log.txt was six
-- writers each overwriting the others from their own array - what survived was
-- whichever client flushed last, and reading it told you nothing about any
-- particular account. that matters most when something goes wrong on ONE of
-- them, which is exactly the case that needs evidence
local LOG_FILE = "STD_Hub_log_" .. LP.Name .. ".txt"

flushLog = function()
    if writefile then
        pcall(function() writefile(LOG_FILE, table.concat(LOG, "\n")) end)
    end
end

--=============================================================
-- TELEPORT DIAGNOSTIC
--=============================================================
-- "Lost connection due to an unknown error (256)" is what the CLIENT draws when
-- a teleport fails or a connection drops. It carries no reason of its own - a
-- Player:Kick would have shown the kick text instead, and this dialog does not -
-- so the only place the reason exists is TeleportService. Recorded here, before
-- anything else in the hub is busy, and written to this account's own log so an
-- alt that dies on the way into an event leaves a note behind.
--   TeleportInitFailed -> the teleport was refused, with a result enum and text
--   OnTeleport         -> the state machine: Started / InProgress / Completed /
--                         Failed, which separates "never left" from "left and
--                         could not land"
-- the getgenv guard is so a hub reload does not stack a second pair of these
if not getgenv().STD_TeleDiag then
    getgenv().STD_TeleDiag = true
    pcall(function()
        local TS = game:GetService("TeleportService")
        TS.TeleportInitFailed:Connect(function(plr, result, message)
            if plr ~= nil and plr ~= Players.LocalPlayer then return end
            log(("teleport refused: %s - %s"):format(tostring(result), tostring(message)))
            flushLog()
        end)
    end)
    pcall(function()
        local plr = Players.LocalPlayer
        if plr and plr.OnTeleport then
            plr.OnTeleport:Connect(function(state, placeId, err)
                log(("teleport %s -> place %s%s"):format(
                    tostring(state), tostring(placeId),
                    err and ("  err=" .. tostring(err)) or ""))
                flushLog()
            end)
        end
    end)
end

--=============================================================
-- ABILITY TABLE
--=============================================================
-- key = Config.AttackType.Value
--   flag      : Config value that unlocks the button
--   flagValue : required value (default true)
--   cd        : Config cooldown value, or "@player.<Name>"
--   remote    : path relative to ReplicatedStorage.Remotes
--   charge    : needs a real meter charge, may be refused by the server
--   qte       : has the timing minigame
local ABILITIES = {
    ["TojiEvo"] = {
        label = "Toji Evo", ability = "ULT", short = "ult",
        flag = "Ult", cd = "UltRemCd",
        remote = "Towers.TojiEvo.TojiUlt", unlock = 6,
    },
    ["SukunaEvo"] = {
        label = "Meguna", ability = "DOMAIN", short = "domain",
        flag = "DomainActive", cd = "DomainRemCd",
        remote = "Towers.KingOfCursesEvo.DomainActive", unlock = 7,
    },
    ["GojoDisco"] = {
        label = "Gojo Disco", ability = "DOMAIN", short = "domain",
        flag = "DomainActive", cd = "DomainRemCd",
        remote = "Towers.GojoDisco.Domain", unlock = 6,
    },
    ["GojoEvo"] = {
        label = "Gojo Evo", ability = "DOMAIN", short = "domain",
        flag = "DomainActive", cd = "@player.EvoGojoDomainRemCd",
        remote = "GojoDomain", unlock = 7,
        -- Unlike every other domain, this one is checked on the server.
        -- Tested at L1, L5 and L6: the gate value can be forced and the
        -- remote fires, but EvoGojoDomainRemCd stays 0 and nothing
        -- happens. At L7 DomainActive is genuinely true, so it works
        -- normally. Below that the bypass is dead.
        serverGate = true,
    },
    ["Sukuna"] = {
        label = "Sukuna", ability = "DOMAIN", short = "domain",
        flag = "DomainActive", cd = "DomainRemCooldown",
        remote = "SukunaDomain",
    },
    ["MahitoAwk"] = {
        label = "Mahito True", ability = "DOMAIN", short = "domain",
        flag = "DomainActive", cd = "DomainRemCd",
        remote = "MahitoDomain",
        -- L1..L5 carry DomainActive but no DomainRemCd at all, so the
        -- cooldown value cannot be zeroed. Measured anyway: firing the
        -- remote at L1 does reach the server - IsCasting flips true, the
        -- Blackflash cooldown resets to 10 and damage jumps ~75k. What is
        -- missing is the domain model itself: no hands, no barrier, because
        -- that part is created server-side only when DomainActive is
        -- genuinely true (L6+). So the cast "works" but there is nothing
        -- big to look at.
        cdOptional = true,
    },
    ["Hakari"] = {
        label = "Hakari", ability = "DOMAIN", short = "domain",
        flag = "DomainActive", cd = "FeverMeter", charge = true,
        remote = "Towers.Hakari.HakariDomain",
    },
    ["OvertimeAwk"] = {
        label = "Overtime Awk", ability = "ULT", short = "ult",
        flag = "Ult", cd = "OvertimeMeter", charge = true,
        remote = "Towers.OvertimeAwk.Ult",
    },
    ["RedScarfSorcererAwk"] = {
        label = "Red Scarf Awk", ability = "RAGE", short = "rage",
        flag = "Rage", cd = "RageMeter", charge = true,
        remote = "Towers.RedScarfSorcererAwk.Rage",
    },
    ["MechaSorcerer"] = {
        label = "Mecha Sorcerer", ability = "ACTIVE", short = "active",
        flag = "ActiveAmount", flagValue = 3, cd = "ActiveRemCd",
        remote = "MechaXmassActive",
    },
    ["RedScarfSorcererAnniversary"] = {
        label = "Red Scarf (Anniv)", ability = "CELEBRATION", short = "celebration",
        flag = "Celebration", cd = "CelebrationRemCd",
        remote = "Towers.RedScarfSorcerer.Ability", unlock = 6,
    },
    ["SukunaFrost"] = {
        label = "Sukuna Frost", ability = "DOMAIN", short = "domain",
        flag = "DomainActive", cd = "DomainRemCooldown",
        remote = "Towers.KingOfCursesFrost.Domain", unlock = 6,
    },
    ["LightningSorcerer"] = {
        label = "Lightning", ability = "BEAST AMBER", short = "amber",
        flag = "BeastAmber", cd = "BeastAmberRemCd",
        remote = "Towers.Lightning.BeastAmber", unlock = 6,
    },
    ["JusticeSorcerer"] = {
        label = "Justice (Higuruma)", ability = "DOMAIN", short = "domain",
        flag = "DomainActive", cd = "DomainRemCd",
        remote = "Towers.JusticeSorcerer.Domain", unlock = 6, qte = true,
    },
    ["ProjectionSorcerer"] = {
        label = "Projection", ability = "ULTIMATE", short = "ultimate",
        flag = "Ultimate", cd = "UltimateRemCd",
        remote = "Towers.ProjectionSorcerer.Ultimate", unlock = 6,
        -- The Ultimate itself is dead below L6: the remote fires, but the
        -- server never echoes UltimateCutscene / UltimateAnim back, so the
        -- cinematic never plays. Barrage and SmashKick are a different
        -- story - both are processed at L1 (IsCasting flips, the frame
        -- stacks appear on mobs, SmashKick really deals its damage), so we
        -- fire those alongside the ult. That is what you actually see.
        extra = {
            "Towers.ProjectionSorcerer.Barrage",
            "Towers.ProjectionSorcerer.SmashKick",
        },
    },
    ["ExplosiveSorcerer"] = {
        label = "Explosive", ability = "KAMIKAZE", short = "kamikaze",
        flag = "Kamikaze", cd = "KamikazeRemCd",
        remote = "Towers.ExplosiveSorcerer.Kamikaze", unlock = 1,
    },
}

--=============================================================
-- REMOTE / TEMPLATE LOOKUP
--=============================================================
local RemotesRoot = RS:WaitForChild("Remotes", 30)

local function resolveRemote(path)
    if not RemotesRoot then return nil end
    local node = RemotesRoot
    for part in string.gmatch(path, "[^%.]+") do
        if not node then return nil end
        node = node:FindFirstChild(part)
    end
    return node
end

-- a few abilities keep their cooldown on the player instead of the tower
local function cdValueOf(spec, cfg)
    if not spec.cd then return nil end
    local p = spec.cd
    if string.sub(p, 1, 8) == "@player." then
        return LP:FindFirstChild(string.sub(p, 9))
    end
    return cfg and cfg:FindFirstChild(p) or nil
end

-- template index: every Model under ReplicatedStorage.Towers that has a
-- Config with AttackType, so we can work out which level a placed tower is
local TemplateIndex = nil
local TemplateFamily = nil   -- attackType -> { order = {name,name,...} }

local function buildTemplateIndex()
    TemplateIndex, TemplateFamily = {}, {}
    local T = RS:FindFirstChild("Towers")
    if not T then return end

    for _, m in ipairs(T:GetDescendants()) do
        if m:IsA("Model") then
            local cfg = m:FindFirstChild("Config")
            if cfg and cfg:FindFirstChild("AttackType") then
                TemplateIndex[m.Name] = m
            end
        end
    end

    for _, m in ipairs(T:GetDescendants()) do
        if m:IsA("Model") then
            local cfg = m:FindFirstChild("Config")
            if cfg and cfg:FindFirstChild("AttackType") then
                local at = cfg.AttackType.Value
                local fam = TemplateFamily[at]
                if not fam then
                    fam = { members = {} }
                    TemplateFamily[at] = fam
                end
                table.insert(fam.members, m)
            end
        end
    end

    for _, fam in pairs(TemplateFamily) do
        local pointed = {}
        for _, m in ipairs(fam.members) do
            local up = m.Config:FindFirstChild("Upgrade")
            local v = up and up.Value
            if v then pointed[v.Name] = true end
        end
        local order, seen = {}, {}
        for _, m in ipairs(fam.members) do
            if not pointed[m.Name] and not seen[m.Name] then
                local cur, guard = m, 0
                while cur and guard < 20 do
                    if seen[cur.Name] then break end
                    seen[cur.Name] = true
                    table.insert(order, cur.Name)
                    local up = cur.Config:FindFirstChild("Upgrade")
                    local v = up and up.Value
                    if not v then break end
                    cur = TemplateIndex[v.Name]
                    guard = guard + 1
                end
            end
        end
        fam.order = order
    end
end

local function levelOf(model, attackType)
    local fam = TemplateFamily and TemplateFamily[attackType]
    if not fam or not fam.order then return nil, nil end
    for i, name in ipairs(fam.order) do
        if name == model.Name then return i, #fam.order end
    end
    return nil, #fam.order
end

--=============================================================
-- TOWER SCAN
--=============================================================
local function scanTowers()
    local out = {}
    local root = workspace:FindFirstChild("Towers")
    if not root then return out end

    local seen = {}
    for _, m in ipairs(root:GetDescendants()) do
        if m:IsA("Model") and not seen[m] then
            local cfg = m:FindFirstChild("Config")
            if cfg and cfg:FindFirstChild("AttackType") then
                local at = cfg.AttackType.Value
                local spec = ABILITIES[at]
                if spec then
                    seen[m] = true
                    local lvl, maxlvl = levelOf(m, at)
                    local remote = resolveRemote(spec.remote)
                    local gate = cfg:FindFirstChild(spec.flag)
                    local unlocked
                    if spec.flagValue ~= nil then
                        unlocked = gate ~= nil and gate.Value == spec.flagValue
                    else
                        unlocked = gate ~= nil and gate.Value == true
                    end

                    -- the bypass needs the gate value to exist and, for most
                    -- abilities, the cooldown value too. Some towers simply do
                    -- not carry those values until a later upgrade, and then
                    -- nothing can be forced from the client.
                    local cdObj = cdValueOf(spec, cfg)
                    local blocked = nil
                    if spec.serverGate then
                        blocked = "server checks the level"
                    elseif gate == nil then
                        blocked = "no " .. spec.flag .. " on this level"
                    elseif cdObj == nil and not spec.cdOptional then
                        blocked = "no " .. tostring(spec.cd) .. " on this level"
                    elseif spec.needs then
                        for _, need in ipairs(spec.needs) do
                            if cfg:FindFirstChild(need) == nil then
                                blocked = "no " .. need .. " on this level"
                                break
                            end
                        end
                    end

                    table.insert(out, {
                        model    = m,
                        name     = m.Name,
                        attack   = at,
                        spec     = spec,
                        level    = lvl,
                        maxlvl   = maxlvl,
                        remote   = remote,
                        unlocked = unlocked,
                        charge   = spec.charge and true or false,
                        blocked  = blocked,
                    })
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

--=============================================================
-- UNLOCK + CAST
--=============================================================
local function unlock(model, spec)
    local cfg = model:FindFirstChild("Config")
    if not cfg then return end

    local gate = cfg:FindFirstChild(spec.flag)
    if gate then
        if spec.flagValue ~= nil then
            if gate.Value ~= spec.flagValue then
                pcall(function() gate.Value = spec.flagValue end)
            end
        elseif gate:IsA("BoolValue") and not gate.Value then
            pcall(function() gate.Value = true end)
        end
    end

    -- charge meters are real gameplay state - forcing them to 0 makes the
    -- ability look "not ready" instead of ready, so leave them alone
    if not spec.charge then
        local cd = cdValueOf(spec, cfg)
        if cd and cd:IsA("ValueBase") and cd.Value ~= 0 then
            pcall(function() cd.Value = 0 end)
        end
    end

    local casting = cfg:FindFirstChild("IsCasting")
    if casting and casting:IsA("BoolValue") and casting.Value then
        pcall(function() casting.Value = false end)
    end
end

local function castEntry(entry)
    if not entry.remote then return false, "remote missing" end
    unlock(entry.model, entry.spec)

    local cfg = entry.model:FindFirstChild("Config")
    local cast = cfg and cfg:FindFirstChild("IsCasting")
    local cd = cfg and cdValueOf(entry.spec, cfg)
    -- DomainActive is the one the server sets when the domain is actually up.
    -- IsCasting and the cooldown are both unreliable for this tower: measured
    -- live with a QTE running, the tower read DomainActive=true, IsCasting=false
    -- and DomainRemCd=0, so both old signals said "refused" while the domain was
    -- right there on screen. that false negative is why the farm kept stopping
    local domActive = cfg and cfg:FindFirstChild("DomainActive")
    local wasActive = domActive and domActive.Value or false
    local wasCasting = cast and cast.Value or false
    local cdBefore = (cd and cd:IsA("ValueBase")) and cd.Value or nil

    local ok, err = pcall(function() entry.remote:FireServer(entry.model) end)
    if not ok then return false, tostring(err) end

    -- a few towers only produce anything when several remotes go off
    -- together, so fire the companions too
    if entry.spec.extra then
        for _, path in ipairs(entry.spec.extra) do
            local r = resolveRemote(path)
            if r then
                pcall(function() r:FireServer(entry.model) end)
                task.wait(0.05)
            end
        end
    end

    -- watch for the server actually picking the cast up. A cooldown being
    -- set, or IsCasting flipping on, can only come from the server.
    local accepted = false
    local t0 = os.clock()
    while os.clock() - t0 < 0.9 do
        if cast and cast.Value and not wasCasting then
            accepted = true
            break
        end
        if cd and cd:IsA("ValueBase") and cd.Value > 0 and cdBefore ~= cd.Value then
            accepted = true
            break
        end
        -- DomainActive has to FLIP, not merely be true. it stays true for the
        -- whole duration of a domain, so reading it as "accepted" made every
        -- re-cast look successful while the domain was already up - and the
        -- farm sat there firing a cast every 1.5s that did nothing
        if domActive and domActive.Value and not wasActive then
            accepted = true
            break
        end
        -- qteFolder() is declared further down the file, so calling it from here
        -- resolved to a global and blew up with "attempt to call a nil value"
        -- on every cast. LP is available this early, so read the folder directly
        local qq = LP and LP:FindFirstChild("QTE")
        if qq and qq:FindFirstChild("InQTE") and qq.InQTE.Value then
            accepted = true
            break
        end
        task.wait(0.05)
    end
    entry.lastAccepted = accepted
    return true, accepted and "ok" or "silent"
end

--=============================================================
-- QTE
--=============================================================
-- lazy: the folder only exists inside a match, so never block on it here
local QTE = LP:FindFirstChild("QTE")

local function qteFolder()
    if QTE and QTE.Parent then return QTE end
    QTE = LP:FindFirstChild("QTE")
    return QTE
end

-- beat is the whole point of the lock. a boolean cannot tell "a loop is running"
-- from "a loop died and left the flag set", so the old code guessed - and the
-- guess it made was "stale, take over", which it applied while the loop was
-- very much alive. two loops then clicked the same trial in the same
-- millisecond. a live loop stamps beat every frame, so staleness is a fact
-- instead of an opinion
local Solver = { busy = false, stop = false, token = 0, active = false,
                 running = false, runToken = nil, beat = 0, farming = false,
                 -- gen is the FARM DRIVER's lifetime and nothing else touches
                 -- it. token cancels one rotation and is bumped by six other
                 -- paths; using it for both meant every one of them killed the
                 -- farm. busyRun names whoever set busy, so a thread that was
                 -- overtaken can no longer leave the flag stuck on
                 gen = 0, busyRun = 0, supervisor = nil }

local SOLVER_STALE = 1.0   -- seconds without a heartbeat before a lock is dead

local function points()
    local q = qteFolder()
    if not q then return 0 end
    local p = q:FindFirstChild("Points")
    return p and p.Value or 0
end

local function waitQTE(timeout)
    local t0 = os.clock()
    while os.clock() - t0 < timeout do
        local q = qteFolder()
        if q and q.InQTE and q.InQTE.Value then return true end
        task.wait(0.02)
    end
    return false
end

--=============================================================
-- QTE GUI KEEPER
--=============================================================
-- The game's own LocalScript does exactly one thing to the bar:
--     InQTE.Changed -> Frame.Visible = value
-- so if that connection ever dies (the script errors once, the ScreenGui gets
-- disabled, or the frame is re-parented) the bar stays hidden for the rest of
-- the session even though the trial is still running. We cache the ScreenGui
-- and put it back whenever it is missing, disabled or out of sync.
local qteGui, qteFrame = nil, nil

local function keepQTEvisible()
    local q = qteFolder()
    if qteGui == nil then
        local g = PG:FindFirstChild("QTE")
        if g then
            qteGui = g
            qteFrame = g:FindFirstChild("Frame")
        end
    end
    if qteGui == nil then return end

    -- the ScreenGui got destroyed or unparented: put it back
    if qteGui.Parent == nil then
        pcall(function() qteGui.Parent = PG end)
    end
    if qteGui:IsA("ScreenGui") and not qteGui.Enabled then
        pcall(function() qteGui.Enabled = true end)
    end
    if qteFrame == nil or qteFrame.Parent == nil then
        qteFrame = qteGui:FindFirstChild("Frame")
    end
    if qteFrame == nil then return end

    local want = false
    local inq = q and q:FindFirstChild("InQTE")
    if inq then want = inq.Value end
    if qteFrame.Visible ~= want then
        pcall(function() qteFrame.Visible = want end)
    end
    -- a running trial must never sit behind a broken tween/transparency
    if want then
        local bar = qteFrame:FindFirstChild("Bar")
        if bar and bar:IsA("GuiObject") and bar.Visible == false then
            pcall(function() bar.Visible = true end)
        end
    end
end
Hub.keepQTEvisible = keepQTEvisible

task.spawn(function()
    while getgenv().STD_Hub == Hub do
        pcall(keepQTEvisible)
        task.wait(0.35)
    end
end)

local function playTrial()
    --[[
      Rebuilt from live measurement of the real minigame:

      * one trial = one zone. a click ends the trial and the server spawns the
        next one almost instantly, so a single 14s domain is worth 20-40
        trials. the old solver treated a whole domain as one pass.
      * Result never fires on the reply path (verified over ~40 clicks), so the
        old "tune the lead from the server reply" loop never tuned anything.
        Points is the only ground truth: a hit is +1.0 and +0.1 per consecutive
        hit, a miss is -1.0 and resets the streak.
      * MarkerPos is replicated at ~23 Hz and quantised to 0.01, and the speed
        changes on EVERY trial. a rate carried over from the previous trial is
        what produced the misses - so the speed is fitted inside the current
        trial, with Speed*SpeedToRate as the prior for the first frame.
      * the click has to land when the marker will be at the CENTRE of the zone
        one one-way latency from now. clicking the edge (the old AimFrac) put
        the marker outside the 0.19 wide zones by the time the click arrived.
    ]]
    local Q = qteFolder()
    if not Q then return false end
    local speedV = Q:FindFirstChild("Speed")
    local rightV = Q:FindFirstChild("GoingRight")
    local widthV = Q:FindFirstChild("ZoneWidth")
    local zoneV  = Q:FindFirstChild("ZonePos")
    local markV  = Q:FindFirstChild("MarkerPos")
    if not (widthV and zoneV and markV) then return 0, 0, 0 end

    -- two loops on the same bar click twice at the same spot, because each one
    -- keeps its own idea of "this trial was already clicked". this is the hard
    -- stop for that. the lock is only taken over when the holder has stopped
    -- heartbeating, not when its token looks old - a token changes every time
    -- anything casts a domain, and that used to read as "stale" while the loop
    -- was still running
    if Solver.running then
        local beat = Solver.beat or 0
        if (os.clock() - beat) < SOLVER_STALE then
            log(("qte: a solver loop is already live (beat %.0fms ago) - refusing a second one")
                :format((os.clock() - beat) * 1000))
            return 0, 0, 0
        end
        log(("qte: taking over a dead solver lock (no beat for %.1fs)"):format(os.clock() - beat))
    end
    Solver.running = true
    Solver.runToken = Solver.token
    Solver.beat = os.clock()

    local hits, misses, clicks = 0, 0, 0
    local lastPts = points()
    -- where in the GREEN strip the click should land, in units of the solid
    -- strip's half-width: 0 is the middle, 1.0 is the edge the marker reaches
    -- first. this is NOT carried between domains and it is not learned: the
    -- gate fires at min(target, hw - errBar), so wherever errBar is narrower
    -- than (1-edge)*hw the error bar decides the landing point and `edge` is
    -- inert. the aim therefore stays at the edge the user asked for, and the
    -- single learned quantity is the error bar. it used to be restored from
    -- getgenv(), which meant one bad domain at 0.70 kept every later domain
    -- 30% inside the strip - measured live, the aim was still 0.70 a session
    -- later while the log claimed the edge was the target
    local edge = CFG.EdgeAim
    -- how long the marker keeps travelling after the click is sent before the
    -- server judges it. seeded from the prior and replaced by half the measured
    -- round trip on the first reply - see the LEAD comment in CFG
    local lead = CFG.LeadPrior
    local lastRate = 0.8
    local sig = nil
    local pend = nil
    local TS, MS = {}, {}
    local lastMp, lastT = markV.Value, os.clock()
    local t0 = os.clock()
    local trialNo = 0
    local trialStart = os.clock()
    -- trials in a row that ended without a single click going out. declining is
    -- free, so a handful is normal - but a dozen in a row means the rate fit is
    -- not converging (or the marker is not being replicated at all), and the
    -- honest thing is to stop and say that rather than farm zero in silence
    local noShot, clickedThis = 0, false
    local lastDArr, lastRateUsed, lastAge, lastSpd = 0, 0, 0, 0
    -- the last time MarkerPos actually changed. a bar that is up with a marker
    -- that is not moving is not a live trial
    local lastMoveAt = os.clock()
    local winHits, winShots = 0, 0
    local lastTarget = 0
    local lastClick = 0
    -- one click per SETTLED trial. a trial is only opened by a zone signature
    -- that has not moved for ZoneSettle - see the settle check in the loop.
    -- the old guard re-armed on any change to that signature, and the death
    -- animation after a click changes it on every frame, so the guard opened a
    -- new trial 30ms after the previous click and a second click went out
    -- against a trial the server had already closed
    local settleSeq, lastClickSeq = 0, -1
    local settledSig, sigSince = nil, os.clock()
    local streak, bestStreak = 0, 0
    -- exposed so the QTE groupbox can show a live hit rate
    Hub.qteStats = { hits = 0, misses = 0, clicks = 0, aim = edge, edge = edge,
                     lead = lead, minGap = 99, anim = 0, why = {} }
    -- one domain per trace, so the gap column always describes one run
    Hub.qteTrace = {}
    -- the server answers every click on Click with a boolean: true = hit. that
    -- is the real ground truth, Points is only a fallback for a silent reply.
    local replyHit, replyAt = nil, 0
    local clickConn
    pcall(function()
        clickConn = Q.Click.OnClientEvent:Connect(function(hit)
            replyHit = hit and true or false
            replyAt = os.clock()
        end)
    end)
    local frames, frameSum, frameMax, lastBeat = 0, 0, 0, os.clock()
    local upd, maxGap = 0, 0

    -- least squares over the samples of the CURRENT pass, and the standard
    -- error of the slope along with it. the slope says where the marker will be
    -- in `lead` seconds; the error says how much that number can be trusted, and
    -- that is what decides whether a click is worth taking at all. a shot taken
    -- on a rate that is 20% out lands 20% * lead away from where it was aimed,
    -- which is the entire difference between a streak and a lost point
    local function fit()
        local n = #TS
        if n < CFG.MinSamples then return nil, nil end
        local st, sm = 0, 0
        for i = 1, n do st = st + TS[i]; sm = sm + MS[i] end
        local mt, mm = st / n, sm / n
        local num, den = 0, 0
        for i = 1, n do
            local dt = TS[i] - mt
            num = num + dt * (MS[i] - mm)
            den = den + dt * dt
        end
        if den < 1e-7 then return nil, nil end
        local r = num / den
        if r < 0.03 or r > 8 then return nil, nil end
        local sse = 0
        for i = 1, n do
            local e = MS[i] - (mm + r * (TS[i] - mt))
            sse = sse + e * e
        end
        local err = 0.5
        if n > 2 then err = math.sqrt(sse / (n - 2) / den) end
        return r, err
    end

    local hb = game:GetService("RunService").Heartbeat:Connect(function()
        local now = os.clock()
        local dt = now - lastBeat
        lastBeat = now
        if dt > 0 and dt < 1 then
            frames = frames + 1
            frameSum = frameSum + dt
            if dt > frameMax then frameMax = dt end
        end
    end)

    while os.clock() - t0 < CFG.TrialCap do
        if Solver.stop then break end
        if not (Q.InQTE and Q.InQTE.Value) then break end

        local now = os.clock()
        Solver.beat = now
        local mp  = markV.Value
        local zp  = zoneV.Value
        local hw  = widthV.Value * 0.5
        local dir = (rightV and rightV.Value) and 1 or -1
        local curSig = ("%.3f|%.4f|%d"):format(zp, widthV.Value, dir)

        -- the zone moved or changed width. on a live trial that happens once,
        -- between trials. during the death animation after a click it happens
        -- on every frame, which is the tell used right below
        if curSig ~= sig then
            sig = curSig
            sigSince = now
            -- how many times the zone moved while a click was in flight. on a
            -- clean trial this is zero; anything above zero is the death
            -- animation, and it is the number that used to re-arm the guard
            if pend then pend.anim = pend.anim + 1 end
            TS, MS = {}, {}
            lastMp, lastT = mp, now
        end

        -- A TRIAL IS A ZONE THAT HAS HELD STILL.
        -- the death animation keeps rewriting ZonePos and ZoneWidth for several
        -- frames. every rewrite used to bump the trial epoch, that re-armed the
        -- click guard, and a second click went out against a trial the server
        -- had already closed. a signature that has not moved for ZoneSettle is
        -- now the only thing that opens a trial
        if settledSig ~= curSig and (now - sigSince) >= CFG.ZoneSettle then
            settledSig = curSig
            settleSeq = settleSeq + 1
            -- close the trial that just ended before opening the next one
            if trialNo > 0 then
                if clickedThis then
                    noShot = 0
                else
                    noShot = noShot + 1
                    -- A TRIAL WITH NO CLICK IS NOT EVIDENCE THE BAR IS TOO WIDE.
                    -- it used to be read as that, and the error bar was cut 4%
                    -- every single time - 14 lost trials in one domain is
                    -- 0.96^14 = 0.55, so a run that was 17% short on accuracy
                    -- had its bar quietly halved, which made the next domain
                    -- worse, which lost more trials. that is the loop that held
                    -- the whole thing at 83%. most lost trials are lost to the
                    -- gap floor, a stale sample or a settle, none of which say
                    -- anything about timing. nothing is adjusted here any more:
                    -- the lead is measured, not tuned by attrition
                end
            end
            clickedThis = false
            if noShot >= CFG.MaxNoShot then
                log(("qte: %d trials in a row with no shot - the rate fit is not converging, stopping"):format(noShot))
                if Hub.setStatus then Hub.setStatus("qte: no shot in " .. noShot .. " trials - check the log", "bad") end
                break
            end
            trialNo = trialNo + 1
            trialStart = now
        end

        if mp ~= lastMp then
            lastMoveAt = now
            -- the marker was put back at the start. that only happens between
            -- trials, so it opens a new one even if the zone happens to reuse
            -- the same position - but only once the click has been judged and
            -- the gap floor has passed, so it can never re-arm inside the trial
            -- it already clicked
            if math.abs(mp - lastMp) > 0.15 and pend == nil
                and (now - lastClick) >= CFG.MinClickGap then
                settleSeq = settleSeq + 1
            end
            local dt = now - lastT
            local dv = (mp - lastMp) * dir
            -- the marker turned around. the samples either side of a bounce
            -- describe two different lines, and fitting them together produces
            -- a slope that is wrong in both directions - which is why a bounce
            -- used to poison the next six frames. the pass is over, so its
            -- samples go with it
            if dv < -0.0002 then TS, MS = {}, {} end
            if dt > 0.0003 and dv > 0.0002 and dv < 0.45 then
                TS[#TS + 1] = now
                MS[#MS + 1] = mp * dir
                if #TS > 10 then table.remove(TS, 1); table.remove(MS, 1) end
                upd = upd + 1
                if dt > maxGap then maxGap = dt end
            end
            lastMp, lastT = mp, now
        end

        -- there is deliberately no blind re-arm here any more. the old one gave
        -- up after half a second and called the next crossing a new trial, but
        -- half a second is well inside a single trial - so every time the zone
        -- and the marker happened to replicate identical values, that fallback
        -- produced exactly the double click it was supposed to prevent. the
        -- only fallback now is StaleTrial, which is longer than any trial

        -- ground truth first: the Click reply tells us hit or miss directly.
        -- the window matters: the game fires this same event for the player's own
        -- mouse clicks, so a reply that turns up long after our click is
        -- somebody else's, and counting it as ours would teach the lead learner
        -- from noise
        if pend and replyAt >= pend.at and (replyAt - pend.at) <= 0.5 then
            local hit = replyHit == true
            -- the round trip, taken before pend is cleared. this is the only
            -- free measurement of how long the server took to judge, and it is
            -- what the lead is learned from below
            local rtJudge = now - pend.at
            if hit then
                hits = hits + 1
                streak = streak + 1
                if streak > bestStreak then bestStreak = streak end
            else
                misses = misses + 1
                streak = 0
            end
            -- THERE IS NO CLICK LEAD SETTING, AND NO NEED FOR ONE. What there is
            -- instead is a lead that is MEASURED: the marker is judged ~120ms
            -- after the click leaves, so the click goes out when the marker is
            -- still that far short of the strip, and arrives at the centre.
            -- See CFG.LeadPrior for the trajectory evidence.
            --
            -- The old build asserted the opposite - that the server judges at
            -- the tick() the client sends, so latency could only push the marker
            -- deeper and an edge aim needed no lead at all. The trajectory says
            -- otherwise: four clicks, one miss and three hits, all bracketing a
            -- ~120ms delay between the send and the judgement. With a lead of
            -- zero the click lands at the FAR edge, one half-width from the exit
            -- instead of two, and 83% is exactly what that buys.
            if CFG.Verbose then
                log(("click %s dArr=%+.3f aimAt=%+.3f edge=%.2f zone=%.3f half=%.3f rate=%.2f spd=%.2f age=%.0fms errBar=%.3f rt=%.0fms lead=%.0fms anim=%d -> %.2f/%.0f streak=%d"):format(
                    hit and "HIT " or "MISS", pend.dArr, pend.target or 0, edge,
                    pend.zp, pend.hw, lastRateUsed, lastSpd, lastAge * 1000,
                    pend.err or 0, rtJudge * 1000, lead * 1000, pend.anim or 0,
                    points(), CFG.TargetPts, streak))
            end
            local tr = Hub.qteTrace
            if tr and tr[#tr] then
                tr[#tr].hit  = hit and 1 or 0
                tr[#tr].anim = pend.anim or 0
                tr[#tr].rt   = rtJudge
                tr[#tr].lead = lead
            end
            if Hub.qteStats and (pend.anim or 0) > (Hub.qteStats.anim or 0) then
                Hub.qteStats.anim = pend.anim
            end
            lastPts = points()
            pend = nil
            -- judged. a trial only re-arms on the next SETTLE, and only if that
            -- settle happens after this instant - which is why the sequence is
            -- recorded here and not at click time
            lastClickSeq = settleSeq
            winShots = winShots + 1
            if hit then winHits = winHits + 1 end

            -- THE LEAD, MEASURED. the reply arrives rtJudge after the click was
            -- sent, and the server judged somewhere inside that window; half of
            -- it is the natural estimate of how far the marker had travelled by
            -- then. no window, no tuning by attrition, no slider: one EMA per
            -- judged click, on a number the wire hands over for free
            if rtJudge > 0 and rtJudge < 1.0 then
                local want = rtJudge * CFG.LeadFrac
                if want < CFG.LeadMin then want = CFG.LeadMin end
                if want > CFG.LeadMax then want = CFG.LeadMax end
                lead = lead + (want - lead) * CFG.LeadGain
            end

            -- the fault handler is a different diagnosis and needs a different
            -- sample. "aim is outside the strip" is structural - it holds for
            -- every click in the run - so it is judged on the WHOLE domain, not
            -- on 24 clicks that never arrive. below FaultAcc over the full run
            -- means the lead is not the explanation and the aim has to walk in;
            -- above 0.95 means it can walk back out
            local accAll = hits / (hits + misses)
            if (hits + misses) >= 12 then
                if accAll < CFG.FaultAcc then
                    local before = edge
                    edge = math.max(CFG.EdgeMin, edge - CFG.EdgeFall * 0.5)
                    log(("qte: %.0f%% over %d clicks - aim is outside the strip, edge %.2f -> %.2f")
                        :format(accAll * 100, hits + misses, before, edge))
                elseif accAll > 0.95 then
                    -- a clean run earns the aim back. the aim now starts at the
                    -- edge on every domain, so this only undoes a fault walk-in
                    edge = math.min(CFG.EdgeAim, edge + CFG.EdgeFall * 0.25)
                end
            end
            if Hub.qteStats then
                Hub.qteStats.hits = hits
                Hub.qteStats.misses = misses
                Hub.qteStats.clicks = clicks
                Hub.qteStats.aim = edge
                Hub.qteStats.edge = edge
                Hub.qteStats.lead = lead
            end
        else
            -- fallback: no reply, so fall back to watching the gauge move
            local pts = points()
            if pts ~= lastPts then
                local d = pts - lastPts
                if d > 0 then
                    hits = hits + 1
                    streak = streak + 1
                    if streak > bestStreak then bestStreak = streak end
                else
                    misses = misses + 1
                    streak = 0
                end
                if CFG.Verbose then
                    log(("click %s (no reply) dArr=%+.3f aimAt=%+.3f edge=%.2f -> %.2f/%.0f"):format(
                        d > 0 and "HIT " or "MISS", lastDArr, lastTarget, edge, pts, CFG.TargetPts))
                end
                pend = nil
                lastPts = pts
                lastClickSeq = settleSeq
            elseif pend and (now - lastClick) > 0.25 then
                -- the server swallowed the click. treat the trial as over and
                -- let the next settle fire, otherwise this deadlocks. this was
                -- 600ms, which is longer than half a trial - so every swallowed
                -- click also cost the next trial, and the solver looked like it
                -- was clicking "with a delay" when it was really just waiting
                -- out its own timeout
                pend = nil
                lastClickSeq = settleSeq
            end
        end

        if pend == nil and (now - lastClick) > 0.03 then
            local rate, rateErr = fit()
            if rate then lastRate = rate end
            local prior = (speedV and speedV.Value or 0) * CFG.SpeedToRate
            local rateUse = rate or (lastRate * 0.4 + prior * 0.6)
            if rateUse < 0.05 then rateUse = 0.05 end

            local age = now - lastT
            if age > 0.14 then age = 0.14 end
            -- hw is the half-width of the drawn Zone, and the decompile is
            -- unambiguous about what that is: ZoneWidth drives Zone.Size.X, and
            -- the bloom is a Glow CHILD drawn 1.25x its parent - so the glow
            -- sits outside the rect, not inside it. hw is therefore already the
            -- green strip, and aiming at hw is aiming at the green edge with the
            -- glow deliberately untouched
            local hwS = hw
            local predNow = mp * dir + rateUse * age
            local dArr = zp * dir - predNow
            -- WHERE THE MARKER WILL BE WHEN THE SERVER JUDGES.
            -- dArr is measured at click time, but the click is judged ~lead
            -- later, and over that time the marker covers rateUse*lead more
            -- strip. so the position the server sees is dArr - rateUse*lead, and
            -- the click should go out when THAT number is zero - the centre of
            -- the strip. expressed as a fire point, that is dArr <= rate*lead.
            -- `edge` survives as a trim on top, in half-widths: 0.95 fires 5% of
            -- a half-width EARLIER than the centre, which is the safe direction
            -- if the measured lead is a little short
            local target = rateUse * lead + hwS * (1 - edge)
            -- how far the fitted slope can be out over the whole extrapolation.
            -- this is now the guard on whether a frame is worth a shot, not the
            -- thing that sets the aim - extrapolating 120ms on a slope fitted
            -- from 10 samples of a 45Hz signal is where the error lives
            local errBar = (rateErr or 1) * (age + lead) + 0.004
            -- exactly one click per settled trial. until a zone has settled
            -- since the last click was judged, no second click goes out, no
            -- matter where the marker is
            local fresh = (settleSeq > lastClickSeq) or ((now - lastClick) > CFG.StaleTrial)
            -- and never two clicks inside one trial, whatever the gate believes
            local cooled = (now - lastClick) >= CFG.MinClickGap
            -- a zone thinner than this is mid-animation or already gone. the
            -- gate cannot save a click aimed at a strip that is not there
            local liveZone = hwS >= CFG.MinZoneWidth
            -- a bar with a marker that has not moved in 250ms is not a live
            -- trial. nothing is fired, whatever the gate says
            local frozen = (now - lastMoveAt) > CFG.FrozenAfter
            -- and the sample the prediction is built from has to be recent. the
            -- error bar can cover 30ms of extrapolation, not 500ms of it
            local freshSample = age <= CFG.MaxAge
            -- the shot itself: the marker is close enough to the point that the
            -- judged position will be at the centre, and the extrapolation is
            -- tight enough to be worth trusting. if it is not, the frame is
            -- skipped and the next one is tried - a shot taken on a guess costs
            -- a point AND the streak
            --
            -- THE LOWER BOUND IS NOT OPTIONAL. dArr counts down and keeps
            -- falling after the strip is behind the marker, so `dArr <= target`
            -- alone stays true all the way down the bar - which is a click into
            -- empty space. the click has to be in the approach window: at the
            -- fire point or just past it
            --
            -- there is deliberately no "last ditch" shot when the trial is
            -- about to expire. it was simulated against the same trials: firing
            -- at the deadline without the guard drops accuracy and costs more
            -- points than the wasted trial ever did, because a missed trial is
            -- free and a missed click is -1 plus the streak. a trial that never
            -- lines up is a trial to let go of
            local go = (not frozen) and fresh and cooled and liveZone and freshSample
                and (dArr <= target)
                and (dArr >= target - hwS * CFG.LateSlack)
                and (errBar <= hwS * CFG.GuardFrac)

            -- why a click did not go out on a frame where the marker was
            -- already ON the green. only these frames matter: everywhere else
            -- the answer is simply "not there yet", which is not a problem.
            -- this is what turns "it clicks on empty space" into a number
            if (not go) and math.abs(dArr) <= hwS and Hub.qteStats then
                local why = Hub.qteStats.why
                local k
                if frozen then k = "frozen"
                elseif not liveZone then k = "thinZone"
                elseif not cooled then k = "gap"
                elseif not fresh then k = "noTrial"
                elseif not freshSample then k = "stale"
                elseif dArr > target then k = "early"
                elseif dArr < target - hwS * CFG.LateSlack then k = "late"
                else k = "errBar" end
                why[k] = (why[k] or 0) + 1
            end

            if go then
                clicks = clicks + 1
                clickedThis = true
                lastDArr, lastRateUsed, lastAge, lastTarget = dArr, rateUse, age, target
                lastSpd = speedV and speedV.Value or 0
                -- measured BEFORE lastClick moves, or every gap reads zero -
                -- which is exactly what it did, and it hid whether a phantom
                -- click was happening at all
                local gap = now - lastClick
                lastClick = now
                replyHit, replyAt = nil, 0
                pend = { zp = zp, hw = hw, dArr = dArr, target = target, at = now, err = errBar, anim = 0 }
                -- every click, on the record. a phantom one is then a number in
                -- this table - the gap to the click before it - instead of
                -- something to be argued about from a screenshot
                local tr = Hub.qteTrace
                if not tr then tr = {} Hub.qteTrace = tr end
                -- m is the JUDGED margin: how far inside the strip the click
                -- will be when the server looks at it. this is the number that
                -- decides the outcome now, not the distance to the entry edge -
                -- a click is free to go out before the marker has entered
                tr[#tr + 1] = { t = now, dArr = dArr, hw = hw, gap = gap, sig = curSig,
                                m = hwS - math.abs(dArr - rateUse * lead), e = errBar,
                                lead = lead }
                if #tr > 80 then table.remove(tr, 1) end
                if Hub.qteStats and clicks > 1 and gap < (Hub.qteStats.minGap or 99) then
                    Hub.qteStats.minGap = gap
                end
                Q.Click:FireServer(tick())
            end
        end

        task.wait()
    end

    hb:Disconnect()
    if clickConn then pcall(function() clickConn:Disconnect() end) end
    task.wait(0.1)

    local span = math.max(os.clock() - t0, 0.001)
    local rate = clicks > 0 and (hits / clicks * 100) or 0
    log(("qte: %d trials, marker %.1f upd/s, max gap %.0fms, clicks=%d hits=%d misses=%d (%.0f%%), best streak %d, trials with no shot %d, aim point %.2f, lead %.0fms"):format(
        trialNo, upd / span, maxGap * 1000, clicks, hits, misses, rate, bestStreak, noShot, edge, lead * 1000))
    -- the two numbers that say whether a phantom click got through: the
    -- shortest gap between two clicks (must never be under MinClickGap) and the
    -- most times a zone moved while a click was in flight (the death animation)
    log(("qte: shortest gap between clicks %.0fms (floor %.0fms), zone moved up to %d times during a click")
        :format((Hub.qteStats and Hub.qteStats.minGap or 99) * 1000, CFG.MinClickGap * 1000,
                Hub.qteStats and Hub.qteStats.anim or 0))
    -- frames where the marker was on the green and no click went out, by reason
    if Hub.qteStats and Hub.qteStats.why then
        local w, parts = Hub.qteStats.why, {}
        for _, k in ipairs({ "frozen", "thinZone", "gap", "noTrial", "stale", "early", "late", "errBar" }) do
            if (w[k] or 0) > 0 then parts[#parts + 1] = ("%s=%d"):format(k, w[k]) end
        end
        if #parts > 0 then log("qte: declined on the green: " .. table.concat(parts, " ")) end
    end
    -- THE SEPARATION TEST. every click leaves a margin m = hw - dArr between
    -- where it lands and the edge it came from, and a click misses on that side
    -- when the real error beat m. so if the tightest HIT margin is above the
    -- widest MISS margin, margin is the whole story and the AIMD bar is the
    -- right knob - it just has to sit between the two. if a miss shows up at a
    -- margin a hit survived, the error is not the only variable and the aim or
    -- the rate fit is wrong instead
    local tr2 = Hub.qteTrace
    if tr2 then
        local hitMin, missMax, n = nil, nil, 0
        for _, s in ipairs(tr2) do
            if s.m and s.hit then
                n = n + 1
                if s.hit == 1 then
                    if not hitMin or s.m < hitMin then hitMin = s.m end
                else
                    if not missMax or s.m > missMax then missMax = s.m end
                end
            end
        end
        if n > 0 then
            log(("qte: judged margin - tightest hit %.3f, widest miss %s (lead %.0fms)")
                :format(hitMin or -1, missMax and ("%.3f"):format(missMax) or "none", lead * 1000))
        end
    end
    if frames > 0 then
        log(("qte: frame %.1fms avg, %.0fms worst over %d frames"):format(
            frameSum / frames * 1000, frameMax * 1000, frames))
    end
    getgenv().STD_Edge = edge
    getgenv().STD_Lead = lead

    -- release the one-loop lock. every exit from this function goes through
    -- here, and the token check at the top covers the one that errors instead
    Solver.running = false
    Solver.runToken = nil
    Solver.beat = 0

    return hits, misses, clicks
end

--=============================================================
-- ROTATION (Justice Sorcerer: cast + refill the gauge)
--=============================================================
local function runQTERotation(entry, token, maxTrials)
    local trials = 0
    local noQTE = 0
    maxTrials = maxTrials or CFG.MaxTrials
    -- the gauge is still full from the last fill until the execution is spent.
    -- the driver restarts this function every couple of seconds, so remember
    -- the state on entry and only announce a fill that actually just happened -
    -- otherwise "FULL ... EXECUTION" toasts forever.
    local wasFull = points() >= CFG.TargetPts
    -- the auto driver passes a huge cap; show it as "inf" instead of 2147483647
    local capTxt = maxTrials >= 1000000 and "inf" or tostring(maxTrials)
    if not wasFull then
        log(("QTE farm start: %.2f/%.0f, cap %s"):format(points(), CFG.TargetPts, capTxt))
    end

    while points() < CFG.TargetPts and trials < maxTrials do
        if Solver.stop or Solver.token ~= token then
            log("QTE farm: stopped by user")
            if Hub.setStatus then Hub.setStatus("farm stopped", "warn") end
            return false
        end

        trials = trials + 1
        if Hub.setStatus then
            Hub.setStatus(("trial %d/%s   %.1f/%.0f"):format(
                trials, capTxt, points(), CFG.TargetPts), nil)
        end

        -- a domain that ended without filling the gauge can leave the tower
        -- pinned at IsCasting=true with the cooldown frozen. the server then
        -- ignores every cast until the tower / match resets, so say so instead
        -- of firing into the void six times.
        local cfg0 = entry.model:FindFirstChild("Config")
        local cast0 = cfg0 and cfg0:FindFirstChild("IsCasting")
        local cd0 = cfg0 and cdValueOf(entry.spec, cfg0)
        -- a domain that is still up cannot be cast again, and firing the remote
        -- into it every 1.5s is what made the log look like a machine gun while
        -- nothing happened. wait for it to finish, then cast once
        local act0 = cfg0 and cfg0:FindFirstChild("DomainActive")
        if act0 and act0:IsA("BoolValue") and act0.Value
            and not (QTE and QTE.InQTE.Value) then
            log("QTE farm: domain still active with no QTE - waiting for it to end")
            local wt = 0
            while wt < CFG.UnstickWait and act0.Value do
                if Solver.stop or Solver.token ~= token then return false end
                task.wait(0.5)
                wt = wt + 0.5
            end
            if act0.Value then
                log("QTE farm: domain never ended - start a wave or replace the tower")
                if Hub.setStatus then Hub.setStatus("domain never ended - start a wave", "bad") end
                return false
            end
        end
        if cast0 and cast0:IsA("BoolValue") and cast0.Value
            and cd0 and cd0:IsA("ValueBase") and cd0.Value > 0
            and not (QTE and QTE.InQTE.Value) then
            -- it does clear on its own once the match is actually running
            -- (the tower's server loop has to tick), so give it a window
            log(("QTE farm: domain stuck (IsCasting=true, cd=%s) - waiting for the server loop"):format(tostring(cd0.Value)))
            if Hub.setStatus then Hub.setStatus("domain stuck - waiting", "warn") end
            local wt = 0
            while wt < CFG.UnstickWait and cast0.Value and cd0.Value > 0 do
                if Solver.stop or Solver.token ~= token then return false end
                task.wait(0.5)
                wt = wt + 0.5
            end
            if cast0.Value and cd0.Value > 0 then
                log("QTE farm: still stuck - start a wave or replace the tower")
                if Hub.setStatus then Hub.setStatus("domain stuck - start a wave", "bad") end
                return false
            end
            log("QTE farm: domain unstuck")
        end

        local ok, msg = castEntry(entry)
        if not ok then
            log("cast failed: " .. tostring(msg))
            if Hub.setStatus then Hub.setStatus(msg, "bad") end
            return false
        end
        -- a silent cast is not a refusal. if a QTE is up, the domain is up, and
        -- the only thing "silent" ever meant was that none of the tower's values
        -- happened to move inside the watch window
        if entry.lastAccepted == false then
            local q = qteFolder()
            if q and q.InQTE and q.InQTE.Value then
                log("QTE farm: cast was silent but a QTE is live - carrying on")
            else
                log("QTE farm: server refused the domain - level gated, stop")
                if Hub.setStatus then Hub.setStatus("domain refused by server", "bad") end
                return false
            end
        end

        if waitQTE(CFG.WaitForQTE) then
            noQTE = 0
            local h, m, c = playTrial()
            log(("trial %d: clicks=%d hits=%d misses=%d -> %.2f/%.0f"):format(
                trials, c, h, m, points(), CFG.TargetPts))
            if Hub.setStatus then
                -- no kind on purpose: this fires every trial, and a toast per
                -- trial is exactly the spam we are killing
                Hub.setStatus(("trial %d/%s   %.1f/%.0f   (h%d m%d)"):format(
                    trials, capTxt, points(), CFG.TargetPts, h, m), nil)
            end
        else
            noQTE = noQTE + 1
            log(("trial %d: no QTE appeared (%d)"):format(trials, noQTE))
            if noQTE >= 2 then
                log("QTE farm: the minigame never starts, stop")
                if Hub.setStatus then Hub.setStatus("no QTE - domain not firing", "bad") end
                return false
            end
        end

        -- wait out whatever cooldown is left instead of a blind fixed pause,
        -- so the next cast is not a fresh forced reset every time
        local cfg = entry.model:FindFirstChild("Config")
        local cd = cfg and cdValueOf(entry.spec, cfg)
        local waited = 0
        while cd and cd:IsA("ValueBase") and cd.Value > 0 and waited < 20 do
            if Solver.stop or Solver.token ~= token then break end
            task.wait(0.25)
            waited = waited + 0.25
        end
        if waited == 0 then task.wait(1) end
    end

    if points() >= CFG.TargetPts then
        if not wasFull then
            log(("GAUGE FULL %.2f/%.0f - execution armed"):format(points(), CFG.TargetPts))
            if Hub.setStatus then
                Hub.setStatus(("FULL %.1f/%.0f - EXECUTION"):format(points(), CFG.TargetPts), "good")
            end
        end
        return true
    end

    if Hub.setStatus then
        Hub.setStatus(("farm done at %.1f/%.0f"):format(points(), CFG.TargetPts), "warn")
    end
    return false
end

--=============================================================
-- PUBLIC ACTIONS
--=============================================================
local farmBtn
local function stopFarm()
    Solver.stop = true
    Solver.token = Solver.token + 1
    Solver.busy = false
    Solver.active = false
    if farmBtn then farmBtn.Text = "FARM QTE" end
    if Hub.setStatus then Hub.setStatus("farm stopped", "warn") end
    log("farm stop requested")
end

-- one domain cast + one solve of the minigame it opens. never loops,
-- never re-fires: that is what FARM is for.
local function solveOnce(entry)
    -- A CAST THAT IS STILL WAITING FOR ITS MINIGAME HAS NOT FAILED YET.
    -- without this, auto cast re-fired the same domain every CastDelay while the
    -- first attempt was still waiting for the QTE it had just asked for: one
    -- refusal became three casts and three `no QTE: server refused` lines, and
    -- every one of them bumped the token and cancelled the previous wait. the
    -- gate is the wait itself, not a timer guess - it expires the moment the
    -- thread that set it finishes
    if Solver.waitUntil and os.clock() < Solver.waitUntil then return false end
    -- a solver thread that died between pcall and its cleanup used to leave
    -- busy=true forever, which is exactly "auto qte stops working after you
    -- flip it off and on". clear a stale lock instead of refusing to run.
    if Solver.busy then
        local live = QTE and QTE.InQTE.Value
        if live then
            if Hub.setStatus then Hub.setStatus("QTE solver is already running", "warn") end
            return false
        end
        log("qte: clearing stale solver lock")
        Solver.busy = false
        Solver.active = false
        Solver.token = Solver.token + 1
    end
    -- and the other lock. busy and running are two different flags, and this
    -- function only ever checked its own - so a domain cast here could bump the
    -- token under a playTrial that was already looping, which is how two loops
    -- ended up on the same bar
    if Solver.running and (os.clock() - (Solver.beat or 0)) < SOLVER_STALE then
        log("qte: solveOnce refused - a trial loop is already running")
        if Hub.setStatus then Hub.setStatus("a QTE is already being solved", "warn") end
        return false
    end
    -- clear a stop flag left over from a previous FARM, otherwise playTrial
    -- bails out on its first iteration and the solver looks dead
    Solver.stop = false
    local ok, msg = castEntry(entry)
    if not ok then
        log("cast failed: " .. tostring(msg))
        if Hub.setStatus then Hub.setStatus(msg, "bad") end
        return false
    end
    log(("%s %s fired (%s)"):format(entry.spec.label, entry.spec.ability, tostring(msg)))

    Solver.busy = true
    Solver.active = true
    Solver.token = Solver.token + 1
    local token = Solver.token
    local runId = token
    Solver.busyRun = runId
    -- if the server never acknowledged the cast there is no point sitting in a
    -- 26s wait, the domain simply is not coming
    local waitFor = entry.lastAccepted == false and 4 or CFG.WaitForQTE
    -- capped at 8s on purpose: the thread below keeps waiting the full
    -- WaitForQTE in case the domain opens slowly, but a cast that has produced
    -- nothing in 8s has almost certainly been refused, and blocking auto cast
    -- for 26s after one silent cast is worse than one wasted retry
    Solver.waitUntil = os.clock() + math.min(waitFor, 8) + 0.5
    local thread = task.spawn(function()
        pcall(function()
            if not waitQTE(waitFor) then
                log(entry.lastAccepted == false
                    and "no QTE: server refused the domain"
                    or "no QTE appeared")
                if Hub.setStatus then
                    Hub.setStatus(entry.lastAccepted == false
                        and "domain refused by server"
                        or "domain fired, no QTE", "warn")
                end
                return
            end
            if Solver.token ~= token then return end
            local h, m, c = playTrial()
            log(("qte: clicks=%d hits=%d misses=%d -> %.2f/%.0f"):format(
                c, h, m, points(), CFG.TargetPts))
            if Hub.setStatus then
                Hub.setStatus(("qte h%d m%d   %.1f/%.0f"):format(
                    h, m, points(), CFG.TargetPts), "good")
            end
        end)
        -- whoever set busy owns it. the old check was "does the token still
        -- match", which meant any bump from anywhere - the farm driver, the
        -- FARM button, a second castAll - left busy=true for the rest of the
        -- session. every later attempt then read "the solver is already
        -- running" and returned, which is the exact shape of "solves one
        -- minigame and then never again"
        if Solver.busyRun == runId then
            Solver.busy = false
            Solver.active = false
        end
        Solver.waitUntil = nil
        flushLog()
    end)
    table.insert(Hub.threads, thread)
    return true
end

-- replay path: the macro already fired the domain, so casting again would double
-- it. all that is left is the minigame the cast opened
local function solveOnly()
    if not QTE then return false end
    if Solver.busy then return false end
    Solver.stop = false
    Solver.busy = true
    Solver.active = true
    Solver.token = Solver.token + 1
    local token = Solver.token
    local runId = token
    Solver.busyRun = runId
    table.insert(Hub.threads, task.spawn(function()
        pcall(function()
            if not waitQTE(CFG.WaitForQTE) then
                log("qte: none appeared after replay")
                return
            end
            if Solver.token ~= token then return end
            local h, m, c = playTrial()
            log(("qte replay: clicks=%d hits=%d misses=%d -> %.2f/%.0f"):format(
                c, h, m, points(), CFG.TargetPts))
            if Hub.setStatus then
                Hub.setStatus(("qte h%d m%d   %.1f/%.0f"):format(
                    h, m, points(), CFG.TargetPts), "good")
            end
        end)
        if Solver.busyRun == runId then
            Solver.busy = false
            Solver.active = false
        end
    end))
    return true
end
Hub.solveOnly = solveOnly

local function pressEntry(entry)
    if entry.blocked then
        local msg = ("%s: %s - upgrade the tower, nothing to force"):format(
            entry.spec.label, entry.blocked)
        log(msg)
        if Hub.setStatus then Hub.setStatus(msg, "bad") end
        return
    end

    if entry.spec.qte and CFG.AutoSolve then
        -- ONLY WHILE THE FARM IS ACTUALLY ROTATING DOMAINS.
        -- the farm driver casts this ability itself, so letting the auto-cast
        -- loop press the same button produced `DOMAIN fired (silent)` +
        -- `no QTE: server refused` every 1.2s, thirty times in a row: two
        -- loops, both casting, neither getting a QTE.
        -- The first attempt at this guard asked "does a driver exist" instead
        -- and killed auto cast outright - a driver exists whenever the farm is
        -- on, including when it is sitting idle because the gauge is already
        -- full or because it cannot find a tower. In "selected" mode that meant
        -- the one tower the user had picked stopped casting entirely. The flag
        -- is set only around the rotation itself, so idle means idle
        if Solver.farming then return end
        solveOnce(entry)
        return
    end

    local ok, msg = castEntry(entry)
    if ok then
        log(("%s %s fired (%s)"):format(entry.spec.label, entry.spec.ability, tostring(msg)))
        if Hub.setStatus then
            local extra
            if entry.spec.charge then
                extra = "  (charge gated)"
            elseif entry.lastAccepted then
                extra = "  server OK"
            else
                extra = "  no server response - level gated"
            end
            Hub.setStatus(("%s  %s  FIRED%s"):format(entry.spec.label, entry.spec.ability, extra),
                entry.lastAccepted and "good" or "bad")
        end
    else
        log("cast failed: " .. tostring(msg))
        if Hub.setStatus then Hub.setStatus(msg, "bad") end
    end
end

local function castAll()
    local list = scanTowers()
    if #list == 0 then
        if Hub.setStatus then Hub.setStatus("no ability towers placed", "bad") end
        return
    end
    local n, skipped, justice = 0, 0, nil
    for _, e in ipairs(list) do
        if e.spec.qte then
            justice = e
        elseif e.blocked then
            skipped = skipped + 1
            log(("%s skipped: %s"):format(e.spec.label, e.blocked))
        else
            if castEntry(e) then n = n + 1 end
        end
    end
    log(("cast all: %d fired, %d locked"):format(n, skipped))
    if justice and CFG.AutoSolve then
        pressEntry(justice)
    elseif justice then
        castEntry(justice)
    end
    if Hub.setStatus then
        local extra = skipped > 0 and (", %d locked"):format(skipped) or ""
        Hub.setStatus(("%d ability tower(s) fired%s"):format(n, extra), "good")
    end
end

-- repeated cast -> solve -> wait cycle until the gauge fills.
-- always stoppable: press FARM again (or flip AUTO QTE off).
local function farmQTE()
    if Solver.busy then
        stopFarm()
        return
    end
    local list = scanTowers()
    local justice
    for _, e in ipairs(list) do
        if e.spec.qte and not e.blocked then justice = e end
    end
    if not justice then
        if Hub.setStatus then Hub.setStatus("no Justice Sorcerer on the map", "bad") end
        return
    end

    Solver.stop = false
    Solver.token = Solver.token + 1
    Solver.busy = true
    Solver.active = true
    -- a manual FARM rotation owns the QTE ability exactly like the auto driver
    -- does, so pressEntry has to keep its hands off it here too. it also gives
    -- ensureFarm below something to test that is not the busy flag
    Solver.farming = true
    local token = Solver.token

    local thread = task.spawn(function()
        pcall(function() runQTERotation(justice, token, CFG.MaxTrials) end)
        Solver.farming = false
        Solver.busy = false
        Solver.active = false
        if farmBtn then farmBtn.Text = "FARM QTE" end
        flushLog()
    end)
    table.insert(Hub.threads, thread)
    if farmBtn then farmBtn.Text = "FARM QTE: RUNNING - click to stop" end
end

-- "MAKE SURE A FARM IS RUNNING", NOT "TOGGLE A FARM".
-- farmQTE reads a second call while busy as "stop" - that is what makes the
-- FARM button a toggle. The anniversary driver calls this every couple of
-- seconds to keep the gauge filling, and under toggle semantics it stopped the
-- farm it had started on the very next tick, then started it again, and the
-- minigame solved once or twice and appeared to die. This leaves a live
-- rotation alone and only clears a busy flag that has nothing behind it.
function Hub.ensureFarm()
    if Solver.busy then
        if Solver.farming or Solver.running then return false end
        -- a cast that is still waiting for its minigame has not failed, and
        -- stealing its flag here is how two loops end up on one bar
        if Solver.waitUntil and os.clock() < Solver.waitUntil then return false end
        log("QTE farm: busy flag with no live rotation behind it - clearing")
        Solver.busy = false
        Solver.active = false
    end
    farmQTE()
    return true
end

--=============================================================
-- UI
--=============================================================
local COL = {
    bg     = Color3.fromRGB(18, 16, 24),
    panel  = Color3.fromRGB(28, 24, 36),
    panel2 = Color3.fromRGB(36, 30, 48),
    stroke = Color3.fromRGB(84, 66, 128),
    accent = Color3.fromRGB(150, 96, 240),
    text   = Color3.fromRGB(235, 230, 245),
    dim    = Color3.fromRGB(150, 143, 168),
    good   = Color3.fromRGB(96, 220, 140),
    bad    = Color3.fromRGB(240, 96, 110),
    warn   = Color3.fromRGB(240, 190, 90),
}

--=============================================================
-- OBSIDIAN UI
--=============================================================
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()

-- the library keeps these on itself, not in getgenv
local Options = Library.Options
local Toggles = Library.Toggles

Library.ShowToggleFrameInKeybinds = true

local Window = Library:CreateWindow({
    Title = "STD HUB",
    Footer = "sorcerer tower defense  ·  v7",
    NotifySide = "Right",
    ShowCustomCursor = false,
    ToggleKeybind = Enum.KeyCode.RightShift,
})
Hub.window = Window

local Tabs = {
    Abil   = Window:AddTab("Misc", "swords"),
    Gaunt  = Window:AddTab("Gauntlet",  "crosshair"),
    Raids  = Window:AddTab("Raids",     "skull"),
    Casino = Window:AddTab("Casino",    "dices"),
    Sukuna = Window:AddTab("Sukuna",    "flame"),
    Story  = Window:AddTab("Story",     "book-open"),
    Place  = Window:AddTab("Place",     "map-pin"),
    Culling = Window:AddTab("Culling",  "map-pin"),
    Candy  = Window:AddTab("Candy",     "gift"),
    Event  = Window:AddTab("Event",     "clock"),
    Units  = Window:AddTab("Units",     "zap"),
    Macros = Window:AddTab("Macros",    "bot"),
    Cfg    = Window:AddTab("Config",    "save"),
}

local function notify(text, time)
    if CFG.Notify == false then return end
    pcall(function()
        Library:Notify({ Title = "STD", Description = tostring(text), Time = time or 4 })
    end)
end

-- The caster and the QTE loop set a status every tick, and every "good" status
-- used to fire a toast - that is what buried the screen in FULL/EXECUTION
-- popups. Same text is now dropped for 20 s, and nothing fires faster than
-- once every 1.5 s.
local lastToast, lastToastAt = nil, -99
local function toast(text, time)
    if CFG.Notify == false then return end
    local t = tostring(text)
    local now = os.clock()
    if t == lastToast and now - lastToastAt < 20 then return end
    if now - lastToastAt < 1.5 then return end
    lastToast, lastToastAt = t, now
    notify(t, time)
end
Hub.toast = toast

-- core code calls Hub.setStatus(...) with a kind, keep the signature
local function setStatus(txt, kind)
    Hub._status = txt
    if Hub._statusLabel then pcall(function() Hub._statusLabel:SetText(tostring(txt)) end) end
    if kind == "bad" or kind == "good" then toast(txt, 3) end
end
Hub.setStatus = setStatus

--=============================================================
-- AUTO DRIVER
--   CFG.AutoSolve on  ->  cast the domain and keep solving trials
--   until the gauge fills, then immediately start the next one.
--   flipping the toggle off kills the whole loop.
--=============================================================
function Hub.startAuto()
    if Solver.driver then return end
    Solver.stop = false
    Solver.token = Solver.token + 1
    -- THE DRIVER'S LIFE IS A GENERATION, NOT THE TOKEN.
    -- The token means "cancel the rotation that is running right now", and six
    -- other paths bump it: solveOnce, solveOnly, castAll, the FARM button,
    -- stopFarm, startAuto itself. The driver used to exit when it saw a token it
    -- did not recognise, so any one of those - including the auto-cast loop
    -- pressing the same Justice Sorcerer while the farm sat in its 2..30s pause
    -- - killed the farm for good. On screen that is "it solves one or two
    -- minigames and then does nothing", with the toggle still reading on.
    -- Only startAuto and stopAuto move the generation now.
    Solver.gen = (Solver.gen or 0) + 1
    local gen = Solver.gen
    Solver.driver = task.spawn(function()
        local fails = 0
        local lastFarmPts = points()
        local saidNoTower = false
        -- every tower model the driver has ever seen, and when it first saw it.
        -- a model that is not in here was just built, so its domain waits.
        local seen = setmetatable({}, { __mode = "k" })
        local seeded = false
        while CFG.AutoSolve and getgenv().STD_Hub == Hub and Solver.gen == gen do
            -- a tower you just built must not pop its domain on the same breath.
            -- Place.spawn stamps freshUntil on every successful placement, and
            -- the seen-table below covers towers placed by the game itself.
            local P = Hub.Place
            if P and P.autoCastHeld and P.autoCastHeld() then
                task.wait(0.4)
                continue
            end
            local towers = scanTowers()
            local now = os.clock()
            local grace = CFG.CastGrace or 8
            if not seeded then
                -- whatever is already on the map when the farm starts is old
                for _, e in ipairs(towers) do seen[e.model] = now - grace end
                seeded = true
            end
            local justice
            for _, e in ipairs(towers) do
                if e.spec.qte and not e.blocked then
                    if not seen[e.model] then seen[e.model] = now end
                    if now - seen[e.model] >= grace then justice = e break end
                end
            end
            if justice then
                saidNoTower = false
                Solver.busy = true
                Solver.active = true
                -- this is the ONLY window in which the auto-cast loop must keep
                -- its hands off the QTE ability, and pressEntry reads it. it has
                -- to be a separate flag from busy/active, because those are also
                -- held by solveOnce and by the driver while it is idle
                Solver.farming = true
                -- A FRESH TOKEN PER ROTATION. the rotation is what a token bump
                -- is allowed to cancel. taking the token once at the top of the
                -- driver meant the second rotation started with a token that
                -- was already stale and returned on its first check - forever.
                -- runQTERotation gets the token that is current RIGHT NOW, so a
                -- cancel costs one rotation and the next one just runs
                local rot = Solver.token
                local ran = false
                local ok = pcall(function() ran = runQTERotation(justice, rot, 2147483647) end)
                Solver.farming = false
                Solver.busy = false
                Solver.active = false
                -- THE RETRY LOOP USED TO BE A MACHINE GUN. runQTERotation
                -- returns false when the server refused the domain, and that
                -- return was thrown away - so `pcall` succeeded, fails reset to
                -- zero, and the whole farm restarted two seconds later. a
                -- refused domain produced `DOMAIN fired (silent)` +
                -- `no QTE: server refused` every 1.5s, twenty times in a row,
                -- which is what the log looked like. the gauge moving is the
                -- only real proof of progress, so that is what resets the
                -- counter; anything else backs off
                if points() > lastFarmPts then
                    fails = 0
                    lastFarmPts = points()
                elseif ok and ran == true then
                    fails = 0
                else
                    fails = fails + 1
                end
                if fails == 3 then
                    log("QTE farm: the domain keeps being refused - backing off to 30s between attempts")
                    if Hub.setStatus then Hub.setStatus("domain refused - backing off", "warn") end
                end
            end
            -- a farm with no tower in the map used to sit there in silence. it is
            -- not an error - the tower is placed by the player - but a farm that
            -- looks dead is worse than one that says why
            if not justice and not saidNoTower then
                saidNoTower = true
                log("QTE farm: no Justice Sorcerer on the map - waiting for one to be placed")
                if Hub.setStatus then Hub.setStatus("QTE farm: place a Justice Sorcerer", "warn") end
            end
            if Solver.gen ~= gen then break end
            -- 2s normally, then 4, 8, 16, 30. a refusal is usually "no wave
            -- running" or a dead tower, and neither is fixed by asking again
            -- sooner - it just fills the log
            local pause = 2
            if fails > 1 then pause = math.min(30, 2 ^ math.min(fails, 5)) end
            task.wait(pause)
        end
        Solver.busy = false
        Solver.active = false
        Solver.farming = false
        Solver.driver = nil
        flushLog()
    end)
    -- a thread that finished before the assignment above - which happens when
    -- CFG.AutoSolve is already false on entry - would otherwise leave a dead
    -- handle in Solver.driver and block every later start
    if Solver.driver and coroutine.status(Solver.driver) == "dead" then
        Solver.driver = nil
    end
    Hub.startSupervisor()
end

-- A DRIVER THAT DIES MUST NOT LEAVE THE TOGGLE LYING.
-- Everything above is supposed to keep the farm alive, and this is the backstop
-- for the case where something still kills it: an error outside the pcall, a
-- cancelled rotation, a path that bumps the generation by accident. While
-- CFG.AutoSolve is true, a missing driver is put back within a second. "on"
-- now means on, which is what the toggle has always claimed.
function Hub.startSupervisor()
    if Solver.supervisor then return end
    Solver.supervisor = task.spawn(function()
        local restarts = 0
        while getgenv().STD_Hub == Hub do
            task.wait(1)
            if CFG.AutoSolve and not Solver.driver then
                restarts = restarts + 1
                -- a farm that cannot start logs its own reason; this line only
                -- has to say that the restart happened, and not sixty times a
                -- minute when the reason is permanent
                if restarts <= 3 or restarts % 60 == 0 then
                    log(("QTE farm: the driver was not running - restarting it (%d)"):format(restarts))
                end
                Hub.startAuto()
            end
        end
        Solver.supervisor = nil
    end)
end

function Hub.stopAuto()
    Solver.stop = true
    Solver.token = Solver.token + 1
    -- the generation is what the driver actually watches, and it has to move
    -- before the cancel so a driver that is mid-pcall cannot loop once more
    Solver.gen = (Solver.gen or 0) + 1
    if Solver.driver then pcall(function() task.cancel(Solver.driver) end) end
    Solver.driver = nil
    Solver.busy = false
    Solver.active = false
    -- a cancelled driver never reaches the line that clears these, and a stuck
    -- flag would leave the auto-cast loop permanently unable to press the QTE
    -- ability - which is exactly how "auto cast stopped working" looked
    Solver.farming = false
    Solver.waitUntil = nil
    flushLog()
end

--=============================================================
-- REMOTE SURFACE
--=============================================================
-- a handle so a run can be started and watched from the executor console (or
-- over MCP) without clicking through the UI. it only touches flags the driver
-- already reads, so nothing here can put the hub into a state the UI could not.
Hub.api = {
    verbose = function(on) Hub.verbose = on == true return Hub.verbose == true end,
    farm = function(on)
        on = on == true
        CFG.AutoSolve = on
        if on then Hub.startAuto() else Hub.stopAuto() end
        return CFG.AutoSolve
    end,
    stats = function() return Hub.qteStats end,
    -- run the solver against whatever QTE is live right now, with no farm
    -- driver around it. returns hits, misses, clicks. this is how the gate gets
    -- tested against a real domain instead of a screenshot
    solve = function()
        -- stopAuto() sets this, and playTrial treats it as "the user cancelled".
        -- a direct solve request is the opposite of a cancel, so clear it here -
        -- otherwise the loop breaks on its first line and reports 0 trials
        Solver.stop = false
        return playTrial()
    end,
    points = function() return points() end,
    inqte = function() local q = qteFolder() return q ~= nil and q.InQTE ~= nil and q.InQTE.Value end,
    cfg = function() return CFG end,
    band = function() return { edge = getgenv().STD_Edge } end,
    -- every click of the last domain, oldest first: t, dArr, hw, gap since the
    -- previous click, the zone signature it was fired into, and - once judged -
    -- the hit flag, how many times the zone moved while it was in flight, and
    -- the round trip. a phantom click is a `gap` under MinClickGap
    trace = function() return Hub.qteTrace end,
}

--=============================================================
-- TAB 1 : ABILITIES
--=============================================================
local abilBox = Tabs.Abil:AddLeftGroupbox("Cast", "zap")
local qteBox  = Tabs.Abil:AddRightGroupbox("QTE", "timer")

--=============================================================
-- HOTBAR PLACEMENT (misc tab)
--=============================================================
-- The game builds a clone of the tower in workspace the moment you pick a unit
-- in the hotbar (keys 1-5). With this on, the hub watches for that clone, locks
-- onto the same unit, and the next left click builds it wherever the cursor is
-- pointing - no pad, no range, no green/red check. The clone is removed after a
-- successful placement so the game cannot build a second one on the same click.
local hotBox = Tabs.Abil:AddRightGroupbox("Hotbar placement", "mouse-pointer")

hotBox:AddToggle("PlaceHotbar", {
    Text = "place from hotbar anywhere",
    Default = false,
    Tooltip = "pick a unit with 1-5, then left click anywhere. works during macro recording too. " ..
              "clicks on this window are ignored",
    Callback = function(v)
        local p = Hub.Place
        if not p then return end
        p.setAutoHotbar(v)
        if v then
            setStatus("hotbar placement ON - pick a unit with 1-5, then click the world", "good")
        else
            setStatus("hotbar placement OFF - clicks no longer build anything", "info")
        end
    end,
})

hotBox:AddLabel("pick a unit with 1-5, then click", true)
hotBox:AddLabel("no build pad, no area check", true)
hotBox:AddLabel("the game's own clone is cleaned up after", true)

--=============================================================
-- BOOGIE : Celebration on every copy at once
--=============================================================
-- Celebration is gated on Config.Celebration, which only flips true at tier 6.
-- The unlock below is the same local reset the ability caster uses: it clears a
-- stale cooldown and the flag so the icon is not stuck, but the cast itself is
-- the server's call - if the tower is below tier 6 the server drops it.
local Boogie = {}
Hub.Boogie = Boogie

Boogie.key = Enum.KeyCode.B
Boogie._conn = nil

function Boogie.list()
    local found = {}
    local towers = workspace:FindFirstChild("Towers")
    if not towers then return found end
    for _, m in ipairs(towers:GetChildren()) do
        if string.find(m.Name, "Boogie") then table.insert(found, m) end
    end
    return found
end

function Boogie.unlock(m)
    local cfg = m:FindFirstChild("Config")
    if not cfg then return end
    local flag = cfg:FindFirstChild("Celebration")
    if flag and flag:IsA("BoolValue") and not flag.Value then
        pcall(function() flag.Value = true end)
    end
    local cd = cfg:FindFirstChild("CelebrationRemCd")
    if cd and cd:IsA("ValueBase") and cd.Value ~= 0 then
        pcall(function() cd.Value = 0 end)
    end
    local casting = cfg:FindFirstChild("IsCasting")
    if casting and casting:IsA("BoolValue") and casting.Value then
        pcall(function() casting.Value = false end)
    end
end

function Boogie.fire()
    local rem = resolveRemote("Towers.BoogieSorcererAnniversary.Celebration")
    if not rem then
        setStatus("boogie: Celebration remote missing - are you in a match?", "bad")
        return 0
    end
    local extra = resolveRemote("Towers.BoogieSorcererAnniversary.SynergyCutscene")
    local list = Boogie.list()
    if #list == 0 then
        setStatus("boogie: no Boogie Sorcerer on the map", "warn")
        return 0
    end
    local n = 0
    for _, m in ipairs(list) do
        Boogie.unlock(m)
        pcall(function() rem:FireServer(m) end)
        if extra then pcall(function() extra:FireServer(m) end) end
        n = n + 1
    end
    if Hub._boogieLabel then
        pcall(function() Hub._boogieLabel:SetText(("boogies: %d"):format(n)) end)
    end
    setStatus(("boogie: Celebration fired on %d copy(ies)"):format(n), "good")
    return n
end

function Boogie.setKey(on)
    if Boogie._conn then
        pcall(function() Boogie._conn:Disconnect() end)
        Boogie._conn = nil
    end
    if not on then return end
    Boogie._conn = UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode ~= Boogie.key then return end
        if getgenv().STD_Hub ~= Hub then return end
        if UIS:GetFocusedTextBox() then return end
        Boogie.fire()
    end)
end

local boogieBox = Tabs.Abil:AddRightGroupbox("Boogie", "party-popper")

boogieBox:AddButton({
    Text = "CELEBRATION - ALL COPIES",
    Func = function() Boogie.fire() end,
    Tooltip = "fires Celebration on every Boogie Sorcerer on the map at once. " ..
              "the server only honours it from tier 6",
})

boogieBox:AddToggle("BoogieKey", {
    Text = "keybind (B)",
    Default = false,
    Tooltip = "press B in game to fire Celebration on every Boogie copy",
    Callback = function(v)
        Boogie.setKey(v)
        setStatus(v and "boogie keybind ON - press B" or "boogie keybind OFF", nil)
    end,
})

boogieBox:AddButton({
    Text = "COUNT BOOGIES",
    Func = function()
        local n = #Boogie.list()
        if Hub._boogieLabel then
            pcall(function() Hub._boogieLabel:SetText(("boogies: %d"):format(n)) end)
        end
        setStatus(("boogie: %d on the map"):format(n), nil)
    end,
})

Hub._boogieLabel = boogieBox:AddLabel("boogies: -", true)

task.spawn(function()
    while getgenv().STD_Hub == Hub do
        local n = #Boogie.list()
        if Hub._boogieLabel then
            pcall(function() Hub._boogieLabel:SetText(("boogies: %d"):format(n)) end)
        end
        task.wait(1.5)
    end
end)

--=============================================================
-- DAILY CALENDAR + QUESTS : auto claim
--=============================================================
-- Both are plain remote calls, the same two the game's own GUI makes:
--   Remotes.Anniversary.ClaimDaily : FireServer(dayIndex)
--   Remotes.Quests.ClaimQuest      : FireServer(category, questName)
-- The server does all the validation (day lock, progress, already claimed),
-- so firing blindly is pointless: we only send what the local state says is
-- finished and unclaimed, and after three refusals we stop retrying that one
-- instead of hammering the remote every cycle.
local Claim = {}
Hub.Claim = Claim

Claim.autoDaily  = false
Claim.autoQuests = false
Claim.autoChain  = false
Claim.interval   = 15
Claim._thread    = nil
Claim._state     = nil
Claim._qcfg      = nil
Claim._tries     = {}
Claim._maxTries  = 3
Claim._acfg      = nil

-- event categories first, then anything else the config happens to ship
local QUEST_ORDER = {
    "Anniversary", "Daily", "Weekly", "Sukuna", "Hakari", "Casino",
    "Achievements", "Summer", "Christmas25", "Xmass", "Halloween",
}

local function stateMod()
    if Claim._state then return Claim._state end
    local ok, mod = pcall(function() return require(RS.Client.State) end)
    if ok and mod then Claim._state = mod end
    return Claim._state
end

function Claim.data()
    local mod = stateMod()
    if not mod then return nil end
    local ok, d = pcall(function() return mod.GetData() end)
    if ok and type(d) == "table" then return d end
    return nil
end

local function questConfig()
    if Claim._qcfg then return Claim._qcfg end
    local ok, mod = pcall(function() return require(RS.Configs.Quests) end)
    if ok and mod and type(mod.Config) == "table" then Claim._qcfg = mod.Config end
    return Claim._qcfg
end

local function annivConfig()
    if Claim._acfg then return Claim._acfg end
    local ok, mod = pcall(function() return require(RS.Configs.Anniversary) end)
    if ok and mod and type(mod.Config) == "table" then Claim._acfg = mod.Config end
    return Claim._acfg
end

local function categories(cfg)
    local out = {}
    for _, c in ipairs(QUEST_ORDER) do
        if cfg[c] then table.insert(out, c) end
    end
    for c in pairs(cfg) do
        local known = false
        for _, k in ipairs(QUEST_ORDER) do
            if k == c then known = true break end
        end
        if not known then table.insert(out, c) end
    end
    return out
end

-- every finished-but-unclaimed quest, optionally without firing
function Claim.claimQuests(dry)
    local rem = resolveRemote("Quests.ClaimQuest")
    local d, cfg = Claim.data(), questConfig()
    if not rem or not d or not cfg or not d.Quests then return 0, 0 end
    local ready, fired = 0, 0
    for _, cat in ipairs(categories(cfg)) do
        local list, cur = cfg[cat], d.Quests[cat]
        if list and cur then
            local names = {}
            for name in pairs(list) do table.insert(names, name) end
            table.sort(names)
            for _, name in ipairs(names) do
                local conf, e = list[name], cur[name]
                local need = tonumber(conf and conf.Value) or 0
                local prog = tonumber(e and e.Progress) or 0
                if need > 0 and prog >= need and not (e and e.Claimed) then
                    ready = ready + 1
                    local key = cat .. "/" .. name
                    if not dry and (Claim._tries[key] or 0) < Claim._maxTries then
                        Claim._tries[key] = (Claim._tries[key] or 0) + 1
                        pcall(function() rem:FireServer(cat, name) end)
                        fired = fired + 1
                        task.wait(0.25)
                    end
                end
            end
        end
    end
    return ready, fired
end

-- the anniversary story chain: ClaimTutorial takes the current step index
function Claim.claimQuestline(dry)
    local rem = resolveRemote("Anniversary.ClaimTutorial")
    local d = Claim.data()
    local cfg = annivConfig()
    local ql = d and d.Anniversary and d.Anniversary.Questline
    if not rem or not ql or not cfg then return 0, 0 end
    if ql.Finished then return 0, 0 end
    local cur = tonumber(ql.Current) or 1
    local list = cfg.Quests
    local need = list and list[cur] and tonumber(list[cur].Value) or 0
    local e = ql.Quests and ql.Quests[cur]
    local prog = tonumber(e and e.Progress) or 0
    if need <= 0 or not e or e.Claimed or prog < need then return 0, 0 end
    local key = "chain/" .. cur
    if dry then return 1, 0 end
    if (Claim._tries[key] or 0) >= Claim._maxTries then return 1, 0 end
    Claim._tries[key] = (Claim._tries[key] or 0) + 1
    pcall(function() rem:FireServer(cur) end)
    task.wait(0.3)
    return 1, 1
end

-- calendar: day N unlocks 24h after the refresh, so day 1 is the only free one.
-- in auto mode we only ever send the next locked day - one request per cycle,
-- not twenty. force is for the manual button, where trying them all is the
-- whole point (the server refuses the locked ones without complaining).
function Claim.claimDaily(force)
    local rem = resolveRemote("Anniversary.ClaimDaily")
    local d = Claim.data()
    local dr = d and d.Anniversary and d.Anniversary.DailyRewards
    if not rem or not dr or type(dr.Rewards) ~= "table" then return 0 end

    if Claim._drStamp ~= dr.LastRefresh then
        Claim._drStamp = dr.LastRefresh
        for k in pairs(Claim._tries) do
            if tostring(k):find("^day/") then Claim._tries[k] = nil end
        end
    end

    local current = tonumber(dr.Current) or 0
    local open = {}
    for i, got in pairs(dr.Rewards) do
        local n = tonumber(i)
        if n and not got then table.insert(open, n) end
    end
    table.sort(open)
    if #open == 0 then return 0 end

    local queue = {}
    if force then
        queue = open
    else
        for _, i in ipairs(open) do
            if i <= current then table.insert(queue, i) end
        end
    end

    local fired = 0
    for _, i in ipairs(queue) do
        local key = "day/" .. i
        if (Claim._tries[key] or 0) < Claim._maxTries then
            Claim._tries[key] = (Claim._tries[key] or 0) + 1
            pcall(function() rem:FireServer(i) end)
            fired = fired + 1
            task.wait(0.3)
        end
    end

    if not force and fired == 0 and #open > 0 and open[1] == current + 1 then
        local since = os.time() - (tonumber(dr.LastRefresh) or os.time())
        if since >= 86400 then
            local stamp = "probe/" .. open[1]
            if os.clock() - (Claim._tries[stamp] or -1e9) > 30 then
                Claim._tries[stamp] = os.clock()
                pcall(function() rem:FireServer(open[1]) end)
                fired = 1
            end
        end
    end
    return fired
end

function Claim.summary()
    local d, cfg = Claim.data(), questConfig()
    if not d then return "waiting for game data..." end
    local ready, cats = 0, 0
    for cat, list in pairs(cfg or {}) do
        local cur = d.Quests and d.Quests[cat]
        if cur then
            cats = cats + 1
            for name, conf in pairs(list) do
                local e = cur[name]
                local need = tonumber(conf and conf.Value) or 0
                local prog = tonumber(e and e.Progress) or 0
                if need > 0 and prog >= need and not (e and e.Claimed) then
                    ready = ready + 1
                end
            end
        end
    end
    local dr = d.Anniversary and d.Anniversary.DailyRewards
    local unclaimed, curDay, maxDay = 0, 0, 0
    if dr and type(dr.Rewards) == "table" then
        curDay = tonumber(dr.Current) or 0
        for i, got in pairs(dr.Rewards) do
            local n = tonumber(i)
            if n then
                if n > maxDay then maxDay = n end
                if n <= curDay and not got then unclaimed = unclaimed + 1 end
            end
        end
    end
    local chain = "done"
    local ql = d.Anniversary and d.Anniversary.Questline
    if ql and not ql.Finished then
        local cfgQ = annivConfig() and annivConfig().Quests
        local total = cfgQ and #cfgQ or 10
        chain = ("%d/%d"):format(math.max((tonumber(ql.Current) or 1) - 1, 0), total)
    end
    return ("quests ready %d  (%d cats)   chain %s   calendar %d/%d, %d ready"):format(
        ready, cats, chain, curDay, maxDay, unclaimed)
end

function Claim.start()
    if Claim._thread then return end
    Claim._thread = task.spawn(function()
        while getgenv().STD_Hub == Hub do
            if Claim.autoQuests then pcall(Claim.claimQuests) end
            if Claim.autoDaily then pcall(Claim.claimDaily) end
            if Claim.autoChain then pcall(Claim.claimQuestline) end
            if Hub._claimLabel then
                pcall(function() Hub._claimLabel:SetText(Claim.summary()) end)
            end
            task.wait(Claim.interval)
        end
        Claim._thread = nil
    end)
end

local claimBox = Tabs.Abil:AddLeftGroupbox("Daily + Quests", "timer")

claimBox:AddButton({
    Text = "CLAIM EVERYTHING NOW",
    Func = function()
        Claim._tries = {}
        local ready, fired = Claim.claimQuests()
        local chainReady, chainFired = Claim.claimQuestline()
        local days = Claim.claimDaily(false)
        setStatus(("claim: %d quest(s), %d story step(s), %d calendar day(s)"):format(
            fired, chainFired, days),
            (fired + chainFired + days) > 0 and "good" or "info")
        if Hub._claimLabel then
            pcall(function() Hub._claimLabel:SetText(Claim.summary()) end)
        end
    end,
    Tooltip = "fires ClaimQuest for every finished quest, ClaimTutorial for a finished story step, " ..
              "then ClaimDaily for the next unlocked day",
})

claimBox:AddButton({
    Text = "FORCE ALL CALENDAR DAYS",
    Func = function()
        Claim._tries = {}
        local days = Claim.claimDaily(true)
        setStatus(("calendar: tried %d day(s) - the server drops the locked ones"):format(days), nil)
    end,
    Tooltip = "sends ClaimDaily for every unclaimed day, locked or not. " ..
              "only useful if the day unlock rule ever changes",
})

claimBox:AddToggle("AutoClaimQuests", {
    Text = "auto claim quests",
    Default = false,
    Tooltip = "every 15s: claim any quest that reached its target and is not claimed yet",
    Callback = function(v)
        Claim.autoQuests = v
        setStatus(v and "auto quests ON" or "auto quests OFF", nil)
    end,
})

claimBox:AddToggle("AutoClaimDaily", {
    Text = "auto claim daily calendar",
    Default = false,
    Tooltip = "checks the anniversary calendar and grabs the day as soon as it unlocks",
    Callback = function(v)
        Claim.autoDaily = v
        setStatus(v and "auto daily ON" or "auto daily OFF", nil)
    end,
})

claimBox:AddToggle("AutoClaimChain", {
    Text = "auto claim story chain",
    Default = false,
    Tooltip = "claims each anniversary questline step the moment it is finished",
    Callback = function(v)
        Claim.autoChain = v
        setStatus(v and "auto story chain ON" or "auto story chain OFF", nil)
    end,
})

claimBox:AddButton({
    Text = "SCAN",
    Func = function()
        local ready = Claim.claimQuests(true)
        setStatus(Claim.summary(), nil)
        if Hub._claimLabel then
            pcall(function() Hub._claimLabel:SetText(Claim.summary()) end)
        end
    end,
    Tooltip = "read only: counts what is claimable right now",
})

Hub._claimLabel = claimBox:AddLabel("scanning...", true)

Claim.start()

--=============================================================
-- PINATAS : open the loot piñatas sitting in the inventory
--=============================================================
-- The inventory row for an item whose config Type is "Pinata" opens it with
--   Remotes.Anniversary.PinataInventory:FireServer(itemUUID)
-- one UUID per piñata, and the server pushes the reveal back on the same
-- remote. There is also Remotes.Anniversary.PiniataSummon, but that one only
-- spends the in-match counter (Anniversary.Pinatas) and is not the inventory.
local Pinata = {}
Hub.Pinata = Pinata

Pinata.auto    = false
Pinata.limit   = 10
Pinata.gap     = 0.7
Pinata._thread = nil
Pinata._cfg    = nil

local function itemConfig()
    if Pinata._cfg then return Pinata._cfg end
    local ok, mod = pcall(function() return require(RS.Configs.Items) end)
    if ok and mod and type(mod.Config) == "table" then Pinata._cfg = mod.Config end
    return Pinata._cfg
end

-- every piñata the player owns, one entry per UUID (they do not stack)
function Pinata.list()
    local found = {}
    local d, cfg = Claim.data(), itemConfig()
    if not (d and cfg and d.Items) then return found end
    for uuid, it in pairs(d.Items) do
        local name = it and it.Name
        local conf = name and cfg[name]
        if conf and conf.Type == "Pinata" then
            table.insert(found, {
                uuid  = uuid,
                name  = name,
                label = conf.DisplayName or name,
            })
        end
    end
    table.sort(found, function(a, b)
        if a.name == b.name then return a.uuid < b.uuid end
        return a.name < b.name
    end)
    return found
end

function Pinata.count()
    return #Pinata.list()
end

-- the Piniatas frame also keeps a plain counter (Anniversary.Pinatas) that
-- PiniataSummon spends; the GUI only ever asks for 1 or 10 at a time
function Pinata.counter()
    local d = Claim.data()
    return tonumber(d and d.Anniversary and d.Anniversary.Pinatas) or 0
end

function Pinata.summon(n, dry)
    local rem = resolveRemote("Anniversary.PiniataSummon")
    if not rem then return 0 end
    n = math.clamp(tonumber(n) or 1, 1, 10)
    if dry then return n end
    local ok, res = pcall(function() return rem:InvokeServer(n) end)
    if ok and res then return n end
    return 0
end

function Pinata.openAll(limit, dry)
    local list = Pinata.list()
    local total = #list
    local fired = 0
    if total > 0 then
        local rem = resolveRemote("Anniversary.PinataInventory")
        if not rem then return total, 0 end
        limit = limit or total
        for _, p in ipairs(list) do
            if fired >= limit then break end
            if not dry then
                pcall(function() rem:FireServer(p.uuid) end)
                task.wait(Pinata.gap)
            end
            fired = fired + 1
        end
        return total, fired
    end
    -- nothing in Items but the counter is not empty: that is the other half of
    -- the same system, opened through PiniataSummon instead
    local c = Pinata.counter()
    if c > 0 then
        local n = math.min(limit or c, c, 10)
        return c, Pinata.summon(n, dry)
    end
    return 0, 0
end

function Pinata.refreshLabel()
    if not Hub._pinataLabel then return end
    local txt = ("pinatas: %d in inventory  ·  counter %d"):format(Pinata.count(), Pinata.counter())
    pcall(function() Hub._pinataLabel:SetText(txt) end)
end

function Pinata.start()
    if Pinata._thread then return end
    Pinata._thread = task.spawn(function()
        while getgenv().STD_Hub == Hub do
            Pinata.refreshLabel()
            if Pinata.auto then
                if Pinata.count() > 0 or Pinata.counter() > 0 then
                    local total, fired = Pinata.openAll(Pinata.limit)
                    if fired > 0 then
                        setStatus(("pinata: opened %d of %d"):format(fired, total), "good")
                        Pinata.refreshLabel()
                    end
                end
            end
            task.wait(Pinata.auto and 4 or 2)
        end
        Pinata._thread = nil
    end)
end

local pinataBox = Tabs.Abil:AddLeftGroupbox("Pinatas", "gift")

pinataBox:AddButton({
    Text = "OPEN ALL PINATAS",
    Func = function()
        local total, fired = Pinata.openAll(Pinata.limit)
        if total == 0 then
            setStatus("pinata: inventory is empty", "warn")
        else
            setStatus(("pinata: opened %d of %d"):format(fired, total), "good")
        end
        Pinata.refreshLabel()
    end,
    Tooltip = "opens every Loot Pinata in the inventory, up to the per-pass limit below",
})

pinataBox:AddToggle("AutoOpenPinata", {
    Text = "auto open pinatas",
    Default = false,
    Tooltip = "checks the inventory every few seconds and opens what is there",
    Callback = function(v)
        Pinata.auto = v
        setStatus(v and "auto pinata ON" or "auto pinata OFF", nil)
    end,
})

pinataBox:AddSlider("PinataLimit", {
    Text = "per pass",
    Default = 10,
    Min = 1,
    Max = 50,
    Rounding = 0,
    Callback = function(v) Pinata.limit = v end,
})

Hub._pinataLabel = pinataBox:AddLabel("pinatas in inventory: -", true)

Pinata.start()

local towerList = {}

local function displayOf(e)
    local lvl = e.level and ("L" .. e.level) or "L?"
    return string.format("%s  ·  %s  ·  %s", e.spec.label, e.spec.ability, lvl)
end

--=============================================================
-- CASTER : continuous cast loops (one thread, two modes)
--=============================================================
-- "selected" keeps firing the tower picked in the dropdown, "all" keeps firing
-- every ability tower on the map. Only one can run at a time - two loops would
-- double-fire the same remote - so turning one on turns the other off.
local Caster = {}
Hub.Caster = Caster

Caster.mode = "none"
Caster.thread = nil
Caster._syncing = false

function Caster.findSelected()
    local pick = Options.TowerPick.Value
    if not pick or pick == "no towers on the map" then return nil end
    for _, e in ipairs(scanTowers()) do
        if displayOf(e) == pick then return e end
    end
    return nil
end

function Caster.fire()
    if Caster.mode == "all" then
        castAll()
        return true
    elseif Caster.mode == "selected" then
        local e = Caster.findSelected()
        if not e then
            setStatus("auto cast: pick a tower first", "warn")
            return false
        end
        if not e.remote then
            setStatus("auto cast: remote missing for " .. tostring(e.attack), "bad")
            return false
        end
        pressEntry(e)
        -- status only, no toast: this runs every CastDelay tick
        setStatus("auto cast: " .. e.spec.label, nil)
        return true
    end
    return false
end

function Caster.tick()
    if Caster.thread then return end
    Caster.thread = task.spawn(function()
        while Caster.mode ~= "none" and getgenv().STD_Hub == Hub do
            local ok, err = pcall(Caster.fire)
            if not ok then log("auto cast error: " .. tostring(err)) end
            task.wait(CFG.CastDelay)
        end
        Caster.thread = nil
    end)
end

function Caster.setMode(mode)
    Caster.mode = mode or "none"
    if Caster.mode ~= "none" then Caster.tick() end
end

function Caster.stop()
    Caster.mode = "none"
end

-- one delay value for both sliders (abilities + macros), kept in sync by hand
-- because setting a widget fires its own callback
function Hub.setCastDelay(v)
    v = math.clamp(tonumber(v) or 12, 3, 100)
    CFG.CastDelay = v / 10
    if Hub._syncDelay then return end
    Hub._syncDelay = true
    pcall(function() Options.CastDelayAb:SetValue(v) end)
    Hub._syncDelay = false
end

abilBox:AddLabel("TOWERS ON MAP")
Hub._countLabel = abilBox:AddLabel("scanning...", true)

abilBox:AddDropdown("TowerPick", {
    Values = { "—" },
    Default = 1,
    Multi = false,
    Text = "tower",
    Tooltip = "every placed tower with a domain / ult / special",
    Callback = function() end,
})

abilBox:AddButton({
    Text = "CAST SELECTED",
    Func = function()
        local e = Caster.findSelected()
        if not e then
            setStatus("nothing selected", "warn")
            return
        end
        if not e.remote then
            setStatus("remote missing for " .. tostring(e.attack), "bad")
            return
        end
        pressEntry(e)
        setStatus("cast " .. e.spec.label, "good")
    end,
    DoubleClick = false,
})

abilBox:AddButton({
    Text = "CAST ALL",
    Func = function()
        setStatus("casting all...", nil)
        castAll()
    end,
})

abilBox:AddDivider()

--=============================================================
-- AUTO CAST : selected / all
--=============================================================
-- both toggles drive the same loop, so turning one on turns the other off -
-- otherwise two loops would fire the same ability twice per cycle
local function syncCastToggles()
    if Caster._syncing then return end
    Caster._syncing = true
    pcall(function() Toggles.AutoCastSel:SetValue(Caster.mode == "selected") end)
    pcall(function() Toggles.AutoCastAll:SetValue(Caster.mode == "all") end)
    Caster._syncing = false
end
Hub.syncCastToggles = syncCastToggles

local function castToggleOn(mode)
    if Caster._syncing then return end
    Caster.setMode(mode)
    syncCastToggles()
    local label = mode == "selected" and "auto cast selected on" or "auto cast all on"
    setStatus(label .. (" every %.1fs"):format(CFG.CastDelay), "good")
end

abilBox:AddToggle("AutoCastSel", {
    Text = "auto cast selected",
    Default = false,
    Tooltip = "keeps firing the tower picked above, over and over, until you turn it off",
    Callback = function(v)
        if Caster._syncing then return end
        if v then
            castToggleOn("selected")
        elseif Caster.mode == "selected" then
            Caster.stop()
            syncCastToggles()
            setStatus("auto cast selected off", "warn")
        end
    end,
})

abilBox:AddToggle("AutoCastAll", {
    Text = "auto cast all",
    Default = false,
    Tooltip = "keeps firing every ability tower on the map, over and over, until you turn it off",
    Callback = function(v)
        if Caster._syncing then return end
        if v then
            castToggleOn("all")
        elseif Caster.mode == "all" then
            Caster.stop()
            syncCastToggles()
            setStatus("auto cast all off", "warn")
        end
    end,
})

abilBox:AddSlider("CastDelayAb", {
    Text = "auto cast delay",
    Default = 12,
    Min = 3,
    Max = 100,
    Rounding = 0,
    Suffix = " x0.1s",
    Callback = function(v)
        if Hub._syncDelay then return end
        Hub.setCastDelay(v)
    end,
})

abilBox:AddDivider()

abilBox:AddToggle("AutoQTE", {
    Text = "Auto QTE",
    Default = CFG.AutoSolve,
    Tooltip = "solve the Justice Sorcerer timing minigame",
    Callback = function(v)
        CFG.AutoSolve = v
        if not v then
            Hub.stopAuto()
            setStatus("auto qte off", "warn")
        else
            getgenv().STD_Edge = nil
            Hub.startAuto()
            setStatus("auto qte on - farming until you turn it off", "good")
        end
    end,
})

abilBox:AddDivider()

abilBox:AddToggle("NotifyOn", {
    Text = "notifications",
    Default = CFG.Notify,
    Tooltip = "corner toast popups. off means the status line at the bottom of the window only",
    Callback = function(v)
        CFG.Notify = v
        if not v then
            -- also clear whatever is already on screen
            pcall(function()
                for _, n in pairs(Library.Notifications or {}) do
                    if type(n) == "table" and n.Close then pcall(n.Close, n) end
                end
            end)
        end
    end,
})

abilBox:AddSlider("CastGraceAb", {
    Text = "wait after placing",
    Default = CFG.CastGrace,
    Min = 0,
    Max = 30,
    Rounding = 0,
    Suffix = "s",
    Tooltip = "auto QTE leaves a tower you just built alone for this long, so placing a Justice Sorcerer does not fire its domain on the same click",
    Callback = function(v) CFG.CastGrace = v end,
})

qteBox:AddLabel("GAUGE")
Hub._gaugeLabel = qteBox:AddLabel("idle", true)

-- the click lead slider used to live here. it is gone on purpose: the click is
-- sent with tick() and judged at that stamp, so a lead can only ever fire the
-- click earlier than the marker is there, which is the one direction an edge
-- aim cannot absorb. nothing replaces it

-- the id changed from "EdgeSlider" on purpose. the settings file is keyed by
-- element name and remembered `aim point = 70` from a session where the old
-- fault handler had walked the aim in, so every later load restored 0.70 and
-- the hub clicked 30% inside the strip while the log called 0.95 the target.
-- a new id has no stored value, so the default applies and the stale line is
-- simply never read again
qteBox:AddSlider("EdgeSliderEdge", {
    Text = "aim point",
    Default = 95,
    Min = 0,
    Max = 100,
    Rounding = 0,
    Suffix = "%",
    Tooltip = "how far before the centre of the strip the click is sent, in percent of a " ..
              "half-width: 100% sends it exactly one judge-delay early, so it arrives at the " ..
              "centre with a full half-width of room on both sides - the most a click can have. " ..
              "lower values send it even earlier, which trades room on the far side for room on " ..
              "the near one. the judge delay is measured from the round trip on every click, not " ..
              "set here",
    Callback = function(v)
        CFG.EdgeAim = v / 100
        getgenv().STD_Edge = CFG.EdgeAim
    end,
})

qteBox:AddButton({
    Text = "RESET AIM",
    Func = function()
        getgenv().STD_Edge = nil
        CFG.EdgeAim = 0.95
        setStatus("aim point back to the edge", "good")
    end,
})

qteBox:AddDivider()
qteBox:AddLabel("a hit is +1.0 and +0.1 per streak, a miss is -1.0 and resets it. 22 points fires the execution.", true)

--=============================================================
-- NOCLIP MODULE
--=============================================================
-- NOCLIP : automatic, tied to teleports - no toggle
--=============================================================
-- The lobby has invisible blockers around the elevators and the match places
-- spawn you inside geometry. Touching either with collisions on is instant
-- death, so collisions are switched off by the hub itself:
--   * for a window around every teleport it performs (elevator jump, mode entry)
--   * for the whole time you are inside a mode (any place that is not the lobby)
-- There is nothing to press and nothing to configure.
local Noclip = {}
Hub.Noclip = Noclip

Noclip.LOBBY  = 17720162456
Noclip.WINDOW = 30           -- seconds of protection around one teleport
Noclip.untilClock = 0
Noclip.thread = nil
Noclip.lastPlace = game.PlaceId

-- any place that is not the lobby is a mode we just got teleported into
function Noclip.inMatch()
    return game.PlaceId ~= Noclip.LOBBY
end

function Noclip.active()
    return Noclip.inMatch() or os.clock() < Noclip.untilClock
end

function Noclip.apply()
    local char = LP.Character
    if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then
            pcall(function() p.CanCollide = false end)
        end
    end
end

function Noclip.tick()
    if Noclip.thread then return end
    Noclip.thread = task.spawn(function()
        while getgenv().STD_Hub == Hub do
            if Noclip.active() then Noclip.apply() end
            task.wait(0.15)
        end
        Noclip.thread = nil
    end)
end

-- called by the hub right before it moves you anywhere, so the protection is
-- already on while you are still in the air
function Noclip.arm(secs)
    Noclip.untilClock = math.max(Noclip.untilClock, os.clock() + (tonumber(secs) or Noclip.WINDOW))
    Noclip.tick()
    Noclip.apply()
end

-- only used when the hub unloads: put collisions back so nothing stays ghosted
function Noclip.stop()
    Noclip.untilClock = 0
    local char = LP.Character
    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then pcall(function() p.CanCollide = true end) end
        end
    end
end

-- new character (respawn / landing in a match): re-apply immediately
if LP.CharacterAdded then
    LP.CharacterAdded:Connect(function()
        task.wait(0.35)
        if Noclip.active() then Noclip.apply() end
    end)
end

-- place watcher: every teleport into a mode is a PlaceId change, so that is the
-- signal to arm the window without asking the user for anything
table.insert(Hub.threads, task.spawn(function()
    Noclip.tick()
    while getgenv().STD_Hub == Hub do
        local pid = game.PlaceId
        if pid ~= Noclip.lastPlace then
            Noclip.lastPlace = pid
            Noclip.arm()
            log(("teleported (place %d) - collisions off"):format(pid))
        end
        task.wait(0.4)
    end
end))

-- the server announces the jump before it happens (Countdown / StartCountdown /
-- Teleporting on the elevator remotes). Arming on those covers a long wait on the
-- pad as well, so collisions are already off the instant you are moved
table.insert(Hub.threads, task.spawn(function()
    local watched = {}
    local events = { "Countdown", "StartCountdown", "Teleporting" }
    while getgenv().STD_Hub == Hub do
        for _, folder in ipairs(RemotesRoot:GetChildren()) do
            if not watched[folder] and folder.Name:find("Teleporters") then
                watched[folder] = true
                for _, name in ipairs(events) do
                    local ev = folder:FindFirstChild(name)
                    if ev and ev:IsA("RemoteEvent") then
                        pcall(function()
                            ev.OnClientEvent:Connect(function() Noclip.arm() end)
                        end)
                    end
                end
            end
        end
        task.wait(2)
    end
end))

--=============================================================
-- MODES MODULE
--=============================================================
local Modes = {}
Hub.Modes = Modes

Modes.list = {
    { key = "gauntlet",  label = "Gauntlet",      remote = "GauntletTeleporters",  ws = "Gauntletteleporters",  map = "EndlessChallenge", gui = "GauntletTeleport" },
    { key = "endless",   label = "Endless",       remote = "EndlessTeleporters",   ws = "EndlessTeleporters",   map = "Infinite",         gui = "EndlessTeleport" },
    { key = "challenge", label = "Challenge",     remote = "ChallengeTeleporters", ws = "ChallengeTeleporters", map = "Infinite", elev = "ElevatorMed", gui = "ChallengeTeleport" },
    { key = "raid",      label = "Raid (Gojo)",   remote = "RaidTeleporters",      ws = "RaidTeleporters",      map = "Gojo",             gui = "RaidTeleport" },
    { key = "raid_toji", label = "Raid (Toji)",   remote = "RaidTeleporters",      ws = "RaidTeleporters",      map = "Toji",             gui = "RaidTeleport" },
    { key = "raid_meg",  label = "Raid (Meguna)", remote = "RaidTeleporters",      ws = "RaidTeleporters",      map = "Meguna",           gui = "RaidTeleport" },
    { key = "hakari",    label = "Casino",        remote = "HakariTeleporters",    ws = "HakariTeleporters",    map = "Hakari",           gui = "HakariTeleport" },
    { key = "sukuna",    label = "Sukuna",        remote = "SukunaTeleporters",    ws = "SukunaTeleporters",    map = "Sukuna",           gui = "SukunaTeleport" },
    { key = "story",     label = "Story",         remote = "Teleporters",          ws = "Teleporters",          map = "JujutsuHigh", story = true, gui = "Story" },
}

function Modes.byKey(k)
    for _, m in ipairs(Modes.list) do if m.key == k then return m end end
    return nil
end

function Modes.indexOfKey(k)
    for i, m in ipairs(Modes.list) do if m.key == k then return i end end
    return nil
end

function Modes.indexOfLabel(v)
    for i, m in ipairs(Modes.list) do if m.label == v then return i end end
    return nil
end

Modes.selected = 1
Modes.storyStage = 1
Modes.hellmode = false
Modes.autoJoin = false
Modes.thread = nil

function Modes.findElevator(m)
    local root = workspace:FindFirstChild(m.ws)
    if not root then return nil end
    local byName = m.elev and root:FindFirstChild(m.elev)
    if byName then return byName end
    for _, e in ipairs(root:GetChildren()) do
        local cfg = e:FindFirstChild("Config")
        local map = cfg and cfg:FindFirstChild("Map")
        if map and map.Value == m.map then
            if not m.elev or e.Name == m.elev then return e end
        end
    end
    for _, e in ipairs(root:GetChildren()) do
        local cfg = e:FindFirstChild("Config")
        local map = cfg and cfg:FindFirstChild("Map")
        if map and map.Value == m.map then return e end
    end
    return nil
end

function Modes.openElevator(model)
    if not model then return false end
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local tp = model:FindFirstChild("Teleports")
    local ent = tp and tp:FindFirstChild("Entrance")
    if not hrp or not ent then return false end
    -- the jump below lands on top of the elevator's own geometry, so collisions
    -- go off first - this is the "invisible wall" that used to shred the character
    Noclip.arm()
    if firetouchinterest then
        pcall(function() hrp.CFrame = CFrame.new(ent.Position + Vector3.new(0, 3, 0)) end)
        task.wait(0.35)
        pcall(firetouchinterest, hrp, ent, 0)
        task.wait(0.12)
        pcall(firetouchinterest, hrp, ent, 1)
    else
        pcall(function() hrp.CFrame = CFrame.new(ent.Position + Vector3.new(0, 3, 0)) end)
    end
    task.wait(0.5)
    return true
end

--=============================================================
-- FULLY AUTOMATIC ENTRY
--   the game's own sequence on an elevator, in the order its remotes are named:
--   Host creates the lobby, ChooseStage picks the map/variant, StartCountdown
--   and Start launch it. Every step is a no-op if the remote is missing, and
--   the whole thing retries while the server has not moved us yet.
--=============================================================
function Modes.remoteOf(m)
    if not m or not RemotesRoot then return nil end
    return RemotesRoot:FindFirstChild(m.remote)
end

function Modes.fireStep(rem, step, ...)
    if not rem then return false end
    local r = rem:FindFirstChild(step)
    if not r then
        log(("  step %s: remote missing"):format(step))
        return false
    end
    -- varargs cannot be used inside a nested closure, so pack them once
    local args = table.pack(...)
    local ok, err = pcall(function() r:FireServer(table.unpack(args, 1, args.n)) end)
    if not ok then log(("  step %s failed: %s"):format(step, tostring(err))) end
    return ok
end

-- the game puts a BillboardGui with "1/8" over the elevator you are standing on,
-- so that counter is the honest answer to "did we actually board"
function Modes.boardCount(m)
    local model = Modes.findElevator(m)
    local bg = model and model:FindFirstChild("Billboard")
    local bgi = bg and bg:FindFirstChild("BillboardGui")
    local c = bgi and bgi:FindFirstChild("PlayerCount")
    if not c then return nil end
    return tonumber((tostring(c.Text):gsub("/.*", ""))) or 0
end

function Modes.waitBoard(m, timeout)
    local t0 = os.clock()
    while os.clock() - t0 < (timeout or 3) do
        if (Modes.boardCount(m) or 0) > 0 then return true end
        task.wait(0.15)
    end
    return false
end

-- walks onto the elevator, hosts, picks the stage and starts - no clicks
function Modes.enterAuto(idx, opts)
    opts = opts or {}
    local m = Modes.list[idx or Modes.selected]
    if not m then return false, "no mode" end
    local rem = Modes.remoteOf(m)
    if not rem then
        setStatus("remote " .. tostring(m.remote) .. " is missing", "bad")
        return false, "no remote"
    end

    -- you cannot board a second elevator while you are on one
    local cur = Modes.currentElevator()
    if cur and cur.key ~= m.key then
        log(("releasing %s before %s"):format(cur.label, m.label))
        Modes.release()
        task.wait(0.3)
    end

    local model = Modes.findElevator(m)
    if not model then
        setStatus("no elevator found for " .. m.label, "bad")
        return false, "no elevator"
    end

    -- boarding is the only part worth retrying: once the lobby exists, a retry
    -- would release it and start over
    Noclip.arm()
    local boarded = false
    for attempt = 1, 3 do
        setStatus(("boarding %s - try %d/3"):format(m.label, attempt), nil)
        Modes.openElevator(model)
        if Modes.waitBoard(m, 3) then boarded = true; break end
        log(("  boarding attempt %d missed, touching the entrance again"):format(attempt))
    end
    if not boarded then
        -- the counter can be missing on some elevators, so this is a warning
        -- rather than a stop - the remotes may still take
        log("  board counter never went above 0, firing anyway")
    end

    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    local startPos = hrp and hrp.Position
    local startPlace = game.PlaceId

    Modes.fireStep(rem, "Host", model)
    task.wait(0.6)
    if m.story then
        local modeStr = opts.hellmode and "Hellmode" or "Normal"
        Modes.fireStep(rem, "ChooseStage", model, opts.stage or Modes.storyStage, modeStr, false)
    else
        Modes.fireStep(rem, "ChooseStage", model, false)
    end
    task.wait(0.45)
    Modes.fireStep(rem, "StartCountdown", model)
    task.wait(0.25)
    Modes.fireStep(rem, "Start", model)
    setStatus(m.label .. " - hosted, waiting for the countdown", "good")

    -- the server moves us into the map when the countdown ends, so watch for a
    -- teleport instead of pretending we know the timer
    local t0 = os.clock()
    while os.clock() - t0 < 15 do
        if game.PlaceId ~= startPlace then return true, model end
        local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if h and startPos and (h.Position - startPos).Magnitude > 250 then
            return true, model
        end
        task.wait(0.25)
    end

    setStatus(m.label .. " - hosted but nothing moved, check the elevator screen", "warn")
    return false, "no teleport"
end

function Modes.host(idx, opts)
    opts = opts or {}
    local m = Modes.list[idx or Modes.selected]
    if not m then return false, "no mode" end
    local model = Modes.findElevator(m)
    if not model then
        setStatus("elevator for " .. m.label .. " not found", "bad")
        return false, "no elevator"
    end

    local rem = RemotesRoot:FindFirstChild(m.remote)
    if not rem then
        setStatus("remote " .. m.remote .. " missing", "bad")
        return false, "no remote"
    end

    setStatus("opening " .. m.label .. "...", nil)
    -- you cannot board a second elevator while you are still on one, so drop the
    -- current one first - this is why entering a mode used to silently do nothing.
    -- Also run it when we think we are free, because the server can still hold a
    -- stale slot from an earlier attempt.
    local cur = Modes.currentElevator()
    if not cur or cur.key ~= m.key then
        if cur then log(("releasing %s before entering %s"):format(cur.label, m.label)) end
        Modes.release()
        task.wait(0.3)
    end
    -- the match spawns you inside geometry, and the hub will not survive the
    -- place change, so the window is armed here and re-armed on load over there
    Noclip.arm()
    Modes.openElevator(model)

    local cs = rem:FindFirstChild("ChooseStage")
    if not cs then
        setStatus("ChooseStage missing on " .. m.remote, "bad")
        return false, "no ChooseStage"
    end

    local ok, err
    if m.story then
        local modeStr = opts.hellmode and "Hellmode" or "Normal"
        local stage = opts.stage or Modes.storyStage
        ok, err = pcall(function() cs:FireServer(model, stage, modeStr, false) end)
        log(("host story: stage=%d mode=%s"):format(stage, modeStr))
    else
        ok, err = pcall(function() cs:FireServer(model, false) end)
        log("host " .. m.label)
    end

    if not ok then
        setStatus("fire failed: " .. tostring(err), "bad")
        return false, tostring(err)
    end

    task.wait(0.9)
    local st = rem:FindFirstChild("Start")
    if st then pcall(function() st:FireServer(model) end) end

    setStatus(m.label .. " - hosting, countdown started", "good")
    return true, model
end

function Modes.leave(idx)
    local m = Modes.list[idx or Modes.selected]
    if not m then return end
    local rem = RemotesRoot:FindFirstChild(m.remote)
    local model = Modes.findElevator(m)
    if rem and model then
        local hl = rem:FindFirstChild("HostLeave")
        if hl then pcall(function() hl:FireServer(model) end) end
    end
    setStatus("left " .. m.label, "warn")
end

function Modes.startAutoJoin()
    if Modes.thread then return end
    Modes.autoJoin = true
    Modes.thread = task.spawn(function()
        while Modes.autoJoin and getgenv().STD_Hub == Hub do
            pcall(function()
                if game.PlaceId == 17720162456 then
                    Modes.host(Modes.selected, { stage = Modes.storyStage, hellmode = Modes.hellmode })
                end
            end)
            task.wait(9)
        end
        Modes.thread = nil
    end)
end

function Modes.stopAutoJoin()
    Modes.autoJoin = false
    if Modes.thread then pcall(function() task.cancel(Modes.thread) end) end
    Modes.thread = nil
end

--=============================================================
-- AUTO START
--=============================================================
-- The elevator hands you the host slot by firing Host(elevator), shows the host
-- panel, and then drops you again a second later (Leave + HostLeave) if nobody
-- confirms the stage. Start only sticks while you are still counted on the pad,
-- so pressing it on a timer never lands - it has to go out inside that window.
-- Hence: react to Host itself, then keep re-trying every cycle.
Modes.autoStart = false
Modes.startThread = nil
Modes.hostHooks = {}
Modes.LOBBY = 17720162456

local function pressButton(btn)
    if not btn then return false end
    local ok, conns = pcall(getconnections, btn.Activated)
    if ok and conns and #conns > 0 then
        pcall(function() conns[1].Function() end)
        return true
    end
    return false
end

function Modes.modeGui(m)
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg or not m.gui then return nil end
    return pg:FindFirstChild(m.gui)
end

-- true when the server currently counts us on this elevator
function Modes.isOnElevator(m)
    local model = Modes.findElevator(m)
    local bg = model and model:FindFirstChild("Billboard")
    local bgi = bg and bg:FindFirstChild("BillboardGui")
    local count = bgi and bgi:FindFirstChild("PlayerCount")
    if not count then return false end
    return (tonumber((count.Text:gsub("/.*", ""))) or 0) > 0
end

-- which elevator we are currently attached to, if any
function Modes.currentElevator()
    for _, m in ipairs(Modes.list) do
        if Modes.isOnElevator(m) then return m end
    end
    return nil
end

-- You cannot board a second elevator while you are still on one - the game
-- silently ignores the new entrance until you press Exit. So every entry has to
-- let go of the old one first, otherwise nothing happens and it looks broken.
function Modes.release()
    local released = false

    -- the on-elevator Exit button (this is the one the game puts on screen)
    local pg = LP:FindFirstChild("PlayerGui")
    local elevGui = pg and pg:FindFirstChild("Elevator")
    local ex = elevGui and elevGui:FindFirstChild("Exit")
    if ex and ex.Visible then
        released = pressButton(ex) or released
        task.wait(0.15)
    end

    -- Leave inside each mode panel
    for _, m in ipairs(Modes.list) do
        local gui = Modes.modeGui(m)
        if gui then
            for _, panel in ipairs({ "Frame", "TeleMenu" }) do
                local p = gui:FindFirstChild(panel)
                local leave = p and p:FindFirstChild("Leave")
                if leave and p.Visible then
                    released = pressButton(leave) or released
                end
            end
        end
    end

    -- and the remotes behind them, so it works even with no GUI on screen
    for _, m in ipairs(Modes.list) do
        local rem = RemotesRoot:FindFirstChild(m.remote)
        local model = Modes.findElevator(m)
        if rem and model then
            local hl = rem:FindFirstChild("HostLeave")
            local lv = rem:FindFirstChild("Leave")
            if hl then pcall(function() hl:FireServer(model) end) end
            if lv then pcall(function() lv:FireServer(model) end) end
            released = true
        end
    end

    task.wait(0.45)
    return released
end

-- one full attempt: confirm the stage, then start
function Modes.pressStart(m)
    m = m or Modes.list[Modes.selected]
    local model = Modes.findElevator(m)
    if not model then return false, "no elevator" end
    local rem = RemotesRoot:FindFirstChild(m.remote)
    if not rem then return false, "no remote" end

    local gui = Modes.modeGui(m)
    local frame = gui and gui:FindFirstChild("Frame")
    local menu = gui and gui:FindFirstChild("TeleMenu")

    -- the host panel's Start = ChooseStage, the prompt's Start = Start
    local pressed = false
    if frame and frame.Visible and frame:FindFirstChild("Start") then
        pressed = pressButton(frame.Start) or pressed
    end
    if not pressed then
        local cs = rem:FindFirstChild("ChooseStage")
        if cs then
            if m.story then
                pcall(function() cs:FireServer(model, Modes.storyStage, Modes.hellmode and "Hellmode" or "Normal", false) end)
            else
                pcall(function() cs:FireServer(model, false) end)
            end
        end
    end

    task.wait(0.12)

    local started = false
    if menu and menu:FindFirstChild("Start") then
        started = pressButton(menu.Start)
    end
    if not started then
        local st = rem:FindFirstChild("Start")
        if st then
            local ok = pcall(function() st:FireServer(model) end)
            started = ok
        end
    end
    return started
end

function Modes.watchHost(m, model)
    if not model then return end
    local key = m.remote .. "|" .. model.Name
    if Modes.hostHooks[key] then return end
    local rem = RemotesRoot:FindFirstChild(m.remote)
    if not rem then return end
    local hostEv = rem:FindFirstChild("Host")
    if not hostEv then return end
    Modes.hostHooks[key] = hostEv.OnClientEvent:Connect(function(ev)
        if not Modes.autoStart then return end
        if ev ~= model then return end
        -- we were just made host: fire immediately, before we get dropped
        Modes.pressStart(m)
        log("auto start: Host received -> ChooseStage + Start fired")
    end)
end

function Modes.startAutoStart()
    if Modes.startThread then return end
    Modes.autoStart = true
    Modes.startThread = task.spawn(function()
        local lastTouch = 0
        while Modes.autoStart and getgenv().STD_Hub == Hub do
            if game.PlaceId ~= Modes.LOBBY then
                log("auto start: match began, stopping")
                setStatus("match started - auto start done", "good")
                Modes.autoStart = false
                break
            end

            local m = Modes.list[Modes.selected]
            local model = Modes.findElevator(m)
            if model then
                Modes.watchHost(m, model)
                -- never try to board while attached to a different elevator
                local cur = Modes.currentElevator()
                if cur and cur.key ~= m.key then
                    Modes.release()
                end
                if not Modes.isOnElevator(m) then
                    -- step onto the pad so the server counts us, at most 1x/4s
                    if os.clock() - lastTouch > 4 then
                        lastTouch = os.clock()
                        Modes.openElevator(model)
                    end
                else
                    local ok = Modes.pressStart(m)
                    if ok then
                        setStatus(("auto start: pressing %s"):format(m.label), nil)
                    end
                end
            else
                setStatus("auto start: elevator for " .. m.label .. " not found", "bad")
            end
            task.wait(1.1)
        end
        Modes.startThread = nil
    end)
end

function Modes.stopAutoStart()
    Modes.autoStart = false
    if Modes.startThread then pcall(function() task.cancel(Modes.startThread) end) end
    Modes.startThread = nil
    for k, c in pairs(Modes.hostHooks) do
        pcall(function() c:Disconnect() end)
        Modes.hostHooks[k] = nil
    end
    setStatus("auto start off", "warn")
end

--=============================================================
-- SLOTS : what sits in the hotbar
--=============================================================
-- a slot is a field on the tower entry in State, not a remote of its own.
-- clicking a unit in the inventory fires EquipTower with its UUID and the server
-- answers with (uuid, slot). the same call on an already equipped unit takes it
-- out again, and a fresh one always lands in the lowest free slot - measured, not
-- guessed. so a whole layout can be rebuilt through that one remote.
-- the sixth slot only exists after Counters.GotTowerSlot, i.e. all culling quests
local Slots = {}
Hub.Slots = Slots

Slots.auto = true
Slots.busy = false

local function stateData()
    local c = RS:FindFirstChild("Client")
    local s = c and c:FindFirstChild("State")
    if not s then return nil end
    local ok, d = pcall(function() return require(s).GetData() end)
    if ok then return d end
    return nil
end

function Slots.max()
    local d = stateData()
    local c = d and d.Counters
    return (c and c.GotTowerSlot) and 6 or 5
end

function Slots.current()
    local out = {}
    local d = stateData()
    if not d or not d.Towers then return out end
    for _, t in pairs(d.Towers) do
        if t.Equipped and t.EquippedSlot then
            out[t.EquippedSlot] = { uuid = t.UUID, name = t.Name, trait = t.Trait }
        end
    end
    return out
end

function Slots.owned()
    local out = {}
    local d = stateData()
    if not d or not d.Towers then return out end
    for _, t in pairs(d.Towers) do
        table.insert(out, {
            uuid = t.UUID, name = t.Name, trait = t.Trait,
            equipped = t.Equipped == true,
        })
    end
    return out
end

local function equipRemote()
    local r = RS:FindFirstChild("Remotes")
    local t = r and r:FindFirstChild("Towers")
    return t and t:FindFirstChild("EquipTower")
end

-- one call flips the state: in if it was out, out if it was in
function Slots.toggle(uuid)
    local e = equipRemote()
    if not e or not uuid then return false end
    return pcall(function() e:FireServer(uuid) end)
end

-- "1:SoulCurse@Fortune|2:GazeSorcerer|3:empty|..."
function Slots.encode(map)
    local parts = {}
    for i = 1, Slots.max() do
        local e = map[i]
        if e and e.name then
            table.insert(parts, ("%d:%s%s"):format(i, e.name,
                e.trait and ("@" .. tostring(e.trait)) or ""))
        else
            table.insert(parts, i .. ":empty")
        end
    end
    return table.concat(parts, "|")
end

function Slots.decode(str)
    local out = {}
    for chunk in string.gmatch(tostring(str or ""), "[^|]+") do
        local i, rest = chunk:match("^(%d+):(.*)$")
        i = tonumber(i)
        if i then
            local name, trait = rest:match("^([^@]+)@(.*)$")
            if not name then name, trait = rest, nil end
            if name ~= "empty" and name ~= "" then
                out[i] = { name = name, trait = trait }
            end
        end
    end
    return out
end

function Slots.text(layout)
    local parts = {}
    for i = 1, 6 do
        local e = layout[i]
        if e then table.insert(parts, ("%d:%s"):format(i, e.name)) end
    end
    return #parts > 0 and table.concat(parts, "  ") or "empty"
end

-- rebuild the hotbar. everything is checked before anything is touched: if even
-- one wanted unit is not owned the layout is left exactly as it is, because a
-- half rebuilt hotbar in the middle of a match is worse than no swap at all
function Slots.apply(layout, opts)
    opts = opts or {}
    -- picking a macro and hitting PLAY a second later used to start a second
    -- rebuild on top of the first one, and the two would unequip each other
    if Slots.busy then return 0, "a hotbar swap is already running" end
    local want, top = {}, 0
    for i = 1, 6 do
        if layout[i] and layout[i].name then
            want[i] = layout[i]
            top = i
        end
    end
    if top == 0 then return 0, "no slots saved in this macro" end
    local max = Slots.max()
    if top > max then top = max end

    local cur = Slots.current()
    local same = true
    for i = 1, top do
        local c = cur[i]
        if not c or c.name ~= want[i].name then same = false break end
    end
    if same then return 0, "already matches" end

    local have, need, missing = {}, {}, {}
    for _, t in ipairs(Slots.owned()) do
        have[t.name] = (have[t.name] or 0) + 1
    end
    for i = 1, top do
        need[want[i].name] = (need[want[i].name] or 0) + 1
    end
    for name, cnt in pairs(need) do
        if (have[name] or 0) < cnt then table.insert(missing, name) end
    end
    if #missing > 0 then
        table.sort(missing)
        return 0, "not owned: " .. table.concat(missing, ", ")
    end

    -- clear the board first so the server hands the slots out from 1 upward
    Slots.busy = true
    for _, c in pairs(cur) do
        if c.uuid then
            Slots.toggle(c.uuid)
            task.wait(0.35)
        end
    end
    task.wait(0.5)

    local pool = {}
    for _, t in ipairs(Slots.owned()) do
        if not t.equipped then table.insert(pool, t) end
    end

    local placed = 0
    for i = 1, top do
        local w = want[i]
        local pick, fallback
        for k, t in ipairs(pool) do
            if t.name == w.name then
                if w.trait and t.trait == w.trait then pick = k break end
                fallback = fallback or k
            end
        end
        pick = pick or fallback
        if pick then
            local t = table.remove(pool, pick)
            Slots.toggle(t.uuid)
            placed = placed + 1
            task.wait(0.4)
        end
    end
    task.wait(0.5)

    local after = Slots.current()
    Slots.busy = false
    local wrong = 0
    for i = 1, top do
        local a = after[i]
        if not a or a.name ~= want[i].name then wrong = wrong + 1 end
    end
    if wrong > 0 then
        return placed, ("%d slot(s) did not land, check the hotbar"):format(wrong)
    end
    return placed, nil
end

--=============================================================
-- MACRO RECORDER  (v4 - one per mode tab, named, scoped to its tab)
--=============================================================
-- Files:  STD_Hub_macros/<modeKey>/<name>.txt
-- Line:   <seconds since REC>|<E|F>|<remote path>|<~joined args>
--         E = RemoteEvent:FireServer, F = RemoteFunction:InvokeServer
--
-- Only one recorder captures at a time: the __namecall hook is global and a
-- second one would stack and double-log every call. Starting REC on another
-- tab stops the one that was running, and that one still saves what it caught.
--
-- capture "entry"  teleport / gauntlet remotes only - the mode entry sequence
-- capture "full"   every remote the client sends - a hand-played wave
local Rec = {}
Hub.Rec = Rec

Rec.dir       = "STD_Hub_macros"
Rec.active    = nil     -- the recorder currently capturing
Rec.replaying = false   -- set while a macro plays back, so it never records itself
Rec._hookOld  = nil

if makefolder then pcall(makefolder, Rec.dir) end

local function pathOf(inst)
    local parts = {}
    local cur = inst
    while cur and cur ~= game do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
    end
    return table.concat(parts, ".")
end

local function resolvePath(path)
    local cur = game
    for seg in string.gmatch(path, "[^%.]+") do
        cur = cur and cur:FindFirstChild(seg)
        if not cur then return nil end
    end
    return cur
end

-- a tower gets renamed the moment it is upgraded (SoulCurse -> SoulCurse2), so a
-- raw path alone can miss. it is stored as path|family|level and resolved back
-- by exact path first, then by name family. properties only, no :GetChildren -
-- this runs inside the __namecall hook where a nested call would hijack the
-- dispatch of the very remote being logged
local function baseOf(n)
    return (tostring(n):gsub("%d+$", ""))
end

local function levelOf(n)
    return tonumber(tostring(n):match("(%d+)$")) or 1
end

local function encodeInst(v)
    local nm = v.Name
    return "I:" .. pathOf(v) .. "|" .. baseOf(nm) .. "|" .. tostring(levelOf(nm))
end

local function decodeInst(rest)
    local path, base, lvl = rest:match("^(.-)|(.-)|(%d+)$")
    if not path then return resolvePath(rest) end
    local exact = resolvePath(path)
    if exact and exact.Parent then return exact end
    local parPath = path:match("^(.*)%.[^%.]+$")
    local par = parPath and resolvePath(parPath)
    if not par then return exact end
    local want = tonumber(lvl)
    local first
    for _, c in ipairs(par:GetChildren()) do
        if baseOf(c.Name) == base then
            if want and levelOf(c.Name) == want then return c end
            first = first or c
        end
    end
    return first or exact
end

local function encodeArg(v)
    if typeof(v) == "Instance" then return encodeInst(v) end
    if typeof(v) == "CFrame" then return "C:" .. tostring(v) end
    if typeof(v) == "Vector3" then return "V:" .. tostring(v) end
    local t = type(v)
    if t == "nil" then return "nil:" end
    if t == "boolean" or t == "number" then return t .. ":" .. tostring(v) end
    return "s:" .. tostring(v)
end

local function numbersOf(s)
    local n = {}
    for num in string.gmatch(s, "[-%d%.eE]+") do
        local v = tonumber(num)
        if v then table.insert(n, v) end
    end
    return n
end

local function decodeArg(s)
    local kind, rest = s:match("^(%a+):(.*)$")
    if kind == "I" then return decodeInst(rest) end
    if kind == "C" then
        local n = numbersOf(rest)
        if #n >= 12 then
            return CFrame.new(n[1], n[2], n[3], n[4], n[5], n[6], n[7], n[8], n[9], n[10], n[11], n[12])
        end
        if #n >= 3 then return CFrame.new(n[1], n[2], n[3]) end
        return nil
    end
    if kind == "V" then
        local n = numbersOf(rest)
        return Vector3.new(n[1] or 0, n[2] or 0, n[3] or 0)
    end
    if kind == "boolean" then return rest == "true" end
    if kind == "number" then return tonumber(rest) end
    if kind == "nil" then return nil end
    return rest
end

local function folderOf(key)
    return Rec.dir .. "/" .. tostring(key)
end

local function fileOf(key, name)
    return folderOf(key) .. "/" .. tostring(name) .. ".txt"
end

local ENTRY_HINTS = { "Teleport", "Gauntlet" }

-- these are captured in every mode, entry included: they are the things a hand
-- does inside a wave, and a macro that only remembered the teleport was useless
-- the moment you wanted it to play the fight
local ACTION_HINTS = {
    "UpgradeTower",        -- Functions.UpgradeTower - level a tower up
    "SellTower",           -- Functions.SellTower - sell a tower
    "Remotes.Towers.",     -- Remotes.Towers.<unit>.<ability> - most ability casts
    "Remotes.VoteSkip",    -- manual wave skip (X / the skip button)
    "Remotes.AutoSkip",    -- auto skip switched on or off
    "Remotes.SkipWave",
}

-- not every ability lives under Remotes.Towers.<unit>. GojoDomain, SukunaDomain,
-- MahitoDomain and MechaXmassActive sit straight on Remotes, so the prefix above
-- walks right past them. the ability table already knows every one of them, so
-- it is the source instead of guessing at names
local ABILITY_REMOTES = {}
for _, a in pairs(ABILITIES) do
    if a.remote then ABILITY_REMOTES[a.remote] = true end
    for _, x in ipairs(a.extra or {}) do ABILITY_REMOTES[x] = true end
end

local REM_PREFIX = RemotesRoot and (pathOf(RemotesRoot) .. ".") or "\1"

-- the abilities that open a minigame. firing the remote is not the whole cast:
-- Justice Sorcerer opens the timing trial and it has to be played out or the
-- domain dies half way
local QTE_REMOTES = {}
for _, a in pairs(ABILITIES) do
    if a.qte and a.remote then QTE_REMOTES[a.remote] = true end
end

local function wanted(self, full)
    if self.capture == "full" then return true end
    if string.sub(full, 1, #REM_PREFIX) == REM_PREFIX then
        if ABILITY_REMOTES[string.sub(full, #REM_PREFIX + 1)] then return true end
    end
    for _, h in ipairs(ACTION_HINTS) do
        if string.find(full, h, 1, true) then return true end
    end
    for _, h in ipairs(ENTRY_HINTS) do
        if string.find(full, h, 1, true) then return true end
    end
    return false
end

-- the single capture hook: installed lazily, never removed, inert whenever
-- Rec.active is nil or not recording
local function ensureHook()
    if Rec._hookOld then return end
    local old
    old = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local rec = Rec.active
        if rec and rec.recording and not Rec.replaying and typeof(self) == "Instance" then
            -- ClassName, not :IsA. any method call in here is a nested namecall and
            -- it overwrites the name this call is about to be dispatched with: the
            -- original then runs as IsA, so a zero-argument FireServer threw
            -- "Argument 1 missing" and a one-argument one silently never fired.
            local cls = self.ClassName
            local isEvent = (method == "FireServer" and cls == "RemoteEvent")
            local isFunc  = (method == "InvokeServer" and cls == "RemoteFunction")
            if isEvent or isFunc then
                local full = pathOf(self)
                if wanted(rec, full) then
                    local args = table.pack(...)
                    local enc = {}
                    for i = 1, args.n do enc[i] = encodeArg(args[i]) end
                    table.insert(rec.steps, {
                        t = os.clock() - rec.t0,
                        kind = isFunc and "F" or "E",
                        remote = full,
                        args = table.concat(enc, "~"),
                    })
                    if rec.onStep then pcall(rec.onStep, #rec.steps, full) end
                end
            end
        end
        return old(self, ...)
    end)
    Rec._hookOld = old
end

-- switches that live on this window never touch a remote, so they would never
-- reach the hook above. they are logged under a HUB: path and replayed by
-- calling the same function back, in the same slot of the timeline
function Rec.note(action, ...)
    local rec = Rec.active
    if not rec or not rec.recording or Rec.replaying then return end
    local args = table.pack(...)
    local enc = {}
    for i = 1, args.n do enc[i] = encodeArg(args[i]) end
    local full = "HUB:" .. tostring(action)
    table.insert(rec.steps, {
        t = os.clock() - rec.t0,
        kind = "H",
        remote = full,
        args = table.concat(enc, "~"),
    })
    if rec.onStep then pcall(rec.onStep, #rec.steps, full) end
end

function Rec.runHub(action, args)
    if action == "AutoSkip" then
        local on = args and args[1] == true
        local M = Hub.Macros
        if M then
            if on then M.startAutoSkip() else M.stopAutoSkip() end
        end
        pcall(function() Toggles.AutoSkip:SetValue(on) end)
        return true
    end
    return false
end

local Recorder = {}
Recorder.__index = Recorder

function Rec.new(key, opts)
    opts = opts or {}
    local self = setmetatable({}, Recorder)
    self.key      = key
    self.capture  = opts.capture or "full"
    self.name     = opts.name or "macro"
    self.steps    = {}
    self.recording = false
    self.playing   = false
    self.t0       = 0
    self.onStep   = opts.onStep
    self.slots    = nil
    return self
end

function Recorder:start(name)
    if name then self.name = tostring(name) end
    -- a focused textbox swallows every key, including the 1-5 the game uses to
    -- pick a unit from the hotbar, which made placement look broken while
    -- recording. drop the focus the moment REC starts
    pcall(function()
        local tb = UIS:GetFocusedTextBox()
        if tb then tb:ReleaseFocus() end
    end)
    -- one capture at a time: the other tab keeps what it already caught
    if Rec.active and Rec.active ~= self and Rec.active.recording then
        pcall(function() Rec.active:stop(true) end)
    end
    ensureHook()
    Rec.active = self
    self.steps = {}
    -- whatever is in the hotbar right now is part of the take: a macro that
    -- replays a wave is useless if the units it places are not the units you had
    self.slots = Slots.current()
    self.t0 = os.clock()
    self.recording = true
    if self.onStep then pcall(self.onStep, 0, "") end
end

function Recorder:stop(silent)
    local was = self.recording
    self.recording = false
    if Rec.active == self then Rec.active = nil end
    if not was then return 0 end

    local lines = {
        ("# %s | %s | capture=%s | %s"):format(self.key, self.name, self.capture, os.date("%Y-%m-%d %H:%M")),
    }
    if self.slots then
        table.insert(lines, "#slots=" .. Slots.encode(self.slots))
    end
    for _, e in ipairs(self.steps) do
        table.insert(lines, ("%.3f|%s|%s|%s"):format(e.t, e.kind, e.remote, e.args))
    end

    if writefile and #self.steps > 0 then
        pcall(makefolder, folderOf(self.key))
        local ok, err = pcall(writefile, fileOf(self.key, self.name), table.concat(lines, "\n"))
        if not ok then
            setStatus("macro save failed: " .. tostring(err), "bad")
            return 0
        end
    end
    if not silent then
        setStatus(("%s: saved %d step(s) as '%s'"):format(self.key, #self.steps, self.name),
            #self.steps > 0 and "good" or "warn")
    end
    return #self.steps
end

function Recorder:load(name)
    name = tostring(name or self.name)
    if not readfile then return {} end
    local ok, data = pcall(readfile, fileOf(self.key, name))
    if not ok or type(data) ~= "string" then return {} end
    local out = {}
    for line in string.gmatch(data, "[^\n]+") do
        if string.sub(line, 1, 1) ~= "#" then
            local t, kind, remote, args = line:match("^([%d%.]+)|(%a)|([^|]+)|(.*)$")
            if t then
                table.insert(out, { t = tonumber(t) or 0, kind = kind, remote = remote, args = args or "" })
            end
        end
    end
    return out
end

-- the hotbar this macro was recorded with, or nil for a macro written before
-- slots were part of the format
function Recorder:loadSlots(name)
    name = tostring(name or self.name)
    if not readfile then return nil end
    local ok, data = pcall(readfile, fileOf(self.key, name))
    if not ok or type(data) ~= "string" then return nil end
    local line = string.match(data, "#slots=([^\r\n]*)")
    if not line then return nil end
    local map = Slots.decode(line)
    if next(map) == nil then return nil end
    return map
end

function Recorder:names()
    local out = {}
    if not listfiles then return out end
    local ok, files = pcall(listfiles, folderOf(self.key))
    if ok and files then
        for _, f in ipairs(files) do
            local base = tostring(f):match("([^/\\]+)%.txt$")
            if base then table.insert(out, base) end
        end
    end
    table.sort(out)
    return out
end

function Recorder:delete(name)
    name = tostring(name or self.name)
    if not delfile then return false end
    return pcall(delfile, fileOf(self.key, name))
end

function Recorder:stopPlayback()
    self.playing = false
    if self.thread then
        pcall(function() task.cancel(self.thread) end)
        self.thread = nil
    end
    Rec.replaying = false
end

function Recorder:replay(name, opts)
    opts = opts or {}
    local steps = opts.steps or self:load(name)
    if #steps == 0 then
        setStatus(("%s: no macro '%s' yet - press REC, play it, press STOP"):format(self.key, tostring(name or self.name)), "warn")
        return false
    end

    self:stopPlayback()
    -- always at the tempo it was recorded at. a macro is a copy of the input,
    -- not a different take on it, so there is no speed knob and no repeat count.
    self.playing = true
    Rec.replaying = true

    local target = tostring(name or self.name)
    setStatus(("%s: playing %d step(s)"):format(self.key, #steps), nil)

    self.thread = task.spawn(function()
        -- the hotbar goes first and on this thread: the swap waits on the server
        -- several times and a button callback must not be held up by it
        local layout = self:loadSlots(target)
        if layout and Slots.auto then
            local n, why = Slots.apply(layout)
            if n and n > 0 then
                setStatus(("slots: %d swapped for '%s'"):format(n, target), "good")
            elseif why and why ~= "already matches" then
                setStatus(("slots: " .. why), "warn")
            end
            if not self.playing then
                Rec.replaying = false
                self.thread = nil
                return
            end
        end

        local prev = 0
        for _, e in ipairs(steps) do
            if not self.playing then break end
            local dt = math.clamp((e.t or 0) - prev, 0, 30)
            prev = e.t or 0
            if dt > 0 then task.wait(dt) end
            if not self.playing then break end

            local args, argc = {}, 0
            for chunk in string.gmatch(e.args, "[^~]+") do
                argc = argc + 1
                args[argc] = decodeArg(chunk)
            end
            if e.kind == "H" or string.sub(e.remote, 1, 4) == "HUB:" then
                Rec.runHub(string.sub(e.remote, 5), args)
            else
                local rem = resolvePath(e.remote)
                if rem then
                    if e.kind == "F" then
                        pcall(function() rem:InvokeServer(table.unpack(args, 1, argc)) end)
                    else
                        pcall(function() rem:FireServer(table.unpack(args, 1, argc)) end)
                    end
                    if string.sub(e.remote, 1, #REM_PREFIX) == REM_PREFIX
                        and QTE_REMOTES[string.sub(e.remote, #REM_PREFIX + 1)]
                        and Hub.solveOnly then
                        Hub.solveOnly()
                    end
                end
            end
        end
        self.playing = false
        self.thread = nil
        Rec.replaying = false
        setStatus(("%s: playback finished"):format(self.key), "good")
    end)
    return true
end

-- one label updater for every tab
function Rec.statusOf(self)
    if self.recording then
        return ("RECORDING  %d step(s)  -> %s"):format(#self.steps, self.name)
    end
    local n = #self:names()
    return ("macros: %d   selected: %s"):format(n, self.name)
end

--=============================================================
-- TABS 2..6 : ONE TAB PER MODE FAMILY
--=============================================================
-- A dropdown of nine modes was annoying, so every family gets its own tab:
-- Gauntlet/Endless/Challenge share one, the three raids share one, Hakari is
-- called Casino, Sukuna and Story stand alone.
local FAMILIES = {
    { key = "gauntlet", tab = Tabs.Gaunt,  title = "Gauntlet",
      modes = { "gauntlet", "endless", "challenge" },
      note = "gauntlet / endless / challenge" },
    { key = "raids",    tab = Tabs.Raids,  title = "Raids",
      modes = { "raid", "raid_toji", "raid_meg" },
      note = "gojo / toji / meguna - один лифт, три босса" },
    { key = "casino",   tab = Tabs.Casino, title = "Casino",
      modes = { "hakari" },
      note = "hakari - казино" },
    { key = "sukuna",   tab = Tabs.Sukuna, title = "Sukuna",
      modes = { "sukuna" },
      note = "sukuna" },
    { key = "story",    tab = Tabs.Story,  title = "Story",
      modes = { "story" },
      note = "главы - stage + hell" },
}
Modes.families = FAMILIES

-- the automation switches are global, so every tab carries its own copy and a
-- single callback pushes the new value into all the others
local Mirrors = { autoStart = {}, anyStart = {}, autoJoin = {} }
local syncing = false

local function mirrorAdd(kind, widget)
    if widget then table.insert(Mirrors[kind], widget) end
end

local function mirrorPush(kind, v)
    if syncing then return end
    syncing = true
    for _, w in ipairs(Mirrors[kind]) do
        pcall(function() w:SetValue(v) end)
    end
    syncing = false
end

for _, fam in ipairs(FAMILIES) do
    local left  = fam.tab:AddLeftGroupbox(fam.title, "door-open")
    local right = fam.tab:AddRightGroupbox("Automation", "radio")
    fam.sel = Modes.indexOfKey(fam.modes[1]) or 1

    -- a family with more than one mode needs its own picker
    if #fam.modes > 1 then
        local names = {}
        for _, k in ipairs(fam.modes) do
            local m = Modes.byKey(k)
            table.insert(names, m and m.label or k)
        end
        left:AddDropdown(fam.key .. "Pick", {
            Values = names,
            Default = 1,
            Multi = false,
            Text = "mode",
            Callback = function(v)
                local idx = Modes.indexOfLabel(v)
                if idx then
                    fam.sel = idx
                    Modes.selected = idx
                end
            end,
        })
    end

    -- only the story elevator takes a stage and a difficulty
    if fam.key == "story" then
        left:AddSlider("StoryStage", {
            Text = "story stage",
            Default = 1,
            Min = 1,
            Max = 15,
            Rounding = 0,
            Callback = function(v) Modes.storyStage = v end,
        })
        left:AddToggle("Hellmode", {
            Text = "hell mode",
            Default = false,
            Callback = function(v) Modes.hellmode = v end,
        })
    end

    -- a divider only makes sense when a control sits above it
    if #fam.modes > 1 or fam.key == "story" then left:AddDivider() end
    left:AddLabel(fam.note, true)
    left:AddLabel("enter = сам находит лифт, хостит лобби и стартует", true)

    left:AddButton({
        Text = "ENTER " .. string.upper(fam.title),
        Func = function()
            local idx = fam.sel
            local opts = { stage = Modes.storyStage, hellmode = Modes.hellmode }
            task.spawn(function() Modes.enterAuto(idx, opts) end)
        end,
        Tooltip = "finds this mode's elevator, boards it, hosts the lobby and starts it - no clicks needed",
    })

    left:AddButton({
        Text = "EXIT ELEVATOR",
        Func = function()
            local n = Modes.release()
            setStatus(n and "exited the elevator - you can enter another mode now" or "nothing to exit", n and "good" or "warn")
        end,
        Tooltip = "presses the game's own Exit / Leave and fires HostLeave, so the next mode can actually be entered",
    })

    left:AddButton({
        Text = "LEAVE LOBBY",
        Func = function() Modes.leave(fam.sel) end,
    })

    mirrorAdd("autoStart", right:AddToggle(fam.key .. "AutoStart", {
        Text = "auto start",
        Default = CFG.AutoStart,
        Tooltip = "stands on the elevator and keeps pressing Start the moment the server gives you the host slot",
        Callback = function(v)
            if syncing then return end
            CFG.AutoStart = v
            if v then
                Modes.startAutoStart()
                setStatus("auto start on - will keep trying until the match begins", "good")
            else
                Modes.stopAutoStart()
            end
            mirrorPush("autoStart", v)
        end,
    }))

    mirrorAdd("anyStart", right:AddToggle(fam.key .. "AnyStart", {
        Text = "auto start (any mode)",
        Default = false,
        Tooltip = "presses the visible Start / Begin / Ready button wherever it shows up - chapter, mode or elevator",
        Callback = function(v)
            if syncing then return end
            -- the Flow module is declared further down, so go through the hub handle
            local f = Hub.Flow
            if f then f.setAutoStart(v) end
            setStatus(v and "auto start (any mode) on" or "auto start (any mode) off", v and "good" or "warn")
            mirrorPush("anyStart", v)
        end,
    }))

    mirrorAdd("autoJoin", right:AddToggle(fam.key .. "AutoJoin", {
        Text = "auto join",
        Default = false,
        Tooltip = "re-enter the selected mode every time you land in the lobby",
        Callback = function(v)
            if syncing then return end
            if v then Modes.startAutoJoin() else Modes.stopAutoJoin() end
            mirrorPush("autoJoin", v)
        end,
    }))

    --=========================================================
    -- per-tab macro recorder
    --=========================================================
    local rec = Rec.new(fam.key, { capture = "entry", name = fam.key .. "_entry" })
    fam.rec = rec
    Rec.list = Rec.list or {}
    table.insert(Rec.list, rec)

    local macBox = fam.tab:AddRightGroupbox("Macros", "bot")

    macBox:AddInput(fam.key .. "MacroName", {
        Default = rec.name,
        Text = "macro name",
        Placeholder = fam.key .. "_entry",
        Finished = false,
        ClearTextOnFocus = false,
        Callback = function(v) if type(v) == "string" and v ~= "" then rec.name = v end end,
    })

    local function macroValues()
        local n = rec:names()
        if #n == 0 then return { "(none yet)" } end
        return n
    end

    local slotLabel, refreshSlots

    macBox:AddDropdown(fam.key .. "MacroList", {
        Values = macroValues(),
        Default = 1,
        Multi = false,
        Text = "saved",
        Callback = function(v)
            if v and v ~= "(none yet)" then
                local changed = rec.name ~= v
                rec.name = v
                pcall(function() Options[fam.key .. "MacroName"]:SetValue(v) end)
                if refreshSlots then refreshSlots() end
                -- picking a macro puts its hotbar in place, but only when the
                -- name actually moved: the dropdown also fires while a config is
                -- being restored, and swapping the hotbar on load would be rude
                if changed and Slots.auto then
                    task.spawn(function()
                        local lay = rec:loadSlots(v)
                        if not lay then return end
                        local n, why = Slots.apply(lay)
                        if n and n > 0 then
                            setStatus(("slots: %d swapped for '%s'"):format(n, v), "good")
                        elseif why and why ~= "already matches" then
                            setStatus(("slots: " .. why), "warn")
                        end
                    end)
                end
            end
        end,
    })

    slotLabel = macBox:AddLabel("slots: -", true)

    function refreshSlots()
        local lay = rec:loadSlots(rec.name)
        if not lay then
            pcall(function() slotLabel:SetText("slots: not saved in this macro") end)
            return
        end
        pcall(function() slotLabel:SetText("slots: " .. Slots.text(lay)) end)
    end

    macBox:AddDropdown(fam.key .. "Capture", {
        Values = { "entry", "full" },
        Default = 1,
        Multi = false,
        Text = "capture",
        Tooltip = "entry = teleport remotes + upgrades, sells, ability casts and skips. " ..
                  "full = every remote the client sends: towers, casts, confirmations - a whole hand-played wave",
        Callback = function(v) rec.capture = (v == "full") and "full" or "entry" end,
    })

    macBox:AddDivider()

    macBox:AddButton({
        Text = "START REC",
        Func = function()
            local n = Options[fam.key .. "MacroName"].Value
            rec:start(n)
            setStatus(("%s: recording '%s' (%s) - play it by hand now"):format(fam.key, rec.name, rec.capture), "warn")
        end,
        Tooltip = "captures this tab only. starting REC here stops a recorder left running on another tab",
    })

    macBox:AddButton({
        Text = "STOP REC",
        Func = function()
            rec:stop()
            if refreshSlots then refreshSlots() end
        end,
    })

    macBox:AddButton({
        Text = "APPLY SLOTS",
        Func = function()
            local lay = rec:loadSlots(rec.name)
            if not lay then
                setStatus("this macro has no hotbar saved", "warn")
                return
            end
            task.spawn(function()
                local n, why = Slots.apply(lay)
                if n and n > 0 then
                    setStatus(("slots: %d swapped for '%s'"):format(n, rec.name), "good")
                else
                    setStatus("slots: " .. tostring(why or "nothing to do"),
                        (why == "already matches") and nil or "warn")
                end
                if refreshSlots then refreshSlots() end
            end)
        end,
        Tooltip = "put the units this macro was recorded with back into your hotbar, if you still own them",
    })

    macBox:AddButton({
        Text = "PLAY",
        Func = function()
            local n = Options[fam.key .. "MacroList"].Value
            if n == "(none yet)" then n = rec.name end
            rec:replay(n)
        end,
        Tooltip = "fires the recorded remotes again with the original timing",
    })

    macBox:AddButton({
        Text = "STOP PLAY",
        Func = function()
            rec:stopPlayback()
            setStatus(("%s: playback stopped"):format(fam.key), "warn")
        end,
    })

    macBox:AddButton({
        Text = "REFRESH MACROS",
        Func = function()
            pcall(function() Options[fam.key .. "MacroList"]:SetValues(macroValues()) end)
            setStatus(("%s: %d macro(s) on disk"):format(fam.key, #rec:names()), "good")
        end,
    })

    macBox:AddButton({
        Text = "DELETE MACRO",
        Func = function()
            local n = Options[fam.key .. "MacroList"].Value
            if n and n ~= "(none yet)" then
                rec:delete(n)
                pcall(function() Options[fam.key .. "MacroList"]:SetValues(macroValues()) end)
                setStatus("deleted macro '" .. n .. "'", "good")
            end
        end,
        Risky = true,
    })

    fam.macroLabel = macBox:AddLabel("no macro yet", true)

    --=========================================================
    -- per-tab config
    --=========================================================
    local cfgTabBox = fam.tab:AddRightGroupbox("Configs", "folder")

    cfgTabBox:AddInput(fam.key .. "CfgName", {
        Default = fam.key,
        Text = "config name",
        Placeholder = fam.key .. "_default",
        Finished = false,
        ClearTextOnFocus = false,
        Callback = function() end,
    })

    local function cfgValues()
        local c = Hub.Cfg
        local n = c and c.namesOf(fam.key) or {}
        if #n == 0 then return { "(none yet)" } end
        return n
    end

    cfgTabBox:AddDropdown(fam.key .. "CfgList", {
        Values = cfgValues(),
        Default = 1,
        Multi = false,
        Text = "saved",
        Callback = function() end,
    })

    cfgTabBox:AddButton({
        Text = "SAVE CONFIG",
        Func = function()
            local c = Hub.Cfg
            if c then c.saveAs(fam.key, Options[fam.key .. "CfgName"].Value) end
            pcall(function() Options[fam.key .. "CfgList"]:SetValues(cfgValues()) end)
        end,
        Tooltip = "writes this mode's settings to its own folder under STD_Hub_configs",
    })

    cfgTabBox:AddButton({
        Text = "LOAD CONFIG",
        Func = function()
            local c = Hub.Cfg
            local n = Options[fam.key .. "CfgList"].Value
            if c and n and n ~= "(none yet)" then c.loadName(fam.key, n) end
        end,
    })

    cfgTabBox:AddButton({
        Text = "DELETE CONFIG",
        Func = function()
            local c = Hub.Cfg
            local n = Options[fam.key .. "CfgList"].Value
            if c and n and n ~= "(none yet)" then c.deleteName(fam.key, n) end
            pcall(function() Options[fam.key .. "CfgList"]:SetValues(cfgValues()) end)
        end,
        Risky = true,
    })

    cfgTabBox:AddButton({
        Text = "REFRESH CONFIGS",
        Func = function()
            pcall(function() Options[fam.key .. "CfgList"]:SetValues(cfgValues()) end)
            setStatus(("%s: %d config(s) on disk"):format(fam.key, #cfgValues()), "good")
        end,
    })

    fam.cfgLabel = cfgTabBox:AddLabel("configs: 0", true)
end

--=============================================================
-- MACROS MODULE
--=============================================================
local Macros = {}
Hub.Macros = Macros

Macros.autoSkip = false
Macros.autoClaim = false
Macros.threads = {}

local SKIP_WORDS = { "skip", "next", "continue", "confirm", "claim", "collect", "start", "ready", "ok" }

local function textOf(o)
    local t = ""
    pcall(function() if o.Text then t = o.Text end end)
    return t
end

local function invokeFirst(btn)
    local conns = getconnections(btn.Activated)
    if #conns == 0 then return false end
    return pcall(function() conns[1].Function() end)
end

function Macros.clickMatching(words, cooldown)
    if not getconnections then return 0 end
    local n = 0
    Macros._seen = Macros._seen or {}
    local now = os.clock()
    for _, d in ipairs(PG:GetDescendants()) do
        if d:IsA("GuiButton") and d.Visible then
            local name = d.Name:lower()
            local txt = textOf(d):lower()
            local hit = false
            for _, wd in ipairs(words) do
                if name:find(wd, 1, true) or txt:find(wd, 1, true) then hit = true break end
            end
            if hit then
                local last = Macros._seen[d] or 0
                if now - last > (cooldown or 0.8) then
                    Macros._seen[d] = now
                    if invokeFirst(d) then n = n + 1 end
                end
            end
        end
    end
    return n
end

function Macros.startAutoSkip()
    if Macros.autoSkip then return end
    Macros.autoSkip = true
    table.insert(Macros.threads, task.spawn(function()
        while Macros.autoSkip and getgenv().STD_Hub == Hub do
            pcall(function() Macros.clickMatching(SKIP_WORDS, 1.2) end)
            task.wait(0.6)
        end
    end))
end

function Macros.stopAutoSkip() Macros.autoSkip = false end

function Macros.startAutoClaim()
    if Macros.autoClaim then return end
    Macros.autoClaim = true
    table.insert(Macros.threads, task.spawn(function()
        while Macros.autoClaim and getgenv().STD_Hub == Hub do
            pcall(function() Macros.clickMatching({ "claim", "collect", "reward" }, 2.5) end)
            task.wait(2)
        end
    end))
end

function Macros.stopAutoClaim() Macros.autoClaim = false end

--=============================================================
-- FLOW : auto start / exit helper
--=============================================================
-- Every mode puts two buttons on screen once you are in it (or on its elevator):
-- Start and Exit. Instead of guessing remotes, this just presses whichever of
-- them is actually visible - same thing your finger does - so it works in a
-- chapter, in a mode, and on the lobby elevator without knowing the internals.
local Flow = {}
Hub.Flow = Flow

Flow.autoStart = false
Flow.thread = nil
Flow.seen = {}
Flow.LOBBY = 17720162456
Flow.lastPlace = game.PlaceId

local START_WORDS = { "start", "begin", "ready", "fight" }
local EXIT_WORDS  = { "exit", "leave" }

local function inHubGui(inst)
    local p = inst
    while p do
        if p.Name == "Obsidian" then return true end
        p = p.Parent
    end
    return false
end

local function isShown(inst)
    local p = inst
    while p and p ~= game do
        local ok, v = pcall(function() return p.Visible end)
        if ok and v == false then return false end
        p = p.Parent
    end
    return true
end

local function exactHit(btn, words)
    local name = btn.Name:lower()
    local txt = textOf(btn):lower()
    for _, w in ipairs(words) do
        if name == w or txt == w then return true end
    end
    return false
end

-- presses every visible matching button, at most once per cooldown per button
function Flow.press(words, cooldown)
    if not getconnections then return 0 end
    local now = os.clock()
    local n = 0
    for _, d in ipairs(PG:GetDescendants()) do
        if d:IsA("GuiButton") and not inHubGui(d) and exactHit(d, words) and isShown(d) then
            local key = tostring(d)
            if now - (Flow.seen[key] or 0) > (cooldown or 2) then
                Flow.seen[key] = now
                if invokeFirst(d) then n = n + 1 end
            end
        end
    end
    return n
end

function Flow.startNow()
    local n = Flow.press(START_WORDS, 0)
    setStatus(n > 0 and ("pressed %d start button(s)"):format(n) or "no start button on screen", n > 0 and "good" or "warn")
    return n
end

function Flow.exitNow()
    local n = Flow.press(EXIT_WORDS, 0)
    setStatus(n > 0 and ("pressed %d exit button(s)"):format(n) or "no exit button on screen", n > 0 and "good" or "warn")
    return n
end

function Flow.tick()
    if Flow.thread then return end
    Flow.thread = task.spawn(function()
        while Flow.autoStart and getgenv().STD_Hub == Hub do
            local pid = game.PlaceId
            if pid ~= Flow.lastPlace then
                Flow.lastPlace = pid
                Flow.seen = {}
            end

            local n = Flow.press(START_WORDS, 1.6)
            if n > 0 then log(("flow: pressed %d start button(s)"):format(n)) end
            task.wait(0.5)
        end
        Flow.thread = nil
    end)
end

function Flow.setAutoStart(on)
    Flow.autoStart = on and true or false
    if on then Flow.tick() end
end

--=============================================================
-- AUTO EXIT
--=============================================================
-- the end screen is the signal, the remote is the action. GameController wires
-- EndScreen.Exit.Activated straight to ExitGame:FireServer() with no arguments,
-- so firing that remote is byte for byte the call the button makes, without
-- touching the button and without a single argument to get wrong.
-- the guard is per place visit: one exit per match, then it waits for the next
local AutoExit = {}
Hub.AutoExit = AutoExit

-- off, and it stays off. the event map ends a round like any other mode, so a
-- watcher that fires ExitGame on the end screen throws you out of the event
-- between rounds - it has to be asked for, never defaulted on
AutoExit.on        = false
AutoExit.done      = false
AutoExit.fired     = 0
AutoExit.lastPlace = 0
AutoExit.delay     = 1.2
AutoExit.stateDelay = 6      -- longer grace when there is no screen to go by
AutoExit.minAge    = 25
AutoExit.t0        = os.clock()
AutoExit.sawRun    = false
AutoExit._watch    = nil
AutoExit._label    = nil

function AutoExit.screen()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local direct = pg:FindFirstChild("EndScreen")
    if direct then return direct end
    for _, d in ipairs(pg:GetDescendants()) do
        if d.Name == "EndScreen" then return d end
    end
    return nil
end

-- true only when the screen and every ancestor of it are shown
function AutoExit.up()
    local es = AutoExit.screen()
    if not es then return false end
    local n = es
    while n and n ~= game do
        local okv, v = pcall(function() return n.Visible end)
        if okv and v == false then return false end
        local oke, e = pcall(function() return n.Enabled end)
        if oke and e == false then return false end
        n = n.Parent
    end
    return true
end

function AutoExit.fire()
    local ev = RS:FindFirstChild("Events")
    local rem = ev and ev:FindFirstChild("ExitGame")
    if rem then
        local ok = pcall(function() rem:FireServer() end)
        if ok then return "ExitGame" end
    end
    local es = AutoExit.screen()
    local btn = es and es:FindFirstChild("Exit", true)
    if btn then
        local ok = pcall(function()
            local c = getconnections(btn.Activated)
            if c and #c > 0 then c[1].Function() end
        end)
        if ok then return "the game's own button" end
    end
    return nil
end

-- the end screen is only one of the two ways a match ends. endless and the
-- challenge modes can just stop: workspace.Info.GameRunning goes false and the
-- server teleports everyone back on its own. watching that as well means the
-- toggle does the same thing in every mode, instead of only where a screen
-- happens to be shown. the screen is still preferred when it is there, because
-- it appears first
function AutoExit.running()
    local info = workspace:FindFirstChild("Info")
    local v = info and info:FindFirstChild("GameRunning")
    if not v then return nil end
    local ok, val = pcall(function() return v.Value end)
    if not ok then return nil end
    return val == true
end

function AutoExit.stateEnd()
    if not AutoExit.sawRun then return false end
    return AutoExit.running() == false
end

function AutoExit.start()
    if AutoExit._watch then return end
    AutoExit._watch = task.spawn(function()
        while getgenv().STD_Hub == Hub do
            local pid = game.PlaceId
            if pid ~= AutoExit.lastPlace then
                AutoExit.lastPlace = pid
                AutoExit.done = false
                AutoExit.sawRun = false
                AutoExit.t0 = os.clock()
            end
            if AutoExit.running() == true then AutoExit.sawRun = true end

            -- a screen that is already up the instant you arrive is a leftover or
            -- part of the loading sequence, not an ending. it must age first
            local old = (os.clock() - AutoExit.t0) > AutoExit.minAge
            local screen = AutoExit.up()
            local state = (not screen) and AutoExit.stateEnd()
            if AutoExit.on and old and not AutoExit.done and (screen or state) then
                task.wait(screen and AutoExit.delay or AutoExit.stateDelay)
                if AutoExit.up() or AutoExit.stateEnd() then
                    local how = AutoExit.fire()
                    if how then
                        AutoExit.done = true
                        AutoExit.fired = AutoExit.fired + 1
                        setStatus("auto exit: left via " .. how, "good")
                    end
                end
            end

            if AutoExit._label then
                pcall(function()
                    AutoExit._label:SetText(("auto exit: %s   fired: %d"):format(
                        (not AutoExit.on) and "off" or (AutoExit.done and "left" or "watching"),
                        AutoExit.fired))
                end)
            end

            task.wait(0.4)
        end
        AutoExit._watch = nil
    end)
end

function AutoExit.stop()
    AutoExit._watch = nil
end

--=============================================================
-- AUTO REPLAY
--=============================================================
-- exactly one job: when the game puts its end screen up, press the replay
-- button on it. the button already restarts the mode you were just in, so there
-- is nothing to decide and nothing to configure - no elevators, no hosting, no
-- stage picking, no remembered mode. the game knows where you were; this just
-- clicks the thing you would click yourself.
--
-- the press is the real one: the game wires EndScreen.<Replay>.Activated, and
-- getconnections gives back that exact handler, so calling it is byte for byte
-- what a mouse click does. Activate() on a GuiButton runs nothing, and firing a
-- remote by hand would mean guessing its arguments
local Replay = {}
Hub.Replay = Replay

Replay.on        = false
Replay.done      = false
Replay.fired     = 0
Replay.delay     = 1.5
Replay.lastPlace = game.PlaceId
Replay.btn       = nil       -- the button that was pressed, for the label
Replay.dumped    = false     -- the end screen's buttons are logged once
Replay._label    = nil
Replay._watch    = nil

-- the words the game could have used for it. checked against the instance name
-- and its text, so "Replay", "Play Again", "Restart" and "Retry" all land
Replay.words = { "replay", "playagain", "play again", "again", "restart", "retry", "rematch", "another" }

function Replay.screen()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local direct = pg:FindFirstChild("EndScreen")
    if direct then return direct end
    for _, d in ipairs(pg:GetDescendants()) do
        if d.Name == "EndScreen" then return d end
    end
    return nil
end

-- true only when the screen and every ancestor of it are shown
function Replay.up()
    local es = Replay.screen()
    if not es then return false end
    local n = es
    while n and n ~= game do
        local okv, v = pcall(function() return n.Visible end)
        if okv and v == false then return false end
        local oke, e = pcall(function() return n.Enabled end)
        if oke and e == false then return false end
        n = n.Parent
    end
    return true
end

function Replay.button()
    local es = Replay.screen()
    if not es then return nil end
    local list = {}
    for _, d in ipairs(es:GetDescendants()) do
        if d:IsA("GuiButton") then
            list[#list + 1] = d
            local text = ""
            pcall(function() text = tostring(d.Text) end)
            local hay = (d.Name .. " " .. text):lower():gsub("%s", "")
            for _, w in ipairs(Replay.words) do
                if hay:find((w:gsub("%s", "")), 1, true) then return d, list end
            end
        end
    end
    return nil, list
end

function Replay.press(btn)
    if not btn then return nil end
    local ok, err = pcall(function()
        local c = getconnections(btn.Activated)
        if c and #c > 0 then c[1].Function() end
    end)
    if ok then return "button" end
    return nil, err
end

function Replay.start()
    if Replay._watch then return end
    Replay._watch = task.spawn(function()
        while getgenv().STD_Hub == Hub do
            local pid = game.PlaceId
            if pid ~= Replay.lastPlace then
                Replay.lastPlace = pid
                Replay.done = false
            end

            local screen = Replay.up()
            -- log the buttons the first time the screen shows up, so a rename on
            -- the game's side shows up in the console instead of failing silently
            if screen and not Replay.dumped then
                Replay.dumped = true
                local _, list = Replay.button()
                local names = {}
                for _, b in ipairs(list or {}) do
                    local text = ""
                    pcall(function() text = tostring(b.Text) end)
                    names[#names + 1] = b.Name .. '("' .. text .. '")'
                end
                log("replay: end screen buttons = " .. (#names > 0 and table.concat(names, "  ") or "none"))
            end

            if Replay.on and screen and not Replay.done then
                task.wait(Replay.delay)
                if Replay.up() and not Replay.done then
                    local btn = Replay.button()
                    if btn then
                        local how = Replay.press(btn)
                        if how then
                            Replay.done = true
                            Replay.fired = Replay.fired + 1
                            Replay.btn = btn.Name
                            setStatus("auto replay: pressed " .. btn.Name, "good")
                        end
                    else
                        setStatus("auto replay: no replay button on the end screen", "warn")
                    end
                end
            end

            if Replay._label then
                pcall(function()
                    Replay._label:SetText(("replay: %s   runs: %d%s"):format(
                        (not Replay.on) and "off" or (Replay.done and "pressed" or "watching"),
                        Replay.fired,
                        Replay.btn and ("   last: " .. tostring(Replay.btn)) or ""))
                end)
            end
            task.wait(0.4)
        end
        Replay._watch = nil
    end)
end

function Replay.stop()
    Replay._watch = nil
end

--=============================================================
-- TAB 3 : MACROS
--=============================================================
local macroBox = Tabs.Macros:AddLeftGroupbox("Automation", "bot")
local manualBox = Tabs.Macros:AddRightGroupbox("Manual", "hand")

macroBox:AddToggle("AutoSkip", {
    Text = "auto skip / confirm",
    Default = false,
    Tooltip = "clicks any visible Skip / Next / Continue / Confirm button",
    Callback = function(v)
        if v then Macros.startAutoSkip() else Macros.stopAutoSkip() end
        Rec.note("AutoSkip", v == true)
    end,
})

macroBox:AddToggle("AutoClaim", {
    Text = "auto claim",
    Default = false,
    Callback = function(v)
        if v then Macros.startAutoClaim() else Macros.stopAutoClaim() end
    end,
})

macroBox:AddDivider()

AutoExit._label = macroBox:AddLabel("auto exit: watching", true)

macroBox:AddToggle("AutoExit", {
    Text = "auto leave to lobby when the match ends",
    Default = false,
    Tooltip = "fires the same remote the game's own exit button fires - ExitGame - with no arguments. " ..
              "one exit per match, then it waits for the next. it also watches the server state, so a mode " ..
              "that ends without showing an end screen (endless, challenge) is left the same way",
    Callback = function(v)
        AutoExit.on = v == true
        setStatus(v and "auto exit: on" or "auto exit: off", v and "good" or "warn")
    end,
})

Replay._label = macroBox:AddLabel("replay: off   runs: 0", true)

macroBox:AddToggle("AutoReplay", {
    Text = "auto replay when the match ends",
    Default = false,
    Tooltip = "when the game puts its end screen up, this presses the replay button on it. " ..
              "that button already restarts the mode you were in, so nothing else is done: " ..
              "no mode is chosen, no elevator is boarded, nothing is remembered",
    Callback = function(v)
        Replay.on = v == true
        setStatus(v and "auto replay: on" or "auto replay: off", v and "good" or "warn")
    end,
})

macroBox:AddButton({
    Text = "PRESS REPLAY",
    Tooltip = "presses the replay button right now, if the end screen is up",
    Func = function()
        if not Replay.up() then setStatus("no end screen up right now", "warn"); return end
        local btn = Replay.button()
        if not btn then setStatus("no replay button on the end screen", "bad"); return end
        local how, err = Replay.press(btn)
        if how then
            Replay.fired = Replay.fired + 1
            Replay.btn = btn.Name
            setStatus("pressed " .. btn.Name, "good")
        else
            setStatus("press failed: " .. tostring(err), "bad")
        end
    end,
})

AutoExit.start()
Replay.start()

macroBox:AddDivider()

macroBox:AddToggle("SlotAuto", {
    Text = "macro sets the hotbar",
    Default = true,
    Tooltip = "every macro remembers the units that were in your slots when it was recorded. " ..
              "with this on, picking one or playing it swaps the hotbar to match, " ..
              "as long as you still own those units",
    Callback = function(v)
        Slots.auto = v == true
        setStatus(v and "slots: macros may swap the hotbar" or "slots: hotbar left alone", nil)
    end,
})

macroBox:AddDivider()
macroBox:AddLabel("start / exit = the real buttons of the mode you are in, pressed for you", true)
macroBox:AddLabel("REC also catches: tower upgrades and sells, ability casts, manual skip, auto-skip on/off", true)

manualBox:AddButton({
    Text = "START NOW",
    Func = function() Flow.startNow() end,
})

manualBox:AddButton({
    Text = "EXIT NOW",
    Func = function() Flow.exitNow() end,
})

manualBox:AddButton({
    Text = "SKIP / CONFIRM NOW",
    Func = function()
        local n = Macros.clickMatching(SKIP_WORDS, 0)
        setStatus(("clicked %d buttons"):format(n), n > 0 and "good" or "warn")
    end,
})

manualBox:AddButton({
    Text = "CAST ALL NOW",
    Func = function() castAll() end,
})

--=============================================================
-- FREE PLACEMENT
--=============================================================
-- Measured from the decompiled client (StarterGui.GameGui.GameController):
--
--   RequestTower:InvokeServer(towerName, nil, nil, buffedTower)  -> bool
--   SpawnNewTower:InvokeServer(towerUUID, cframe, buffedTower)   -> bool
--
-- RequestTower reserves the tower and takes the gold, SpawnNewTower builds it.
-- The client only ever calls the second one after the first returned true, and
-- the UUID is the tower's instance id from State.GetData().Towers - NOT its
-- name. That is why calling SpawnNewTower on its own always answers false.
--
-- The game's own placement is gated by a raycast: the preview only turns green
-- when the hit part's parent is called "TowerArea" (Map.<map>.TowerArea.Floor
-- on Beach). Everything below builds the CFrame itself, so no pad, no preview
-- and no area check happen on our side.
--
-- Tested live: a tower placed 250 studs off the build floor in mid-air was
-- accepted (SpawnNewTower returned true). The server does not validate the
-- area, only that RequestTower succeeded - so placement really is free-form.
local Place = {}
Hub.Place = Place

-- the autoexec loader re-runs this whole file after every teleport, so a
-- placement hold has to live in getgenv or a reload would forget it and the
-- auto driver would pop the domain of the tower you just built
do
    local left = math.max((getgenv().STD_FreshAt or 0) - os.time(), 0)
    if left > 0 then Place.freshUntil = os.clock() + left end
end

local PlaceFns = RS:FindFirstChild("Functions")
local StateMod = nil
pcall(function() StateMod = require(RS.Client.State) end)

Place.selectedSlot = 1
Place.rotation = 180
Place.clickMode = false
Place.coord = { x = 0, y = 0, z = 0 }

function Place.data()
    if not StateMod then return nil end
    local ok, d = pcall(function() return StateMod.GetData() end)
    return ok and d or nil
end

function Place.gold()
    local g = LP:FindFirstChild("Gold")
    return g and g.Value or 0
end

function Place.placedCount()
    local p = LP:FindFirstChild("PlacedTowers")
    return p and p.Value or 0
end

-- the five towers of the current loadout, in slot order
function Place.equipped()
    local out = {}
    local d = Place.data()
    if not d or type(d.Towers) ~= "table" then return out end
    for i = 1, 5 do
        local v = LP:FindFirstChild("Equipped" .. i)
        local uuid = v and v.Value
        local rec = uuid and d.Towers[uuid]
        if rec then
            table.insert(out, {
                slot = i,
                uuid = uuid,
                name = type(rec) == "table" and rec.Name or tostring(rec),
            })
        end
    end
    return out
end

function Place.current()
    local e = Place.equipped()
    return e[Place.selectedSlot or 1]
end

function Place.template(name)
    local root = RS:FindFirstChild("Towers")
    return root and root:FindFirstChild(name) or nil
end

-- per-type caps: every tower template carries its own MaxTowers (a
-- KingOfCursesEvo is capped at 1, a SorcererAgent at 4). That cap - not the
-- match-wide Info.MaxTowers - is what refuses RequestTower once the loadout is
-- fully built out, and it is invisible unless you count what is on the map.
function Place.placedOf(templateName)
    local out = {}
    local wt = workspace:FindFirstChild("Towers")
    if not wt then return out end
    for _, m in ipairs(wt:GetChildren()) do
        local cfg = m:FindFirstChild("Config")
        local at = cfg and cfg:FindFirstChild("AttackType")
        local key = at and at.Value or m.Name
        if key == templateName or m.Name == templateName then
            table.insert(out, m)
        end
    end
    return out
end

function Place.maxOf(templateName)
    local t = Place.template(templateName)
    local cfg = t and t:FindFirstChild("Config")
    local mt = cfg and cfg:FindFirstChild("MaxTowers")
    return mt and mt.Value or nil
end

function Place.capLine()
    local bits = {}
    for _, e in ipairs(Place.equipped()) do
        local maxT = Place.maxOf(e.name)
        local placed = #Place.placedOf(e.name)
        local full = maxT and placed >= maxT
        table.insert(bits, ("%s %d/%s%s"):format(e.name, placed, maxT and tostring(maxT) or "inf", full and "*" or ""))
    end
    if #bits == 0 then return "no loadout" end
    return table.concat(bits, "   ")
end

function Place.sell(model)
    local f = PlaceFns and PlaceFns:FindFirstChild("SellTower")
    if not f or not model then return false end
    local ok, res = pcall(function() return f:InvokeServer(model) end)
    return ok and res == true
end

function Place.sellNearest(templateName, pos)
    local best, bestD
    for _, m in ipairs(Place.placedOf(templateName)) do
        local pp = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
        if pp then
            local d = (pp.Position - pos).Magnitude
            if not bestD or d < bestD then best, bestD = m, d end
        end
    end
    if not best then return false end
    return Place.sell(best), best, bestD
end

-- same formula the client applies to a raycast hit: stand the tower on the
-- surface using the template's own hip height and primary part size
function Place.cframeAt(name, pos, rotDeg)
    local t = Place.template(name)
    local hip, halfY = 0, 1
    if t then
        local hum = t:FindFirstChildOfClass("Humanoid")
        hip = hum and hum.HipHeight or 0
        local pp = t.PrimaryPart
        halfY = (pp and pp.Size.Y or 2) / 2
    end
    return CFrame.new(pos.X, pos.Y - hip + halfY, pos.Z) * CFrame.Angles(0, math.rad(rotDeg or 0), 0)
end

function Place.rayFromMouse()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local mp = UIS:GetMouseLocation()
    local ray = cam:ViewportPointToRay(mp.X, mp.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = {}
    if LP.Character then table.insert(ignore, LP.Character) end
    local wt = workspace:FindFirstChild("Towers")
    if wt then table.insert(ignore, wt) end
    params.FilterDescendantsInstances = ignore
    return workspace:Raycast(ray.Origin, ray.Direction * 4000, params)
end

local function priceOf(name)
    local t = Place.template(name)
    local cfg = t and t:FindFirstChild("Config")
    local p = cfg and cfg:FindFirstChild("Price")
    return p and p.Value or math.huge
end

-- true while the auto driver must leave freshly built towers alone
function Place.autoCastHeld()
    return Place.freshUntil ~= nil and os.clock() < Place.freshUntil
end

-- two-step, exactly like the client. the third return says which step refused,
-- because a refusal at RequestTower costs nothing while one past it means the
-- gold is already spent and retrying would charge again
function Place.spawn(entry, cf)
    if not entry then return false, "no equipped tower selected", "request" end
    local req = PlaceFns and PlaceFns:FindFirstChild("RequestTower")
    local spw = PlaceFns and PlaceFns:FindFirstChild("SpawnNewTower")
    if not req or not spw then return false, "Functions.RequestTower / SpawnNewTower missing", "request" end

    local ok1, res1 = pcall(function() return req:InvokeServer(entry.name, nil, nil, nil) end)
    if not ok1 then return false, "RequestTower error: " .. tostring(res1), "request" end
    if not res1 then
        return false, "RequestTower refused (gold, this tower's own cap, or the match is not buildable)", "request"
    end

    local ok2, res2 = pcall(function() return spw:InvokeServer(entry.uuid, cf, nil) end)
    if not ok2 then return false, "SpawnNewTower error: " .. tostring(res2), "spawn" end
    if not res2 then return false, "SpawnNewTower refused at that position", "spawn" end
    -- hold the auto driver off the unit that was just built, otherwise placing a
    -- Justice Sorcerer fires its domain the instant it lands
    local grace = CFG.CastGrace or 8
    Place.freshUntil = os.clock() + grace
    getgenv().STD_FreshAt = os.time() + grace
    return true
end

-- the selected slot is often a tower that already hit its own MaxTowers (a
-- KingOfCursesEvo is capped at 1), which used to look like "placement is
-- broken". Try the wanted one first, then the rest of the loadout cheapest
-- first, and stop the moment gold has actually been spent.
function Place.spawnBestAt(pos, prefer, strict)
    -- ONE attempt per call, always. The first version walked the whole loadout
    -- after a refusal, and every refusal makes the game print "not enough
    -- money", so a single click used to spam five messages and fire five
    -- RequestTower calls. The only recovery now is the explicit auto replace.
    local e = prefer or Place.current()
    if not e then return false, nil, "no equipped tower - open the loadout once" end

    local ok, why, stage = Place.spawn(e, Place.cframeAt(e.name, pos, Place.rotation))
    if ok then return true, e end

    if Place.autoReplace and stage == "request" then
        local sold, model, dist = Place.sellNearest(e.name, pos)
        if sold then
            log(("auto replace: sold %s at %.0f studs"):format(e.name, dist or -1))
            task.wait(0.25)
            local ok2, why2 = Place.spawn(e, Place.cframeAt(e.name, pos, Place.rotation))
            if ok2 then return true, e end
            return false, e, why2
        end
    end

    return false, e, why
end

function Place.report(ok, entry, pos, why)
    if ok then
        setStatus(("placed %s at %.0f, %.0f, %.0f"):format(entry and entry.name or "?", pos.X, pos.Y, pos.Z), "good")
    else
        setStatus("place failed: " .. tostring(why), "bad")
    end
end

function Place.placeAtMouse(entry, strict)
    entry = entry or Place.current()
    local hit = Place.rayFromMouse()
    if not hit then setStatus("nothing under the cursor to place on", "warn"); return false end
    local ok, used, why = Place.spawnBestAt(hit.Position, entry, strict)
    Place.report(ok, used or entry, hit.Position, why)
    return ok, used
end

function Place.placeAtMe(entry)
    entry = entry or Place.current()
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then setStatus("no character", "warn"); return false end
    local p = hrp.Position
    local ok, used, why = Place.spawnBestAt(p, entry)
    Place.report(ok, used or entry, p, why)
    return ok, used
end

function Place.placeAtCoords(x, y, z, entry)
    entry = entry or Place.current()
    local p = Vector3.new(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
    local ok, used, why = Place.spawnBestAt(p, entry)
    Place.report(ok, used or entry, p, why)
    return ok, used
end

function Place.overHub(x, y)
    local ok, objs = pcall(function() return LP.PlayerGui:GetGuiObjectsAtPosition(x, y) end)
    if not ok or not objs then return false end
    local hubGui = Library.ScreenGui or (Hub.window and Hub.window.ScreenGui)
    if not hubGui then return false end
    for _, o in ipairs(objs) do
        local root = o
        local guard = 0
        while root and root.Parent and root.Parent ~= LP.PlayerGui and guard < 12 do
            root = root.Parent
            guard = guard + 1
        end
        if root == hubGui then return true end
    end
    return false
end

-- the game builds a temporary clone of the tower model in workspace while you
-- are choosing where to put it; that clone is how we know which unit the
-- hotbar currently has selected
function Place.findPlaceholder()
    for _, c in ipairs(workspace:GetChildren()) do
        if c:IsA("Model") then
            local cfg = c:FindFirstChild("Config")
            if cfg and cfg:FindFirstChild("AttackType") and c:FindFirstChildOfClass("Humanoid") then
                if Place.template(c.Name) then return c end
            end
        end
    end
    return nil
end

function Place.entryForName(name)
    for _, e in ipairs(Place.equipped()) do
        if e.name == name then return e end
    end
    return nil
end

-- every placement goes through here. "hotbar" only ever acts on a unit the
-- player actually picked (Place.pending); with nothing picked a click does
-- nothing at all. "manual" is the explicit click-to-place switch.
function Place.onClick(source)
    if Place._busy then return end
    -- zombie guard: if this closure belongs to a hub that has already been
    -- replaced (re-exec, autoexec reload after a teleport), it must never build
    -- anything. Older builds left their click connection alive, which is why
    -- towers kept appearing after the feature was switched off.
    if getgenv().STD_Hub ~= Hub then return end

    local entry
    if source == "hotbar" then
        entry = Place.pending
        if not entry then return end      -- no unit picked: ignore the click
    else
        -- when the hotbar watcher is armed it owns clicks; letting the manual
        -- switch also fire would build twice from one click
        if Place.autoHotbar then return end
        entry = Place.current()
        if not entry then return end
    end

    Place._busy = true
    local ok = Place.placeAtMouse(entry, true)
    if ok and source == "hotbar" then
        local ph = Place.pendingPlaceholder
        if ph and ph.Parent then pcall(function() ph:Destroy() end) end
        Place.pending = nil
        Place.pendingPlaceholder = nil
    end
    -- debounce: two InvokeServer round trips can outlast a fast double click
    task.wait(0.35)
    Place._busy = false
end

function Place.setClickMode(on)
    Place.clickMode = on
    if Place._manualConn then
        pcall(function() Place._manualConn:Disconnect() end)
        Place._manualConn = nil
    end
    if not on then return end
    Place._manualConn = UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if Place.overHub(input.Position.X, input.Position.Y) then return end
        task.spawn(function() Place.onClick("manual") end)
    end)
end

-- watch the hotbar: the moment the game spawns its placement clone, lock onto
-- that unit, then the next click builds it wherever the cursor points. This is
-- its own connection and it never touches the click-to-place switch, so
-- turning it off really does disarm it.
function Place.setAutoHotbar(on)
    Place.autoHotbar = on
    if Place._autoThread then
        pcall(function() task.cancel(Place._autoThread) end)
        Place._autoThread = nil
    end
    if Place._hotConn then
        pcall(function() Place._hotConn:Disconnect() end)
        Place._hotConn = nil
    end
    Place.pending = nil
    Place.pendingPlaceholder = nil

    if not on then return end

    Place._hotConn = UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if Place.overHub(input.Position.X, input.Position.Y) then return end
        task.spawn(function() Place.onClick("hotbar") end)
    end)

    Place._autoThread = task.spawn(function()
        while Place.autoHotbar and getgenv().STD_Hub == Hub do
            local ph = Place.findPlaceholder()
            if ph then
                local e = Place.entryForName(ph.Name)
                if e then
                    Place.pending = e
                    Place.pendingPlaceholder = ph
                end
            else
                Place.pending = nil
                Place.pendingPlaceholder = nil
            end
            task.wait(0.15)
        end
        Place.pending = nil
        Place.pendingPlaceholder = nil
    end)
end

--=============================================================
-- TAB : PLACE
--=============================================================
local placeBox = Tabs.Place:AddLeftGroupbox("Free placement", "map-pin")
local placeInfo = Tabs.Place:AddRightGroupbox("State", "info")

local function placeValues()
    local out = {}
    for _, e in ipairs(Place.equipped()) do
        table.insert(out, ("%d. %s"):format(e.slot, e.name))
    end
    if #out == 0 then out = { "(no loadout)" } end
    return out
end

placeBox:AddDropdown("PlaceTower", {
    Values = placeValues(),
    Default = 1,
    Multi = false,
    Text = "tower",
    Tooltip = "your five equipped slots - only these can be placed, the server checks the loadout",
    Callback = function(v)
        local slot = tonumber(tostring(v):match("^(%d+)"))
        if slot then Place.selectedSlot = slot end
    end,
})

placeBox:AddSlider("PlaceRot", {
    Text = "rotation",
    Default = 180,
    Min = 0,
    Max = 315,
    Rounding = 0,
    Callback = function(v) Place.rotation = v end,
})

placeBox:AddDivider()

placeBox:AddButton({
    Text = "PLACE AT MOUSE",
    Func = function() Place.placeAtMouse() end,
    Tooltip = "raycasts from the cursor and builds there - no pad, no green/red check",
})

placeBox:AddButton({
    Text = "PLACE AT ME",
    Func = function() Place.placeAtMe() end,
})

placeBox:AddToggle("PlaceClick", {
    Text = "click to place",
    Default = false,
    Tooltip = "every left click on the world places the selected tower there. clicks on this window are ignored",
    Callback = function(v) Place.setClickMode(v) end,
})

placeBox:AddDivider()

placeBox:AddInput("PlaceX", {
    Default = "0", Text = "x", Placeholder = "0", Finished = false, ClearTextOnFocus = false,
    Callback = function(v) Place.coord.x = tonumber(v) or 0 end,
})
placeBox:AddInput("PlaceY", {
    Default = "0", Text = "y", Placeholder = "0", Finished = false, ClearTextOnFocus = false,
    Callback = function(v) Place.coord.y = tonumber(v) or 0 end,
})
placeBox:AddInput("PlaceZ", {
    Default = "0", Text = "z", Placeholder = "0", Finished = false, ClearTextOnFocus = false,
    Callback = function(v) Place.coord.z = tonumber(v) or 0 end,
})

placeBox:AddButton({
    Text = "PLACE AT COORDS",
    Func = function() Place.placeAtCoords(Place.coord.x, Place.coord.y, Place.coord.z) end,
})

placeBox:AddToggle("PlaceReplace", {
    Text = "auto replace when capped",
    Default = false,
    Tooltip = "every tower type has its own MaxTowers (KingOfCursesEvo 1, SorcererAgent 4). " ..
              "when the server refuses because that type is full, sell the same type sitting closest " ..
              "to the click and build again - one sale per attempt",
    Callback = function(v) Place.autoReplace = v end,
})

placeBox:AddButton({
    Text = "SELL UNDER CURSOR",
    Func = function()
        local hit = Place.rayFromMouse()
        if not hit then setStatus("nothing under the cursor", "warn"); return end
        local best, bestD
        local wt = workspace:FindFirstChild("Towers")
        for _, m in ipairs(wt and wt:GetChildren() or {}) do
            local pp = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
            if pp then
                local d = (pp.Position - hit.Position).Magnitude
                if d < 30 and (not bestD or d < bestD) then best, bestD = m, d end
            end
        end
        if not best then setStatus("no tower within 30 studs of the cursor", "warn"); return end
        local ok = Place.sell(best)
        setStatus(ok and ("sold " .. best.Name) or ("could not sell " .. best.Name), ok and "good" or "bad")
    end,
    Tooltip = "sells the nearest tower to the cursor, within 30 studs",
})

placeBox:AddButton({
    Text = "REFRESH LOADOUT",
    Func = function()
        pcall(function() Options.PlaceTower:SetValues(placeValues()) end)
        setStatus(("%d tower(s) in the loadout"):format(#Place.equipped()), "good")
    end,
})

placeInfo:AddButton({
    Text = "PROBE SERVER RULES",
    Func = function()
        local e = Place.current()
        if not e then setStatus("no equipped tower", "warn"); return end
        local floor = workspace:FindFirstChild("Map")
        local area
        for _, c in ipairs(workspace:GetDescendants()) do
            if c.Name == "TowerArea" and c:IsA("Folder") then
                area = c:FindFirstChildWhichIsA("BasePart")
                break
            end
        end
        if area then
            local p = area.Position + Vector3.new(0, area.Size.Y / 2, 0)
            setStatus(("build floor at %.0f, %.0f, %.0f - press PLACE AT COORDS with these to test"):format(p.X, p.Y, p.Z), nil)
            log(("TowerArea floor: %s  pos=%s size=%s"):format(area:GetFullName(), tostring(area.Position), tostring(area.Size)))
            flushLog()
        else
            setStatus("no TowerArea part on this map", "warn")
        end
    end,
})

placeInfo:AddDivider()
placeInfo:AddLabel("RequestTower then SpawnNewTower", true)
placeInfo:AddLabel("uuid comes from the loadout, not the name", true)
placeInfo:AddLabel("build floor: Map.TowerArea.Floor, one per map", true)
placeInfo:AddDivider()
placeInfo:AddLabel("per-type cap, * means full", true)
Hub._capLabel = placeInfo:AddLabel("caps", true)
placeInfo:AddDivider()
Hub._placeLabel = placeInfo:AddLabel("ready", true)

table.insert(Hub.threads, task.spawn(function()
    while getgenv().STD_Hub == Hub do
        if Hub._placeLabel then
            local e = Place.current()
            pcall(function()
                Hub._placeLabel:SetText(("%s   gold %d   placed %d"):format(
                    e and e.name or "no loadout", Place.gold(), Place.placedCount()))
            end)
        end
        if Hub._capLabel then
            pcall(function() Hub._capLabel:SetText(Place.capLine()) end)
        end
        task.wait(1)
    end
end))

--=============================================================
-- CONFIG
--=============================================================
local Cfg = {}
Hub.Cfg = Cfg
Cfg.dir       = "STD_Hub_configs"
Cfg.currentOf = {}      -- modeKey -> selected config name
Cfg.current   = ""
Cfg.names     = {}
Cfg.key       = "gauntlet"   -- what the global Config tab is looking at
-- plain text on purpose: the dropdown font renders an em dash as three dashes
Cfg.EMPTY     = "no configs yet"
Cfg.MODE_KEYS = {}
for _, fam in ipairs(Modes.families or {}) do table.insert(Cfg.MODE_KEYS, fam.key) end
if makefolder then pcall(makefolder, Cfg.dir) end

local function cfgDirOf(key)
    return Cfg.dir .. "/" .. tostring(key)
end

local function cfgPath(key, name)
    return cfgDirOf(key) .. "/" .. tostring(name) .. ".txt"
end

local function familyOf(key)
    for _, fam in ipairs(Modes.families or {}) do
        if fam.key == key then return fam end
    end
    return nil
end

local function snapshot(key)
    local fam = familyOf(key)
    return {
        mode       = fam and fam.sel or Modes.selected,
        modeKey    = tostring(key),
        autoSolve  = CFG.AutoSolve,
        stage      = Modes.storyStage,
        hell       = Modes.hellmode,
        castDelay  = CFG.CastDelay,
        castSel    = Caster.mode == "selected",
        castAll    = Caster.mode == "all",
        autoSkip   = Macros.autoSkip,
        autoClaim  = Macros.autoClaim,
        antiAfk    = (Hub.Move == nil) or Hub.Move.on,
        plazaLeave = (Hub.Plaza == nil) or Hub.Plaza.on,
        autoExit   = (Hub.AutoExit == nil) or Hub.AutoExit.on,
        autoJoin   = Modes.autoJoin,
        autoStart  = Modes.autoStart,
        flowStart  = Flow.autoStart,
    }
end

local function apply(t, key)
    CFG.AutoSolve = t.autoSolve ~= false and t.autoSolve ~= "false"
    Modes.selected = math.clamp(tonumber(t.mode) or 1, 1, #Modes.list)
    Modes.storyStage = math.clamp(tonumber(t.stage) or 1, 1, 15)
    Modes.hellmode = t.hell == true or t.hell == "true"
    Hub.setCastDelay((tonumber(t.castDelay) or CFG.CastDelay) * 10)

    -- drive the widgets, not the raw flags, so the callbacks do the work
    pcall(function() Toggles.AutoQTE:SetValue(CFG.AutoSolve) end)
    pcall(function() Toggles.Hellmode:SetValue(Modes.hellmode) end)
    local wantSel = t.castSel == true or t.castSel == "true"
    local wantAll = t.castAll == true or t.castAll == "true"
    pcall(function() Toggles.AutoCastSel:SetValue(wantSel) end)
    pcall(function() Toggles.AutoCastAll:SetValue(wantAll) end)
    pcall(function() Toggles.AutoSkip:SetValue(t.autoSkip == true or t.autoSkip == "true") end)
    pcall(function() Toggles.AutoClaim:SetValue(t.autoClaim == true or t.autoClaim == "true") end)
    if t.antiAfk ~= nil then
        pcall(function() Toggles.AntiAfk:SetValue(t.antiAfk == true or t.antiAfk == "true") end)
    end
    -- auto-exit is deliberately not restored from a config: a saved "true" from
    -- before would re-arm it on every load and start dropping you out of the
    -- event again. it is turned on by hand, per session, or not at all
    pcall(function() Toggles.AutoExit:SetValue(false) end)
    if t.plazaLeave ~= nil then
        pcall(function() Toggles.PlazaLeave:SetValue(t.plazaLeave == true or t.plazaLeave == "true") end)
    end
    -- the automation switches exist once per mode tab; setting one mirrors the rest
    pcall(function() Toggles.gauntletAutoJoin:SetValue(t.autoJoin == true or t.autoJoin == "true") end)
    pcall(function() Toggles.gauntletAutoStart:SetValue(t.autoStart == true or t.autoStart == "true") end)
    pcall(function() Toggles.gauntletAnyStart:SetValue(t.flowStart == true or t.flowStart == "true") end)

    -- point the picker of the tab this config belongs to
    local m = Modes.list[Modes.selected]
    if m then
        for _, fam in ipairs(Modes.families or {}) do
            for _, k in ipairs(fam.modes) do
                if k == m.key then
                    fam.sel = Modes.selected
                    pcall(function() Options[fam.key .. "Pick"]:SetValue(m.label) end)
                end
            end
        end
    end
    pcall(function() Options.StoryStage:SetValue(Modes.storyStage) end)
end

local function serialize(key)
    local t = snapshot(key)
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys)
    local lines = {}
    for _, k in ipairs(keys) do table.insert(lines, k .. "=" .. tostring(t[k])) end
    return table.concat(lines, "\n")
end

function Cfg.namesOf(key)
    local out = {}
    if not listfiles then return out end
    local ok, files = pcall(listfiles, cfgDirOf(key))
    if ok and files then
        for _, f in ipairs(files) do
            local base = tostring(f):match("([^/\\]+)%.txt$")
            if base then table.insert(out, base) end
        end
    end
    table.sort(out)
    return out
end

-- refreshes the GLOBAL tab list (Cfg.key), the per-tab lists refresh themselves
function Cfg.refresh()
    local key = Cfg.key or "gauntlet"
    Cfg.names = Cfg.namesOf(key)
    local cur = Cfg.currentOf[key] or ""
    if cur ~= "" then
        local alive = false
        for _, n in ipairs(Cfg.names) do
            if n == cur then alive = true break end
        end
        if not alive then Cfg.currentOf[key] = "" end
    end
    local values = {}
    for _, n in ipairs(Cfg.names) do table.insert(values, n) end
    if #values == 0 then values = { Cfg.EMPTY } end
    -- SetValues clears the selected value, so pick one back afterwards
    local pick = values[1]
    for _, n in ipairs(values) do
        if n == Cfg.currentOf[key] then pick = n break end
    end
    pcall(function()
        Options.CfgList:SetValues(values)
        Options.CfgList:SetValue(pick)
    end)
    if Hub._cfgLabel then
        pcall(function()
            Hub._cfgLabel:SetText(("configs: %d  (%s)"):format(#Cfg.names,
                (Cfg.currentOf[key] ~= "" and Cfg.currentOf[key]) or "none"))
        end)
    end
    return Cfg.names
end

function Cfg.saveAs(key, name)
    key = tostring(key or Cfg.key or "gauntlet")
    name = tostring(name or ""):gsub("[^%w_%-]", "")
    if name == "" then
        setStatus("config name is empty - type one first", "bad")
        return
    end
    if not writefile then setStatus("writefile unavailable", "bad"); return end
    pcall(makefolder, cfgDirOf(key))
    local ok, err = pcall(writefile, cfgPath(key, name), serialize(key))
    if not ok then setStatus("save failed: " .. tostring(err), "bad"); return end
    Cfg.currentOf[key] = name
    Cfg.refresh()
    setStatus(("saved '%s' under %s"):format(name, key), "good")
end

function Cfg.loadName(key, name)
    key = tostring(key or Cfg.key or "gauntlet")
    name = tostring(name or Cfg.currentOf[key] or "")
    if name == "" or name == Cfg.EMPTY then setStatus("pick a config first", "warn"); return end
    local ok, data = pcall(readfile, cfgPath(key, name))
    if not ok or not data then setStatus("config '" .. name .. "' not found", "bad"); return end
    local t = {}
    for k, v in string.gmatch(data, "([%w_]+)=([^\n]+)") do t[k] = v end
    apply(t, key)
    Cfg.currentOf[key] = name
    Cfg.refresh()
    setStatus(("loaded '%s' (%s)"):format(name, key), "good")
end

function Cfg.deleteName(key, name)
    key = tostring(key or Cfg.key or "gauntlet")
    name = tostring(name or Cfg.currentOf[key] or "")
    if name == "" or name == Cfg.EMPTY then setStatus("pick a config first", "warn"); return end
    if not delfile then setStatus("delfile unavailable", "bad"); return end
    local ok = pcall(delfile, cfgPath(key, name))
    if not ok then setStatus("delete failed", "bad"); return end
    if Cfg.currentOf[key] == name then Cfg.currentOf[key] = "" end
    Cfg.refresh()
    setStatus(("deleted '%s' (%s)"):format(name, key), "good")
end

local cfgBox = Tabs.Cfg:AddLeftGroupbox("Configs", "folder")
local infoBox = Tabs.Cfg:AddRightGroupbox("Info", "info")

cfgBox:AddDropdown("CfgMode", {
    Values = Cfg.MODE_KEYS,
    Default = 1,
    Multi = false,
    Text = "mode",
    Tooltip = "which mode's config folder this tab browses - every mode tab keeps its own set",
    Callback = function(v)
        if v and v ~= "" then
            Cfg.key = v
            Cfg.refresh()
        end
    end,
})

cfgBox:AddInput("CfgName", {
    Default = "",
    Text = "config name",
    Placeholder = "e.g. gauntlet_higuruma",
    Finished = false,
    ClearTextOnFocus = false,
    Callback = function() end,
})

cfgBox:AddButton({
    Text = "CREATE CONFIG",
    Func = function() Cfg.saveAs(Cfg.key, Options.CfgName.Value) end,
    Tooltip = "writes this mode's settings (picker, stage, hell, qte, macros) into its own folder",
})

cfgBox:AddDropdown("CfgList", {
    Values = { Cfg.EMPTY },
    Default = 1,
    Multi = false,
    Text = "list cfg",
    Callback = function(v)
        if v and v ~= Cfg.EMPTY then Cfg.currentOf[Cfg.key] = v end
    end,
})

cfgBox:AddDivider()

cfgBox:AddButton({
    Text = "SAVE CFG",
    Func = function()
        local n = Options.CfgName.Value
        if n == nil or n == "" then n = Cfg.currentOf[Cfg.key] end
        Cfg.saveAs(Cfg.key, n)
    end,
    Tooltip = "overwrites the named config (or the selected one if the name box is empty)",
})

cfgBox:AddButton({
    Text = "LOAD CFG",
    Func = function() Cfg.loadName(Cfg.key, Options.CfgList.Value) end,
})

cfgBox:AddButton({
    Text = "REFRESH CFG",
    Func = function()
        local n = Cfg.refresh()
        setStatus(("%d config(s) in %s"):format(#n, Cfg.key), "good")
    end,
})

cfgBox:AddButton({
    Text = "DELETE CFG",
    Func = function() Cfg.deleteName(Cfg.key, Options.CfgList.Value) end,
    Risky = true,
    Tooltip = "removes the selected config file",
})

Hub._cfgLabel = cfgBox:AddLabel("configs: 0", true)

cfgBox:AddDivider()
cfgBox:AddButton({
    Text = "UNLOAD HUB",
    Func = function() pcall(function() Hub.destroy() end) end,
})

infoBox:AddButton({
    Text = "TOWER REPORT",
    Func = function()
        local list = scanTowers()
        log(("towers on map: %d"):format(#list))
        for _, e in ipairs(list) do
            log(("  %s lvl=%s remote=%s"):format(e.attack, tostring(e.level), tostring(e.remote ~= nil)))
        end
        flushLog()
        setStatus(("report written, %d tower(s)"):format(#list), "good")
    end,
})

infoBox:AddDivider()
infoBox:AddLabel("status")
Hub._statusLabel = infoBox:AddLabel("ready", true)

infoBox:AddDivider()
infoBox:AddLabel("configs live in")
infoBox:AddLabel("workspace/STD_Hub_configs/", true)
infoBox:AddLabel("one .txt per config, plain key=value, so you can edit or share them by hand", true)

--=============================================================
-- LIVE LOOPS
--=============================================================
local function refresh(force)
    local list = scanTowers()
    towerList = list

    local sig = {}
    for _, e in ipairs(list) do table.insert(sig, e.name .. "|" .. tostring(e.level)) end
    local s = table.concat(sig, ",")
    if force or s ~= Hub._sig then
        Hub._sig = s
        local values = {}
        for _, e in ipairs(list) do table.insert(values, displayOf(e)) end
        if #values == 0 then values = { "no towers on the map" } end
        pcall(function()
            Options.TowerPick:SetValues(values)
            -- same gotcha as the config list: SetValues wipes the selection
            if not Options.TowerPick.Value then Options.TowerPick:SetValue(values[1]) end
        end)
        pcall(function() Hub._countLabel:SetText(("%d tower(s)"):format(#list)) end)
    end
    return list
end
Hub.refresh = refresh

table.insert(Hub.threads, task.spawn(function()
    while getgenv().STD_Hub == Hub do
        pcall(refresh, false)
        task.wait(CFG.Rescan)
    end
end))

table.insert(Hub.threads, task.spawn(function()
    while getgenv().STD_Hub == Hub do
        local q = qteFolder()
        if q and q:FindFirstChild("InQTE") and q.InQTE.Value then
            local p = q:FindFirstChild("Points")
            if p and Hub._gaugeLabel then
                local st = Hub.qteStats
                local extra = ""
                if st and st.clicks > 0 then
                    extra = ("   hit %.0f%%   aim %.0f%%"):format(
                        st.hits / st.clicks * 100, (st.edge or 0) * 100)
                end
                pcall(function()
                    Hub._gaugeLabel:SetText(("%.1f / %.0f%s"):format(p.Value, CFG.TargetPts, extra))
                end)
            end
        end
        task.wait(0.2)
    end
end))

table.insert(Hub.threads, task.spawn(function()
    while getgenv().STD_Hub == Hub do
        -- one label per mode tab, plus the config counter under it
        for _, fam in ipairs(Modes.families or {}) do
            local rec = fam.rec
            if rec and fam.macroLabel then
                pcall(function() fam.macroLabel:SetText(Rec.statusOf(rec)) end)
            end
            if fam.cfgLabel then
                local c = Hub.Cfg
                local n = c and #c.namesOf(fam.key) or 0
                local cur = c and c.currentOf[fam.key] or nil
                pcall(function()
                    fam.cfgLabel:SetText(("configs: %d  (%s)"):format(n, cur and cur ~= "" and cur or "none"))
                end)
            end
        end
        task.wait(1)
    end
end))

--=============================================================
-- BOOT
--=============================================================
buildTemplateIndex()
pcall(function() Cfg.refresh() end)
local initial = refresh(true)
if CFG.AutoSolve then Hub.startAuto() end
-- The executor does not survive a teleport, so this script simply does not exist
-- while the match loads. That makes "collisions off on teleport" a load-time job:
-- if we are not in the lobby, we are inside a mode, so they go off right now
-- without any toggle. In the lobby a short window covers the elevator jump.
if Noclip.inMatch() then
    Noclip.tick()
    Noclip.apply()
    log("inside a mode - collisions off automatically")
else
    Noclip.arm(5)
end
if CFG.AutoStart then Modes.startAutoStart() end
log(("hub v7 loaded, %d ability tower(s), %d mode tab(s) with their own recorder"):format(#initial, #(Modes.families or {})))
flushLog()

Hub.scan = scanTowers
Hub.castAll = castAll
Hub.ABILITIES = ABILITIES
Hub.farmQTE = farmQTE
Hub.solveOnce = solveOnce
Hub.points = points
Hub.playTrial = playTrial
Hub.qte = function() return qteFolder() end
Hub.solver = Solver
Hub.CFG = CFG
Hub.Tabs = Tabs
-- handles so external scripts (and my own probes) can drive widgets directly
Hub.OptionsRef = Options
--=============================================================
-- PERSIST : keep the last used settings
--=============================================================
-- Every widget the library creates is registered in Library.Toggles /
-- Library.Options, so instead of hand-listing fields we snapshot the whole
-- pair of tables into one plain text file and push it back on load. The loop
-- only writes when the snapshot actually changed, so idle cost is one string
-- compare every two seconds.
local Persist = {}
Hub.Persist = Persist
-- per account for the same reason the log is: the settings file is a single
-- blob of every toggle in the hub, and with several clients on one machine each
-- one restored and then re-saved the others' choices. an alt switching its own
-- auto qte off used to switch it off on the main
Persist.file     = "STD_Hub_last_" .. LP.Name .. ".txt"
Persist.enabled  = true
Persist._last    = nil
Persist._thread  = nil
Persist._loading = false

-- volatile widgets: text boxes, capture buffers, live list pickers. Restoring
-- a stale value there is either useless or actively wrong, so skip them
local SKIP_OPT = { "Capture", "MacroList", "CfgList", "TowerPick", "Name", "List", "Search" }

local function skipOption(name)
    for _, w in ipairs(SKIP_OPT) do
        if string.find(name, w, 1, true) then return true end
    end
    return false
end

local SEP = string.char(30)

local function enc(v)
    local t = type(v)
    if t == "boolean" then return "b" .. (v and "1" or "0") end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return nil end
        return "n" .. tostring(v)
    end
    if t == "string" then
        if v == "" or string.find(v, "\n", 1, true) then return nil end
        return "s" .. v
    end
    if t == "table" then
        local parts = {}
        for _, x in ipairs(v) do
            local tx = type(x)
            if tx == "string" or tx == "number" then parts[#parts + 1] = tostring(x) end
        end
        if #parts == 0 then return nil end
        return "t" .. table.concat(parts, SEP)
    end
    return nil
end

local function dec(s)
    local tag, rest = string.sub(s, 1, 1), string.sub(s, 2)
    if tag == "b" then return rest == "1" end
    if tag == "n" then return tonumber(rest) end
    if tag == "s" then return rest end
    if tag == "t" then
        local out = {}
        for piece in string.gmatch(rest .. SEP, "([^" .. SEP .. "]*)" .. SEP) do
            table.insert(out, piece)
        end
        if #out == 0 then return nil end
        return out
    end
    return nil
end

function Persist.snapshot()
    local lines = {}
    for name, t in pairs(Library.Toggles) do
        local ok, v = pcall(function() return t.Value end)
        local e = ok and enc(v)
        if e then table.insert(lines, "T\t" .. tostring(name) .. "\t" .. e) end
    end
    for name, o in pairs(Library.Options) do
        if not skipOption(tostring(name)) then
            local ok, v = pcall(function() return o.Value end)
            local e = ok and enc(v)
            if e then table.insert(lines, "O\t" .. tostring(name) .. "\t" .. e) end
        end
    end
    table.sort(lines)
    return table.concat(lines, "\n")
end

function Persist.apply(txt)
    if type(txt) ~= "string" or txt == "" then return 0 end
    Persist._loading = true
    local n = 0
    for kind, name, val in string.gmatch(txt, "([TO])\t([^\t\n]+)\t([^\n]*)") do
        local v = dec(val)
        if v ~= nil then
            local target = (kind == "T") and Library.Toggles[name] or Library.Options[name]
            if target then
                local ok = pcall(function() target:SetValue(v) end)
                if ok then n = n + 1 end
            end
        end
    end
    task.wait(0.25)
    Persist._loading = false
    return n
end

function Persist.start()
    if Persist._thread then return end
    Persist._thread = task.spawn(function()
        local restored = false
        if readfile then
            local ok, data = pcall(readfile, Persist.file)
            if ok and type(data) == "string" and #data > 0 then
                local n = Persist.apply(data)
                restored = n > 0
                setStatus(("settings restored: %d value(s)"):format(n), "good")
            end
        end
        Persist._last = Persist.snapshot()
        -- first run: nothing on disk yet, so lay down a baseline right away
        if not restored and writefile then
            pcall(function() writefile(Persist.file, Persist._last) end)
        end
        while getgenv().STD_Hub == Hub do
            if Persist.enabled and not Persist._loading and writefile then
                local snap = Persist.snapshot()
                if snap ~= Persist._last then
                    Persist._last = snap
                    pcall(function() writefile(Persist.file, snap) end)
                end
            end
            task.wait(2)
        end
        Persist._thread = nil
    end)
end

function Persist.stop()
    Persist.enabled = false
end

local persistBox = Tabs.Cfg:AddRightGroupbox("Last session", "save")

persistBox:AddToggle("PersistOn", {
    Text = "remember settings",
    Default = true,
    Tooltip = "every toggle, slider and picker is written to STD_Hub_last.txt and " ..
              "restored the next time the hub loads",
    Callback = function(v)
        Persist.enabled = v
        if v then
            Persist._last = nil
            setStatus("settings will be remembered again", "good")
        else
            setStatus("settings are no longer saved", "warn")
        end
    end,
})

persistBox:AddButton({
    Text = "SAVE NOW",
    Func = function()
        if not writefile then setStatus("writefile unavailable", "bad") return end
        local snap = Persist.snapshot()
        local ok, err = pcall(writefile, Persist.file, snap)
        if ok then
            Persist._last = snap
            setStatus("settings written to " .. Persist.file, "good")
        else
            setStatus("save failed: " .. tostring(err), "bad")
        end
    end,
    Tooltip = "force a write instead of waiting for the next change",
})

persistBox:AddButton({
    Text = "WIPE SAVED SETTINGS",
    Func = function()
        if not delfile then setStatus("delfile unavailable", "bad") return end
        local ok = pcall(delfile, Persist.file)
        Persist._last = nil
        setStatus(ok and "saved settings wiped" or "wipe failed", ok and "good" or "bad")
    end,
    Tooltip = "delete STD_Hub_last.txt - the next load starts from defaults",
})

Hub._persistLabel = persistBox:AddLabel("file: " .. Persist.file, true)

task.defer(function() Persist.start() end)

Hub.TogglesRef = Toggles
Hub.LibraryRef = Library

--=============================================================
-- CULLING GAMES
--=============================================================
local Culling = {}
Hub.Culling = Culling

Culling.maps = {
    { level = 1,  name = "Kagoshima 1",       colony = "Colony1" },
    { level = 2,  name = "Kagoshima 2",       colony = "Colony1" },
    { level = 3,  name = "Kyoto 1",           colony = "Colony2" },
    { level = 4,  name = "Kyoto 2",           colony = "Colony2" },
    { level = 5,  name = "Industrial Tokyo 1", colony = "Colony3" },
    { level = 6,  name = "Industrial Tokyo 2", colony = "Colony3" },
    { level = 7,  name = "Urban Tokyo 1",     colony = "Colony4" },
    { level = 8,  name = "Urban Tokyo 2",     colony = "Colony4" },
    { level = 9,  name = "Sendai City 1",     colony = "Colony5" },
    { level = 10, name = "Sendai City 2",     colony = "Colony5" },
}

local CG_BY_LEVEL, CG_BY_NAME = {}, {}
for _, m in ipairs(Culling.maps) do
    CG_BY_LEVEL[m.level] = m
    CG_BY_NAME[m.name] = m
end

Culling.pick = "auto"
Culling.autoRun = false
Culling.autoJoin = false
Culling.autoUpgrade = false
Culling.joinLevel = 1
Culling.thread = nil
Culling.lastLevel = nil
Culling.lastMap = nil

local function cgFolder()
    local info = workspace:FindFirstChild("Info")
    return info and info:FindFirstChild("CullingGames")
end

function Culling.inMatch()
    local cg = cgFolder()
    local v = cg and cg:FindFirstChild("IsCullingGames")
    return (v and v.Value) == true
end

function Culling.level()
    local cg = cgFolder()
    local v = cg and cg:FindFirstChild("Level")
    return v and v.Value or nil
end

function Culling.colony()
    local map = workspace:FindFirstChild("Map")
    if not map then return nil end
    for _, c in ipairs(map:GetChildren()) do
        if c.Name:match("^Colony%d+$") then return c.Name end
    end
    return nil
end

function Culling.detected()
    if not Culling.inMatch() then return nil end
    local lv = Culling.level()
    if lv and CG_BY_LEVEL[lv] then return CG_BY_LEVEL[lv] end
    return nil
end

function Culling.target()
    if Culling.pick ~= "auto" and CG_BY_NAME[Culling.pick] then
        return CG_BY_NAME[Culling.pick]
    end
    return Culling.detected()
end

--=============================================================
-- storage: one macro per level, spots captured from a live match
--=============================================================
local MACRO_FILE = "STD_Culling_macros.json"

local function jsonEncode(v)
    local ok, s = pcall(function() return game:GetService("HttpService"):JSONEncode(v) end)
    return ok and s or nil
end

local function jsonDecode(s)
    local ok, v = pcall(function() return game:GetService("HttpService"):JSONDecode(s) end)
    return ok and v or nil
end

Culling.data = {}

function Culling.loadMacros()
    Culling.data = {}
    if not readfile or not isfile then return end
    local ok = pcall(function() return isfile(MACRO_FILE) end)
    if not ok then return end
    local exists = false
    pcall(function() exists = isfile(MACRO_FILE) end)
    if not exists then return end
    local raw
    pcall(function() raw = readfile(MACRO_FILE) end)
    local t = raw and jsonDecode(raw)
    if type(t) == "table" then Culling.data = t end
end

function Culling.saveMacros()
    local s = jsonEncode(Culling.data)
    if s and writefile then pcall(function() writefile(MACRO_FILE, s) end) end
end

function Culling.macroOf(level)
    local m = Culling.data[tostring(level)]
    if type(m) == "table" and type(m.spots) == "table" then return m end
    return nil
end

function Culling.spotCount(level)
    local m = Culling.macroOf(level)
    return m and #m.spots or 0
end

--=============================================================
-- towers: what is on the map and what is in the loadout
--=============================================================
local StateMod = nil
pcall(function() StateMod = require(RS:WaitForChild("Client"):WaitForChild("State")) end)

local function stateData()
    if not StateMod then return nil end
    local ok, d = pcall(function() return StateMod.GetData() end)
    return ok and d or nil
end

function Culling.equipped()
    local out, byName = {}, {}
    local d = stateData()
    if not d or type(d.Towers) ~= "table" then return out, byName end
    for slot = 1, 5 do
        local v = LP:FindFirstChild("Equipped" .. slot)
        local uuid = v and v.Value
        local rec = uuid and d.Towers[uuid]
        if rec then
            local nm = type(rec) == "table" and rec.Name or tostring(rec)
            local e = { slot = slot, uuid = uuid, name = nm }
            table.insert(out, e)
            byName[nm] = e
        end
    end
    return out, byName
end

function Culling.gold()
    local g = LP:FindFirstChild("Gold")
    return g and g.Value or 0
end

function Culling.towerOwner(model)
    local cfg = model:FindFirstChild("Config")
    local own = cfg and cfg:FindFirstChild("Owner")
    if own then return tostring(own.Value) end
    return model:GetAttribute("Owner")
end

function Culling.myTowers()
    local root = workspace:FindFirstChild("Towers")
    if not root then return {} end
    local mine, all = {}, {}
    for _, m in ipairs(root:GetChildren()) do
        table.insert(all, m)
        local own = Culling.towerOwner(m)
        if own ~= nil and own == LP.Name then table.insert(mine, m) end
    end
    if #mine > 0 then return mine end
    return all
end

function Culling.capture(silent)
    local t = Culling.target()
    if not t then
        setStatus("culling: no map detected, pick one by hand", "warn")
        return 0
    end
    local towers = Culling.myTowers()
    if #towers == 0 then
        setStatus("culling: no towers on the map to capture", "warn")
        return 0
    end
    local spots = {}
    for _, m in ipairs(towers) do
        local p = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
        if p then
            local cf = p.CFrame
            table.insert(spots, {
                name = m.Name,
                x = math.floor(cf.X * 100) / 100,
                y = math.floor(cf.Y * 100) / 100,
                z = math.floor(cf.Z * 100) / 100,
                rot = math.floor(math.deg(math.atan2(-cf.LookVector.X, -cf.LookVector.Z)) + 0.5),
            })
        end
    end
    Culling.data[tostring(t.level)] = {
        name = t.name,
        colony = t.colony,
        spots = spots,
        saved = os.time(),
    }
    Culling.saveMacros()
    if not silent then
        setStatus(("culling: saved %d spot(s) for %s"):format(#spots, t.name), "good")
    end
    return #spots
end

--=============================================================
-- placement: RequestTower reserves and charges, SpawnNewTower builds
--=============================================================
local CG_F = RS:FindFirstChild("Functions")

function Culling.placeSpot(spot, eq, timeout)
    local ok, res = pcall(function()
        return CG_F.RequestTower:InvokeServer(eq.name, nil, nil, nil)
    end)
    if not (ok and res == true) then return false end
    local cf = CFrame.new(spot.x, spot.y, spot.z) * CFrame.Angles(0, math.rad(spot.rot or 0), 0)
    local ok2, res2 = pcall(function()
        return CG_F.SpawnNewTower:InvokeServer(eq.uuid, cf, nil)
    end)
    return ok2 and res2 == true
end

function Culling.run(level)
    level = level or (Culling.target() and Culling.target().level)
    if not level then
        setStatus("culling: no macro selected", "warn")
        return false
    end
    local macro = Culling.macroOf(level)
    if not macro then
        setStatus(("culling: %s has no macro yet"):format(CG_BY_LEVEL[level] and CG_BY_LEVEL[level].name or level), "warn")
        return false
    end
    local _, byName = Culling.equipped()
    setStatus(("culling: running %s (%d spots)"):format(macro.name or level, #macro.spots), nil)
    local placed, skipped = 0, 0
    for _, spot in ipairs(macro.spots) do
        local eq = byName[spot.name]
        if not eq then
            for nm, cand in pairs(byName) do
                if nm:find(spot.name, 1, true) or spot.name:find(nm, 1, true) then eq = cand break end
            end
        end
        if not eq then
            skipped = skipped + 1
        else
            local done = false
            for _ = 1, 12 do
                if Culling.placeSpot(spot, eq) then
                    done = true
                    placed = placed + 1
                    break
                end
                if not Culling.inMatch() then break end
                task.wait(1.5)
            end
            if not done then skipped = skipped + 1 end
            task.wait(0.25)
        end
    end
    setStatus(("culling: placed %d, skipped %d"):format(placed, skipped), placed > 0 and "good" or "warn")
    return placed > 0
end

function Culling.upgradePass()
    local up = RS.Functions:FindFirstChild("UpgradeTower")
    if not up then return 0 end
    local n = 0
    for _, m in ipairs(Culling.myTowers()) do
        for _ = 1, 20 do
            local ok, res = pcall(function() return up:InvokeServer(m) end)
            if not (ok and res == true) then break end
            n = n + 1
            task.wait(0.08)
        end
    end
    return n
end

--=============================================================
-- join: elevator touch -> host -> start, then confirm the contract
--=============================================================
local function cgRemotes()
    return RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("CullingGamesTeleporters")
end

function Culling.elevator()
    local root = workspace:FindFirstChild("CullingGamesTeleporters")
    if not root then return nil end
    local best, bestCount = nil, 99
    for _, e in ipairs(root:GetChildren()) do
        local bb = e:FindFirstChild("Billboard")
        local gui = bb and bb:FindFirstChildOfClass("BillboardGui")
        local pc = gui and gui:FindFirstChild("PlayerCount")
        local n = 0
        if pc then
            local a = tostring(pc.Text):match("^(%d+)")
            n = tonumber(a) or 0
        end
        if n < bestCount then best, bestCount = e, n end
    end
    return best
end

function Culling.stepOn(ele)
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local tp = ele and ele:FindFirstChild("Teleports")
    local ent = tp and tp:FindFirstChild("Entrance")
    if not hrp or not ent then return false end
    pcall(function() hrp.CFrame = CFrame.new(ent.Position + Vector3.new(0, 3, 0)) end)
    task.wait(0.3)
    if firetouchinterest then
        pcall(firetouchinterest, hrp, ent, 0)
        task.wait(0.12)
        pcall(firetouchinterest, hrp, ent, 1)
    end
    task.wait(0.5)
    return true
end

function Culling.join(level)
    level = level or Culling.joinLevel
    local rem = cgRemotes()
    local ele = Culling.elevator()
    if not rem or not ele then
        setStatus("culling: elevator not found (need the lobby)", "bad")
        return false
    end
    setStatus("culling: boarding " .. ele.Name, nil)
    Culling.stepOn(ele)
    pcall(function() rem.Host:FireServer(ele) end)
    task.wait(0.6)
    pcall(function() rem.ChooseStage:FireServer(ele, level) end)
    task.wait(0.4)
    pcall(function() rem.Start:FireServer(ele) end)
    setStatus(("culling: started lobby %d"):format(level), "good")
    return true
end

function Culling.confirmContract()
    local folder = RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("CullingGames")
    local cm = folder and folder:FindFirstChild("ChooseModifiers")
    if not cm then return false end
    pcall(function() cm:FireServer(nil, true) end)
    return true
end

function Culling.skipWave()
    local r = RS:FindFirstChild("Remotes")
    local v = r and r:FindFirstChild("VoteSkip")
    if v then pcall(function() v:FireServer() end) end
end

--=============================================================
-- auto driver: detects the map, runs its macro, joins when idle
--=============================================================
function Culling.startAuto()
    if Culling.thread then return end
    Culling.thread = task.spawn(function()
        local contractAt, joinAt = 0, 0
        while Culling.autoRun or Culling.autoJoin do
            if getgenv().STD_Hub ~= Hub then break end
            pcall(function()
                if Culling.inMatch() then
                    local map = workspace:FindFirstChild("Map")
                    local built = map and #map:GetChildren() > 0
                    if Culling.autoJoin and not built and os.clock() - contractAt > 6 then
                        contractAt = os.clock()
                        Culling.confirmContract()
                    end
                    if built then
                        local t = Culling.detected()
                        if t and Culling.autoRun and Culling.lastLevel ~= t.level then
                            if Culling.spotCount(t.level) > 0 then
                                Culling.lastLevel = t.level
                                Culling.run(t.level)
                            end
                        end
                        if Culling.autoUpgrade and #Culling.myTowers() > 0 then
                            Culling.upgradePass()
                        end
                    end
                else
                    Culling.lastLevel = nil
                    if Culling.autoJoin and os.clock() - joinAt > 15 then
                        joinAt = os.clock()
                        Culling.join(Culling.joinLevel)
                    end
                end
            end)
            task.wait(4)
        end
        Culling.thread = nil
    end)
end

function Culling.stopAuto()
    Culling.autoRun = false
    Culling.autoJoin = false
    if Culling.thread then
        pcall(function() task.cancel(Culling.thread) end)
        Culling.thread = nil
    end
end

--=============================================================
-- UI
--=============================================================
local cgLeft  = Tabs.Culling:AddLeftGroupbox("map", "map-pin")
local cgRight = Tabs.Culling:AddRightGroupbox("macro", "bot")

local detectLabel = cgLeft:AddLabel("detected: -", true)
local macroLabel  = cgLeft:AddLabel("macro: -", true)

local function refreshLabels()
    local t = Culling.detected()
    local txt = t and (t.name .. "  (" .. t.colony .. ", lvl " .. t.level .. ")") or (Culling.inMatch() and "culling, unknown map" or "not in culling")
    pcall(function() detectLabel:SetText("detected: " .. txt) end)
    local target = Culling.target()
    if target then
        local n = Culling.spotCount(target.level)
        pcall(function() macroLabel:SetText(("macro %s: %s"):format(target.name, n > 0 and (n .. " spots") or "empty")) end)
    else
        pcall(function() macroLabel:SetText("macro: -") end)
    end
end

Culling.refreshLabels = refreshLabels

local pickNames = { "auto" }
for _, m in ipairs(Culling.maps) do table.insert(pickNames, m.name) end

cgLeft:AddDropdown("CullingPick", {
    Values = pickNames,
    Default = 1,
    Multi = false,
    Text = "map",
    Callback = function(v)
        Culling.pick = v
        refreshLabels()
    end,
})

cgLeft:AddDivider()

cgLeft:AddButton({
    Text = "CAPTURE HERE",
    Func = function() Culling.capture() end,
    Tooltip = "saves the towers standing on this map as its macro",
})

cgLeft:AddButton({
    Text = "RUN MACRO",
    Func = function() Culling.run() end,
})

cgLeft:AddButton({
    Text = "CLEAR MACRO",
    Func = function()
        local t = Culling.target()
        if not t then return end
        Culling.data[tostring(t.level)] = nil
        Culling.saveMacros()
        refreshLabels()
        setStatus("culling: cleared " .. t.name, "warn")
    end,
})

cgRight:AddToggle("CullingAutoRun", {
    Text = "auto run on match",
    Default = false,
    Callback = function(v)
        Culling.autoRun = v
        if v then Culling.startAuto() else if not Culling.autoJoin then Culling.stopAuto() end end
        refreshLabels()
    end,
})

cgRight:AddToggle("CullingAutoUpgrade", {
    Text = "auto upgrade",
    Default = false,
    Callback = function(v)
        Culling.autoUpgrade = v
        if v then Culling.startAuto() end
    end,
})

cgRight:AddSlider("CullingJoinLevel", {
    Text = "join level",
    Default = 1,
    Min = 1,
    Max = 10,
    Rounding = 0,
    Callback = function(v) Culling.joinLevel = v end,
})

cgRight:AddToggle("CullingAutoJoin", {
    Text = "auto join",
    Default = false,
    Callback = function(v)
        Culling.autoJoin = v
        if v then Culling.startAuto() else if not Culling.autoRun then Culling.stopAuto() end end
    end,
})

cgRight:AddDivider()

cgRight:AddButton({
    Text = "JOIN NOW",
    Func = function() Culling.join(Culling.joinLevel) end,
})

cgRight:AddButton({
    Text = "CONFIRM CONTRACT",
    Func = function()
        local ok = Culling.confirmContract()
        setStatus(ok and "culling: contract skipped" or "culling: contract remote missing", ok and "good" or "bad")
    end,
    Tooltip = "the run does not start until the modifier card is confirmed",
})

cgRight:AddButton({
    Text = "SKIP WAVE",
    Func = function() Culling.skipWave() end,
})

Culling.loadMacros()

task.spawn(function()
    while getgenv().STD_Hub == Hub do
        pcall(refreshLabels)
        task.wait(2)
    end
end)


local Candy = {}
Hub.Candy = Candy

Candy.auto = false
Candy.overlay = false
Candy.thread = nil
Candy.hooked = {}
Candy.rolls = 0
Candy.tally = {}
Candy.last = "-"
Candy.lastAt = 0
Candy.perMachine = {}
Candy.machines = {}

local function candyRemote()
    local r = RS:FindFirstChild("Remotes")
    local t = r and r:FindFirstChild("Towers")
    return t and t:FindFirstChild("CandyMachine")
end

function Candy.list()
    local out = {}
    local root = workspace:FindFirstChild("Towers")
    if not root then return out end
    for _, m in ipairs(root:GetChildren()) do
        if m.Name:find("CandyMachine") and m:FindFirstChild("Config") then
            table.insert(out, m)
        end
    end
    return out
end

function Candy.cfgOf(m)
    return m and m:FindFirstChild("Config")
end

function Candy.cd(m)
    local c = Candy.cfgOf(m)
    local v = c and c:FindFirstChild("CandyRollRemCd")
    return v and v.Value or nil
end

function Candy.burstCd(m)
    local c = Candy.cfgOf(m)
    local v = c and c:FindFirstChild("CandyBurstRemCd")
    return v and v.Value or nil
end

function Candy.onRoll(res, m)
    local names = {}
    if type(res) == "table" then
        for _, v in pairs(res) do table.insert(names, tostring(v)) end
    else
        table.insert(names, tostring(res))
    end
    for _, n in ipairs(names) do
        Candy.rolls = Candy.rolls + 1
        Candy.tally[n] = (Candy.tally[n] or 0) + 1
    end
    Candy.last = table.concat(names, " + ")
    Candy.lastAt = os.clock()
    Candy.lastModel = m
    Candy.perMachine[m] = Candy.last
    if Candy.onUpdate then pcall(Candy.onUpdate) end
end

function Candy.hook(m)
    if Candy.hooked[m] then return true end
    local dec = m:FindFirstChild("Decals")
    local rd = dec and dec:FindFirstChild("RollDisplay")
    local ev = rd and rd:FindFirstChild("RollEvent")
    if not ev then return false end
    Candy.hooked[m] = true
    ev.OnClientEvent:Connect(function(res)
        pcall(Candy.onRoll, res, m)
    end)
    return true
end

function Candy.overlayFor(m)
    local gui = m:FindFirstChild("CandyHud")
    if gui then return gui end
    local host = m:FindFirstChild("MainStructure") or m:FindFirstChild("Hitbox") or m:FindFirstChildWhichIsA("BasePart")
    if not host then return nil end
    local bb = Instance.new("BillboardGui")
    bb.Name = "CandyHud"
    bb.Size = UDim2.fromOffset(190, 46)
    bb.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = 250
    bb.Adornee = host
    bb.Parent = m

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    frame.BackgroundTransparency = 0.25
    frame.BorderSizePixel = 0
    frame.Parent = bb
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = frame

    local top = Instance.new("TextLabel")
    top.Name = "Candy"
    top.Size = UDim2.new(1, -8, 0.58, 0)
    top.Position = UDim2.new(0, 4, 0, 2)
    top.BackgroundTransparency = 1
    top.Font = Enum.Font.GothamBold
    top.TextSize = 14
    top.TextColor3 = Color3.fromRGB(255, 214, 120)
    top.TextXAlignment = Enum.TextXAlignment.Center
    top.Text = "candy"
    top.Parent = frame

    local bottom = Instance.new("TextLabel")
    bottom.Name = "Cd"
    bottom.Size = UDim2.new(1, -8, 0.34, 0)
    bottom.Position = UDim2.new(0, 4, 0.6, 0)
    bottom.BackgroundTransparency = 1
    bottom.Font = Enum.Font.Gotham
    bottom.TextSize = 12
    bottom.TextColor3 = Color3.fromRGB(210, 210, 215)
    bottom.TextXAlignment = Enum.TextXAlignment.Center
    bottom.Text = "-"
    bottom.Parent = frame
    return bb
end

function Candy.paintOverlay(m)
    local gui = Candy.overlayFor(m)
    if not gui then return end
    local frame = gui:FindFirstChildOfClass("Frame")
    if not frame then return end
    local top = frame:FindFirstChild("Candy")
    local bottom = frame:FindFirstChild("Cd")
    if top then
        top.Text = tostring(Candy.perMachine[m] or Candy.last or "-"):upper()
    end
    if bottom then
        local rc = Candy.cd(m)
        local bc = Candy.burstCd(m)
        bottom.Text = ("roll %s  ·  burst %s"):format(tostring(rc or "-"), tostring(bc or "-"))
    end
end

function Candy.clearOverlays()
    for _, m in ipairs(Candy.list()) do
        local gui = m:FindFirstChild("CandyHud")
        if gui then gui:Destroy() end
    end
end

function Candy.step()
    local machines = Candy.list()
    Candy.machines = machines
    local F = candyRemote()
    for _, m in ipairs(machines) do
        Candy.hook(m)
        if Candy.auto and F then
            local rc = Candy.cd(m)
            local bc = Candy.burstCd(m)
            if rc and rc <= 0 and F:FindFirstChild("Throw") then
                pcall(function() F.Throw:FireServer(m) end)
            end
            if bc and bc <= 0 and F:FindFirstChild("Burst") then
                pcall(function() F.Burst:FireServer(m) end)
            end
        end
        if Candy.overlay then Candy.paintOverlay(m) end
    end
    if Candy.onUpdate then pcall(Candy.onUpdate) end
end

function Candy.start()
    if Candy.thread then return end
    Candy.thread = task.spawn(function()
        while getgenv().STD_Hub == Hub and (Candy.auto or Candy.overlay) do
            pcall(Candy.step)
            task.wait(0.15)
        end
        Candy.thread = nil
        if not Candy.overlay then Candy.clearOverlays() end
    end)
end

function Candy.stop()
    Candy.auto = false
    Candy.overlay = false
    Candy.thread = nil
    Candy.clearOverlays()
end

function Candy.top(n)
    local arr = {}
    for k, v in pairs(Candy.tally) do table.insert(arr, { k = k, v = v }) end
    table.sort(arr, function(a, b) return a.v > b.v end)
    local out = {}
    for i = 1, math.min(n or 3, #arr) do
        table.insert(out, arr[i].k .. " " .. arr[i].v)
    end
    return #out > 0 and table.concat(out, " · ") or "-"
end

--=============================================================
-- UI
--=============================================================
-- every label in this file lives in one table on purpose: a top-level local
-- costs a VM register for the whole chunk, and the chunk was at 199 of the
-- 200 Luau allows ("out of local registers when trying to allocate httpGet")
local lbl = {}

local candyLeft  = Tabs.Candy:AddLeftGroupbox("machine", "gift")
local candyRight = Tabs.Candy:AddRightGroupbox("rolls", "dices")

lbl.machine = candyLeft:AddLabel("machines: -", true)
lbl.last    = candyLeft:AddLabel("last: -", true)
lbl.cd      = candyLeft:AddLabel("roll -  ·  burst -", true)

lbl.rolls   = candyRight:AddLabel("session: 0", true)
lbl.top     = candyRight:AddLabel("top: -", true)
lbl.odds    = candyRight:AddLabel("odds: common 79.5  ·  rare 18  ·  special 2.5", true)

Candy.onUpdate = function()
    pcall(function() lbl.machine:SetText("machines: " .. #Candy.machines) end)
    pcall(function() lbl.last:SetText("last: " .. tostring(Candy.last)) end)
    local first = Candy.machines[1]
    if first then
        pcall(function()
            lbl.cd:SetText(("roll %s  ·  burst %s"):format(tostring(Candy.cd(first) or "-"), tostring(Candy.burstCd(first) or "-")))
        end)
    end
    pcall(function() lbl.rolls:SetText("session: " .. Candy.rolls) end)
    pcall(function() lbl.top:SetText("top: " .. Candy.top(3)) end)
end

candyLeft:AddToggle("CandyAuto", {
    Text = "auto use",
    Default = false,
    Callback = function(v)
        Candy.auto = v
        if v then
            Candy.start()
            setStatus("candy: auto use on", nil)
        else
            if not Candy.overlay then Candy.thread = nil end
            setStatus("candy: auto use off", "warn")
        end
    end,
})

candyLeft:AddToggle("CandyOverlay", {
    Text = "overlay on machines",
    Default = false,
    Callback = function(v)
        Candy.overlay = v
        if v then Candy.start() else Candy.clearOverlays() end
    end,
})

candyLeft:AddDivider()

candyLeft:AddButton({
    Text = "refresh",
    Func = function()
        Candy.hooked = {}
        Candy.step()
        setStatus(("candy: %d machines"):format(#Candy.machines), nil)
    end,
})

candyRight:AddButton({
    Text = "reset stats",
    Func = function()
        Candy.rolls = 0
        Candy.tally = {}
        Candy.last = "-"
        Candy.onUpdate()
    end,
})

candyRight:AddDivider()

candyRight:AddLabel("range 26.5 · dmg 26.5 · atkspeed 26.5", true)
candyRight:AddLabel("power 6 · sniper 6 · thunder 6", true)
candyRight:AddLabel("golden 1.07 · rainbow 1.07 · secret 0.36", true)
candyRight:AddLabel("next: decided at cast, no preview", true)

local Anniv = {}
Hub.Anniv = Anniv

Anniv.auto = false
Anniv.thread = nil
Anniv.list = {}
Anniv.status = "idle"
Anniv.waitPopulate = 8
Anniv.tierWait = 120
Anniv.tierSince = nil
-- tiers worth joining, best first. ten is always full so the seat is gone, and
-- anything below five is too thin to burn the pinata, so those are never taken
Anniv.tiers = { { 8, 9 }, { 5, 7 } }

local function pinataRoot()
    return workspace:FindFirstChild("PinataTeleporters")
end

function Anniv.scan()
    local root = pinataRoot()
    local out = {}
    if not root then return out end
    for i, p in ipairs(root:GetChildren()) do
        local part = p:FindFirstChild("Part")
        local prompt = part and part:FindFirstChildOfClass("ProximityPrompt")
        local bb = p:FindFirstChild("Billboard")
        local gui = bb and bb:FindFirstChildOfClass("BillboardGui")
        local pc = gui and gui:FindFirstChild("PlayerCount")
        local title = gui and gui:FindFirstChild("Title")
        local cfg = p:FindFirstChild("Config")
        local maxV = cfg and cfg:FindFirstChild("MaxPlayers")
        local txt = pc and tostring(pc.Text) or "0/10"
        table.insert(out, {
            model = p,
            idx = i,
            prompt = prompt,
            part = part,
            n = tonumber(txt:match("^(%d+)")) or 0,
            max = (maxV and maxV.Value) or (tonumber(txt:match("/(%d+)")) or 10),
            title = title and tostring(title.Text) or "",
            open = prompt ~= nil and prompt.Enabled == true,
        })
    end
    return out
end

function Anniv.openList(list)
    local out = {}
    for _, e in ipairs(list or Anniv.list) do
        if e.open then table.insert(out, e) end
    end
    table.sort(out, function(a, b)
        if a.n == b.n then return a.idx < b.idx end
        return a.n > b.n
    end)
    return out
end

function Anniv.summary()
    local list = Anniv.list
    if #list == 0 then list = Anniv.scan() end
    local parts = {}
    for _, e in ipairs(list) do
        table.insert(parts, ("%d/%d"):format(e.n, e.max))
    end
    return #parts > 0 and table.concat(parts, "  ") or "-"
end

-- candidates in the order they should be tried: every tier in turn, fullest of
-- that tier first, so 9 beats 8 and only then 7 beats 6 beats 5. nothing outside
-- the tiers is ever returned, so a quiet hour means waiting rather than walking
-- into a two-player lobby
function Anniv.ranked(list)
    local open = Anniv.openList(list)
    local out = {}
    for _, t in ipairs(Anniv.tiers) do
        for _, e in ipairs(open) do
            if e.n < e.max and e.n >= t[1] and e.n <= t[2] then
                table.insert(out, e)
            end
        end
    end
    return out
end

function Anniv.best(list)
    return Anniv.ranked(list)[1]
end

function Anniv.enter(model)
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local tp = model and model:FindFirstChild("TpIn")
    local part = model and model:FindFirstChild("Part")
    local prompt = part and part:FindFirstChildOfClass("ProximityPrompt")
    if not (hrp and tp and part and prompt) then return false end
    if type(fireproximityprompt) ~= "function" then return false end

    pcall(function() prompt.HoldDuration = 0 end)
    pcall(function() prompt.ClickablePrompt = true end)

    local place0 = game.PlaceId

    local function left()
        if game.PlaceId ~= place0 then return true end
        local c = LP.Character
        local r = c and c:FindFirstChild("HumanoidRootPart")
        if r and (r.Position - tp.Position).Magnitude > 80 then return true end
        return false
    end

    pcall(function() hrp.CFrame = CFrame.new(tp.Position + Vector3.new(0, 3, 0)) end)
    task.wait(0.4)
    pcall(function() fireproximityprompt(prompt) end)

    for i = 1, 30 do
        task.wait(0.2)
        if left() then return true end
        if i == 8 or i == 16 then
            local c = LP.Character
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if r then
                pcall(function() r.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0)) end)
            end
            pcall(function() fireproximityprompt(prompt) end)
        end
    end
    return false
end

function Anniv.step()
    local list = Anniv.scan()
    Anniv.list = list
    if #list == 0 then
        Anniv.status = "no portals"
        Anniv.tierSince = nil
        return
    end

    local open = Anniv.openList(list)
    if #open == 0 then
        Anniv.status = "closed"
        Anniv.tierSince = nil
        return
    end

    -- the clock starts the moment a portal is open and stops the moment one is
    -- closed again: waiting through the closed hour must not count towards it
    if Anniv.tierSince == nil then Anniv.tierSince = os.clock() end

    if open[1].n == 0 then
        Anniv.status = "open, reading counts"
        local t0 = os.clock()
        while os.clock() - t0 < Anniv.waitPopulate do
            task.wait(0.6)
            local l2 = Anniv.scan()
            Anniv.list = l2
            local o2 = Anniv.openList(l2)
            if #o2 > 0 then
                open = o2
                if o2[1].n > 0 then break end
            end
        end
    end

    local q = Anniv.ranked(open)
    if #q == 0 then
        local spent = os.clock() - Anniv.tierSince
        local remain = Anniv.tierWait - spent
        if remain > 0 then
            Anniv.status = ("open, nobody in 9-8 or 5-7 - hop in %ds"):format(math.ceil(remain))
            return
        end
        -- no hop here. hopping takes you off the event server entirely, and a
        -- quiet portal is not a reason to leave the event - it is a reason to
        -- wait for the next tier. the clock is reset so it re-reads in 2 min
        Anniv.status = "nobody filled in 2 min - waiting"
        Anniv.tierSince = os.clock()
        return
    end
    for _, e in ipairs(q) do
        Anniv.status = ("joining %d/%d"):format(e.n, e.max)
        if Anniv.enter(e.model) then
            Anniv.status = "joined"
            Anniv.tierSince = nil
            return
        end
    end
    Anniv.status = "retry"
end

function Anniv.start()
    if Anniv.thread then return end
    Anniv.thread = task.spawn(function()
        while getgenv().STD_Hub == Hub and Anniv.auto do
            pcall(Anniv.step)
            if Anniv.refresh then pcall(Anniv.refresh) end
            if Anniv.status == "joined" then
                task.wait(5)
            else
                task.wait(2)
            end
        end
        Anniv.thread = nil
    end)
end

function Anniv.stop()
    Anniv.auto = false
    Anniv.thread = nil
    Anniv.tierSince = nil
end

--=============================================================
-- KING / FOLLOW  (anniversary event)
--=============================================================
-- every event portal is literally named "Portal1" and they all lead to separate
-- instances of the same map, so the only stable identity a portal has is where
-- it stands. the king writes the one he took into a file in the executor
-- workspace - the same folder every client on this machine shares - and the
-- alts read it back and take that exact portal. nothing else is shared: no
-- teleport, no job id, no guessing which index the other client saw, because
-- GetChildren order is not the same on two clients
local King = {}
Hub.King = King

King.on         = false
King.file       = "STD_Hub_king.txt"
King.idFile     = "STD_Hub_king_id.txt"
King.maxPlayers = 1          -- strangers allowed in the portal besides us
King.status     = "idle"
King.joined     = false
King.joinedAt   = nil        -- when he believed he was through the portal
King.mine       = false      -- this client is the one holding the crown
King.current    = nil        -- the name on disk, as of the last tick
King.currentAt  = nil        -- and the heartbeat that came with it
King.lastId     = nil
King._thread    = nil
King._sync      = nil
King.silent     = false      -- true while the hub itself is moving a toggle
King.inTick     = false      -- re-entrancy guard: a toggle set inside a tick
                             -- fires its own callback
King.round      = 0          -- bumped once per pick, so an alt never walks into
                             -- the portal of a round it already played
King.lock       = nil        -- the portal of this round. once taken, no other
King.miss       = 0
King.settle     = 8          -- after landing back in the lobby, let the alts load
King.settleUntil= nil
King.lastPlace  = nil
King.waitAlts   = true       -- do not walk in until the squad is staged
King.gateWait   = 90         -- how long to wait for a straggler before going anyway
King.gateSince  = nil
King.stageSince = nil        -- when the squad first looked complete
King.stageStable= 3          -- and how long it has to STAY complete. an alt that
                             -- is still unloading the lobby counts as present the
                             -- instant it appears, and would then be teleported
                             -- mid-load by the king's clock
King.skipGate   = false
King.gateAll    = 0

--=============================================================
-- EVENT COUNTER AND THE HOP THAT FOLLOWS IT
--=============================================================
-- One event = one trip out of the lobby and back. The count goes up on the way
-- BACK, not on the way in: a portal that refused to launch, or a teleport that
-- was cancelled, must not count as a run that never happened. The counter is
-- written to a shared file so every client on the machine shows the same number
-- - the alts only read it, the king owns it
King.events     = 0
King.eventFile  = "STD_Hub_events.txt"
King._evRead    = 0

-- After a finished event the squad moves to the EMPTIEST server of the same
-- place: a quiet instance is one where no stranger can take a portal out from
-- under it. The king publishes the job id first and teleports second, so the
-- alts are already moving while his own teleport is in flight
King.autoHop    = true
King.hopFile    = "STD_Hub_hop.txt"
King.hopPending = nil        -- os.time() when the hop was armed
King.hopTries   = 0          -- a server list that failed to come back is worth
                             -- another try; spending the round in a server
                             -- nobody chose is not
King.wasInMatch = false      -- this client has been outside the lobby since it
                             -- last stood in it, so a return is a finished event
-- THE EVENT IS USUALLY A DIFFERENT PLACE, AND SOMETIMES IT IS NOT.
-- Some of this game's rounds are another SERVER of the same place - the portals
-- all lead to separate instances - and a round spent there never changes the
-- place id at all. So the job id is watched as well, and it is watched purely
-- as a counter: it never touches the pick, the gate or the lock, so a wrong
-- guess here cannot break an entry, only the tally
King.lastJob    = nil        -- game.JobId as of the last pass
King.lobbyJob   = nil        -- the instance that counts as home
King.matchJob   = nil        -- the instance this client left home for
King.hopTarget  = nil        -- the job id this client is hopping to itself, so
                             -- its own move is not mistaken for a match
King.hopAt      = nil        -- when that move was issued, so one that never
                             -- landed can be told from one still in flight

-- WHO IS WORTH WAITING FOR.
-- The roster comes from the launcher's own files, so it lists every account the
-- user ticked there - including ones that are not running right now, are stuck
-- on a black screen, or were closed. Waiting the full 90s for one of those costs
-- a portal that may shut in the meantime. `skip` holds the ones that are NOT
-- waited for; it is stored as the exception list rather than the full list on
-- purpose, so an account launched later is waited for by default instead of
-- silently missing from a list nobody remembered to update
King.skip       = {}
King.skipFile   = "STD_Hub_squad_" .. LP.Name .. ".txt"
King._squadSig  = ""         -- what the dropdown currently shows, so the roster
                             -- is only pushed into it when it actually changed

function King.names()
    local G = Hub.Guard
    local out, seen = {}, {}
    if not G then return out end
    local me = tostring(LP.Name):lower()
    local function add(n)
        local k = tostring(n):lower()
        -- a userid instead of a name means that alt's launcher file has no name
        -- in it yet. it can never match Player.Name, so keeping it in the list
        -- would make the gate wait 90 seconds for a player called "123456789"
        -- on every single round
        if k == "" or k == me or seen[k] or k:match("^%d+$") then return end
        seen[k] = true
        out[#out + 1] = tostring(n)
    end
    for _, n in pairs(G.alts or {}) do add(n) end
    -- G.names is keyed by the lowercased name with the real one as the value,
    -- so the value is what belongs in a list the user reads
    for _, n in pairs(G.names or {}) do add(n) end
    table.sort(out)
    return out
end

-- the subset that must be standing in the lobby before the king moves
function King.wanted()
    local out = {}
    for _, n in ipairs(King.names()) do
        if not King.skip[tostring(n):lower()] then out[#out + 1] = n end
    end
    return out
end

-- what the dropdown should show as ticked
function King.checked()
    return King.wanted()
end

function King.loadSkip()
    King.skip = {}
    if not readfile then return end
    local ok, data = pcall(readfile, King.skipFile)
    if not ok or type(data) ~= "string" then return end
    for line in string.gmatch(data, "[^\r\n]+") do
        local n = line:match("^%s*(.-)%s*$")
        if n ~= "" then King.skip[n:lower()] = true end
    end
end

function King.saveSkip()
    if not writefile then return end
    local out = {}
    for n in pairs(King.skip) do out[#out + 1] = n end
    table.sort(out)
    pcall(writefile, King.skipFile, table.concat(out, "\n") .. (#out > 0 and "\n" or ""))
end

-- the dropdown hands back a map of name -> true (Obsidian's multi format).
-- an EMPTY selection means "everybody" rather than "nobody": an empty list that
-- silently meant "go in alone" would strand the whole squad on a stray click,
-- and there is already a GO NOW button for deliberately going alone
function King.setWait(sel)
    -- no roster, no opinion. the guard files are read a moment after the UI is
    -- built, and rebuilding the skip list against an empty roster would erase
    -- the saved one and write the erasure straight back to disk
    local all = King.names()
    if #all == 0 then return end
    local keep = {}
    if type(sel) == "table" then
        for k, v in pairs(sel) do
            if type(v) == "boolean" then
                if v then keep[tostring(k):lower()] = true end
            elseif type(v) == "string" then
                keep[v:lower()] = true
            end
        end
    end
    if next(keep) == nil then
        King.skip = {}
    else
        local skip = {}
        for _, n in ipairs(all) do
            if not keep[n:lower()] then skip[n:lower()] = true end
        end
        King.skip = skip
    end
    King.saveSkip()
end

function King.sig(part)
    if not part then return nil end
    local p = part.Position
    return ("%.1f,%.1f,%.1f"):format(p.X, p.Y, p.Z)
end

-- nearest portal to a recorded spot, in the XZ plane only. an exact string
-- match would break the moment a portal bobs or spins, and two portals are
-- never four studs apart
function King.find(sig)
    if not sig then return nil end
    local x, y, z = sig:match("^([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)$")
    x, z = tonumber(x), tonumber(z)
    if not x or not z then return nil end
    local best, bestD
    for _, e in ipairs(Anniv.scan()) do
        local p = e.part and e.part.Position
        if p then
            local d = (Vector2.new(p.X, p.Z) - Vector2.new(x, z)).Magnitude
            if d < 4 and (not bestD or d < bestD) then best, bestD = e, d end
        end
    end
    return best
end

-- every account of mine standing in this lobby right now. the roster is the one
-- the server guard already keeps - the folder of userids every client writes
-- plus the hand-written _names.txt - so this is exactly the accounts that were
-- ticked in the launcher, and nothing has to be typed in a second time
function King.here()
    local G = Hub.Guard
    local out = {}
    if not G then return out end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and (G.alts[p.UserId] or G.names[tostring(p.Name):lower()]) then
            -- A PLAYER OBJECT EXISTS BEFORE THE CHARACTER DOES.
            -- Counting them the moment they appear in the player list is how a
            -- still-loading alt got counted as staged - the king opened the
            -- clock, the portal launched thirty seconds later, and the alt that
            -- had never finished loading was teleported mid-load. That is the
            -- "Lost connection due to an unknown error (256)" dialog: the client
            -- was torn down while its place was still being built.
            -- A character with a root part means the server has actually
            -- spawned them here, which is the first moment they can be counted
            local c = p.Character
            if c and c:FindFirstChild("HumanoidRootPart") then
                out[#out + 1] = p.Name
            end
        end
    end
    table.sort(out)
    return out
end

-- HOW MANY OF MY ACCOUNTS EXIST, from the launcher's own roster - the folder of
-- userid files the guard already reads. not "the most I have ever seen here",
-- which drifted up and never came back down when an alt was simply not running.
-- one source of truth: whatever King.names says, since the tick list is a subset
-- of it and two counts that disagree is exactly how a gate starts lying
function King.roster()
    return #King.names()
end

-- THE GATE, INVERTED.
-- The portal's 30s clock starts with the FIRST player through it, so whoever
-- walks in first is spending the squad's window. The old gate spent it the
-- wrong way round: it held the king until every alt had ALREADY left the lobby,
-- so the first alt opened the clock, the king went in last, and any alt still
-- loading when it ran out got teleported mid-load - which is the shape of a
-- 256. Now the king waits until every account of mine is standing here and has
-- been standing here for stageStable seconds, then walks in and opens the
-- window himself. The alts are already loaded, already next to the portal, and
-- follow in about a second.
function King.gate()
    local here = King.here()
    -- the wanted list, not the whole roster: an account that is not running, or
    -- that the user unticked, must not be able to hold the round for 90 seconds
    local want = King.wanted()
    King.gateAll = #want
    if #want == 0 then return true, "", #here, 0 end
    -- WHO IS MISSING, not who is present. the second argument is read straight
    -- into "waiting for ..." and the old version put the names of the accounts
    -- that were already standing there into it, which is the one thing the user
    -- cannot act on: the useful line names the alt that never launched
    local has = {}
    for _, n in ipairs(here) do has[tostring(n):lower()] = true end
    local missing, have = {}, 0
    for _, n in ipairs(want) do
        if has[tostring(n):lower()] then have = have + 1
        else missing[#missing + 1] = n end
    end
    if #missing == 0 then return true, "", have, #want end
    return false, table.concat(missing, ", "), have, #want
end

-- A RECORD FROM THE LAST ROUND MUST NOT SURVIVE INTO THIS ONE.
-- While the king is staging, the file must not exist at all - but the previous
-- round's record is still sitting on disk, and it says "through the portal" with
-- a timestamp seconds old. An alt that has just loaded has no round of its own
-- to compare against, so the round check in Follow cannot save it: it would read
-- that old pick as a fresh order and walk in alone, opening the 30s clock before
-- the king had even finished staging. Deleting is the only unambiguous "no
-- order right now", and the record is republished the instant he commits.
function King.clear()
    if delfile then pcall(delfile, King.file) end
end

--=============================================================
-- EVENT COUNTER
--=============================================================
function King.loadEvents()
    if not readfile then return King.events end
    local ok, data = pcall(readfile, King.eventFile)
    if not ok or type(data) ~= "string" then return King.events end
    local n = tonumber(data:match("^(%d+)"))
    if n then King.events = n end
    return King.events
end

function King.saveEvents()
    if not writefile then return end
    pcall(writefile, King.eventFile, ("%d|%d|%s"):format(King.events or 0, os.time(), LP.Name))
end

-- one finished event. called from the place watcher in King.step, on the way
-- BACK into the lobby, which is the only moment that proves a match was played
-- through rather than a portal that refused to open
function King.countEvent()
    King.events = (King.events or 0) + 1
    King.saveEvents()
    return King.events
end

function King.resetEvents()
    King.events = 0
    King.saveEvents()
    return 0
end

-- ONE PLACE WHERE A ROUND IS DECLARED OVER, whatever told us so. Both watchers
-- end up here, so the reset, the count and the hop can never drift apart
function King.onEventDone()
    King.wasInMatch, King.matchJob = false, nil
    King.settleUntil = os.time() + King.settle
    King.lock, King.joined, King.gateSince, King.miss = nil, false, nil, 0
    King.stageSince, King.joinedAt = nil, nil
    King.clear()
    King.countEvent()
    if King.autoHop then
        King.hopPending = os.time()
        King.hopTries = 0
    end
    return King.events
end

-- the job watcher. only ever counts and arms - see the note on King.lastJob
function King.watchJob()
    local jid = game.JobId
    if King.lastJob == jid then return end
    local prev = King.lastJob
    King.lastJob = jid
    -- home is not known until this client has stood in the lobby. loading
    -- straight into a round must not make the round the home instance
    if King.lobbyJob == nil then
        if game.PlaceId == Modes.LOBBY then King.lobbyJob = jid end
        return
    end
    if game.PlaceId ~= Modes.LOBBY then return end
    if jid == King.hopTarget then
        -- our own hop landing. the new instance is the new home, not a round -
        -- and NOW is the moment the squad can be told where the king actually
        -- is, instead of where he was aiming
        King.hopTarget, King.hopAt, King.lobbyJob, King.matchJob = nil, nil, jid, nil
        King.hopPublish({ id = jid, place = game.PlaceId })
        return
    end
    -- a hop that never landed leaves the target behind; it must not sit there
    -- waiting to be mistaken for the next round
    King.hopTarget = nil
    if jid == King.lobbyJob then
        if King.matchJob then King.onEventDone() end
    elseif prev == King.lobbyJob then
        -- left the home instance for another server of the same place
        King.matchJob = jid
    end
end

--=============================================================
-- THE HOP RECORD
--=============================================================
-- A client can only ever teleport ITSELF, so the alts cannot be moved by the
-- king's call - they have to be told where he went. This file is that order:
-- job id, place id, time, who sent it. Published BEFORE his own teleport goes
-- out, so the alts are already in flight while his is still being processed,
-- and they land within a second or two of him instead of after a poll cycle
-- THE RECORD IS THE SERVER HE IS IN, NOT THE ONE HE MEANT TO GO TO.
-- The old version published the id from the server list before teleporting -
-- a prediction. If the teleport was refused, or the client landed somewhere
-- else, the squad was sent to a server the king was never in. Writing the id
-- AFTER arrival makes it a fact: whatever instance he is actually standing in
-- is the one the rest are told to join
function King.hopPublish(server)
    if not writefile or not server or not server.id then return false end
    pcall(writefile, King.hopFile, ("%s|%d|%d|%s"):format(
        tostring(server.id), server.place or game.PlaceId, os.time(), LP.Name))
    return true
end

function King.hopRead()
    if not readfile then return nil end
    local ok, data = pcall(readfile, King.hopFile)
    if not ok or type(data) ~= "string" then return nil end
    local job, place, at = data:match("^([%w%-_]+)|(%d+)|(%d+)")
    if not job or job == "" then return nil end
    return { job = job, place = tonumber(place), at = tonumber(at) }
end

function King.hopClear()
    if delfile then pcall(delfile, King.hopFile) end
end

function King.record()
    if not readfile then return nil end
    local ok, data = pcall(readfile, King.file)
    if not ok or type(data) ~= "string" then return nil end
    -- six fields now. the shorter patterns are still accepted so a record
    -- written by an older build is read rather than ignored mid-upgrade
    local name, sig, n, at, round, inn =
        data:match("^([%w_]+)|([%d%.,%-]+)|(%d+)|(%d+)|(%d+)|(%d+)$")
    if not name then
        name, sig, n, at, round = data:match("^([%w_]+)|([%d%.,%-]+)|(%d+)|(%d+)|(%d+)$")
        inn = nil
    end
    if not name then
        name, sig, n, at = data:match("^([%w_]+)|([%d%.,%-]+)|(%d+)|(%d+)$")
        round, inn = nil, nil
    end
    if not name then return nil end
    return { name = name, sig = sig, n = tonumber(n), at = tonumber(at),
             round = tonumber(round), inn = tonumber(inn) }
end

-- the record may already carry a round from before this client loaded, so the
-- counter is read back rather than restarted - a reload must not reuse a number
-- an alt has already seen
function King.nextRound()
    -- A WALL-CLOCK STAMP, NOT A COUNTER.
    -- A counter restarts at 1 whenever the king's client reloads the hub (the
    -- in-memory value is gone and the record it would have counted from is
    -- cleared on stop), while an alt still holds the old number in memory and
    -- would then reject every new pick as "a round I already played". Seconds
    -- always move forward - across reloads, across clients, across sessions
    local cur = King.record()
    local r = os.time()
    if cur and cur.round and cur.round >= r then r = cur.round + 1 end
    return r
end

-- THE PORTAL HAS TO HOLD THE WHOLE SQUAD, NOT JUST ONE MORE PLAYER.
-- This used to require a single free seat (n < max) and pick the emptiest. With
-- a squad of six and a portal that holds four, five of them were sent at a
-- server that had no room for them - and a client that cannot get into the
-- reserved server is dropped with exactly the dialog in the screenshot,
-- "Lost connection due to an unknown error (256)". So the requirement is
-- roster + 1 free seats, and among the portals that clear it the one with the
-- most room wins, emptiest first on a tie.
function King.seatsNeeded()
    -- THE UNION OF WHO MUST BE WAITED FOR AND WHO IS ALREADY HERE.
    -- A wanted alt that has not landed yet still needs a seat, and an alt that
    -- is standing here unticked will follow anyway the moment the king is
    -- through - its own client does not know about the tick list. Counting only
    -- the ticked ones would sell seats the squad is about to use, and a squad
    -- that does not fit is the 256 in the screenshot
    local set, n = {}, 0
    local function add(name)
        local k = tostring(name):lower()
        if k ~= "" and not set[k] then set[k] = true n = n + 1 end
    end
    for _, x in ipairs(King.wanted()) do add(x) end
    for _, x in ipairs(King.here()) do add(x) end
    return n + 1
end

function King.pick()
    local need = King.seatsNeeded()
    local best, bestFree
    for _, e in ipairs(Anniv.scan()) do
        local free = (e.max or 0) - (e.n or 0)
        if e.open and free >= need and (e.n or 0) <= King.maxPlayers then
            if not best or free > bestFree or (free == bestFree and e.n < best.n) then
                best, bestFree = e, free
            end
        end
    end
    return best, bestFree, need
end

-- THE RECORD NOW CARRIES TWO THINGS, NOT ONE: WHICH PORTAL, AND WHETHER THE
-- KING IS ALREADY THROUGH IT.
-- "King first" has to be a fact the alts can read, not an assumption about who
-- polls faster. The pick is written before he walks in, so an alt that happens
-- to be on a 0.25s tick would otherwise reach the portal first and open the 30s
-- clock itself. The flag is written the moment Anniv.enter reports he is
-- through, and the alts do not move until they see it - with a grace fallback
-- in Follow for the case where his client dies between the two writes.
function King.write(e, joined)
    if not writefile then return false end
    local sig = (King.lock and King.lock.sig) or King.sig(e and e.part)
    if not sig then return false end
    King.lock = King.lock or { sig = sig }
    King.lock.touch = os.time()
    King.lock.published = true
    -- `in` is a reserved word in Luau and King.lock.in does not parse, hence
    -- `thru` for "the king is through the portal"
    if joined ~= nil then King.lock.thru = joined and 1 or 0 end
    pcall(writefile, King.file, ("%s|%s|%d|%d|%d|%d"):format(
        LP.Name, sig, (e and e.n) or 0, os.time(), King.round or 1, King.lock.thru or 0))
    return true
end

-- while the king is holding, the record still has to stay fresh: an alt that
-- loads late reads the same file and must still find it usable
-- only refreshes a pick that has already been PUBLISHED. while the king is
-- still waiting for the squad the record must not exist at all: an alt that saw
-- it would hold for its grace period and then walk in by itself, which is the
-- alts-first order this whole change is here to remove
function King.touch(e)
    if not King.lock or not King.lock.published then return end
    if os.time() - (King.lock.touch or 0) < 10 then return end
    King.write(e)
end

function King.step()
    -- the auto-hop toggle is shared by every client, and a restored value must
    -- be honoured the same way a click is - so the truth is read from the
    -- control itself instead of being mirrored into a flag at build time
    local hopT = Toggles.KingAutoHop
    if hopT then King.autoHop = hopT.Value == true end

    -- a round that is another server of the same place never changes PlaceId,
    -- so the job id is checked before anything else
    King.watchJob()

    -- a place change is a new round. coming back to the lobby re-arms the
    -- settle timer and drops the pick, so the next portal is chosen fresh
    if King.lastPlace ~= game.PlaceId then
        local fromLobby = King.lastPlace == Modes.LOBBY
        King.lastPlace = game.PlaceId
        if game.PlaceId == Modes.LOBBY then
            King.settleUntil = os.time() + King.settle
            King.lock, King.joined, King.gateSince, King.miss = nil, false, nil, 0
            King.stageSince, King.joinedAt = nil, nil
            -- the round that just ended is over. until the next pick is
            -- published there is no order, and the alts must not find one
            King.clear()
            -- BACK FROM A MATCH IS THE END OF AN EVENT. counted here and not on
            -- the way in, because a portal that refused to launch, or a
            -- teleport that was cancelled, never became a run
            if King.wasInMatch then King.onEventDone() end
        elseif fromLobby then
            King.wasInMatch = true
        end
    end

    if game.PlaceId ~= Modes.LOBBY or King.matchJob then
        King.joined, King.joinedAt = false, nil
        King.wasInMatch = true
        King.status = "in match"
        return
    end
    -- "entered" is only really proven by the place changing. Anniv.enter
    -- reports success the moment the character leaves the portal, but the
    -- teleport can still be cancelled after that (server full, replication
    -- refused, pulled back). without this the king would sit in the lobby
    -- believing he is through, with the alts already released, and never pick
    -- again. a match takes seconds to start, so half a minute is generous
    if King.joined then
        if os.time() - (King.joinedAt or 0) < 30 then return end
        King.joined, King.lock, King.joinedAt = false, nil, nil
        King.status = "teleport never landed - picking again"
    end

    --=========================================================
    -- THE HOP AFTER AN EVENT
    --=========================================================
    -- IT DOES NOT WAIT FOR THE SQUAD, AND THAT IS THE POINT.
    -- The game does not put everybody back in the same server after a match -
    -- an alt routinely comes back somewhere else entirely. Waiting for them in
    -- THIS lobby would burn a minute staring at a gate that can never fill, and
    -- then leave them behind anyway. So the king moves as soon as he himself is
    -- solidly here, and the record he publishes is what tells the rest where
    -- the squad went. They follow from wherever they landed.
    -- The only thing waited for is his OWN character: teleporting out of a
    -- place that is still loading is the 256, and it has nothing to do with
    -- anybody else
    -- A HOP THAT WAS ISSUED AND NEVER LANDED. The record is only written on
    -- arrival now, so a refused teleport leaves this client with its old target
    -- and nothing published - the squad is simply still where it was, which is
    -- recoverable. Twenty seconds is longer than any real teleport takes
    if King.hopTarget and King.hopAt and (os.time() - King.hopAt) > 20 then
        King.hopTarget, King.hopAt = nil, nil
        King.hopPending = os.time()
        King.status = ("event %d done - hop never landed, trying again"):format(King.events or 0)
    end

    if King.hopPending and not King.autoHop then
        -- switched off while the squad was still landing. a hop that is
        -- already armed must not go through anyway
        King.hopPending = nil
        King.status = ("event %d done - staying here"):format(King.events or 0)
    end

    if King.hopPending then
        local char = LP.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local waited = os.time() - (King.hopPending or os.time())
        -- two seconds for the lobby to settle under his feet, then however long
        -- his own character takes to spawn - capped, because a character that
        -- never spawns must not pin the squad to a dead lobby
        if waited < 2 or (not root and waited < 12) then
            King.status = ("event %d done - hopping in %ds"):format(
                King.events or 0, math.max(0, 2 - waited))
            return
        end
        King.hopPending = nil
        local G = Hub.Guard
        if not (G and G.hopEmptiest) then
            King.status = ("event %d done - no server guard"):format(King.events or 0)
            return
        end
        King.status = ("event %d done - hopping to the emptiest server"):format(King.events or 0)
        local moved = G.hopEmptiest(("event %d"):format(King.events or 0))
        if moved then King.hopAt = os.time() end
        if moved == false then
            -- the server list did not come back, or the guard is still cooling
            -- down from the last move. re-arm instead of quietly staying in a
            -- server the king never chose - and give up after a few tries so a
            -- dead endpoint cannot spin here for the rest of the session
            King.hopTries = (King.hopTries or 0) + 1
            if King.hopTries <= 5 then
                King.hopPending = os.time()
                King.status = ("event %d done - hop failed, retrying (%d/5)")
                    :format(King.events or 0, King.hopTries)
            else
                King.hopTries = 0
                King.status = ("event %d done - no server found, staying"):format(King.events or 0)
            end
        else
            King.hopTries = 0
        end
        return
    end

    -- the pick is made once per round and never re-made. from here on the only
    -- thing that can move it is the portal itself disappearing - not a fuller
    -- count on some other one, and not an alt that turned up late
    local e = King.find(King.lock and King.lock.sig)
    if King.lock and (not e or not e.open) then
        -- a shut prompt cannot be fired, and Anniv.enter would spend six
        -- seconds discovering that on every pass, so count it out here
        King.miss = (King.miss or 0) + 1
        if King.miss < 3 then
            King.status = e and "holding the pick - portal is shut" or "holding the pick - portal is not here"
            return
        end
        King.status = "pick is gone - choosing again"
        King.lock, King.miss, e = nil, 0, nil
    end

    if not e then
        if King.settleUntil and os.time() < King.settleUntil then
            King.status = ("settling %ds - letting the alts land"):format(King.settleUntil - os.time())
            return
        end
        local need
        e, _, need = King.pick()
        if not e then
            King.status = ("waiting: no portal with %d free seat(s)"):format(need or 1)
            return
        end
        King.round = King.nextRound()
        King.lock = { sig = King.sig(e.part), n = e.n, max = e.max }
        King.clear()
        -- re-read the roster before counting heads: an alt launched after this
        -- client started has its own file on disk but not in memory yet
        if Hub.Guard and Hub.Guard.load then pcall(Hub.Guard.load) end
        King.miss, King.gateSince, King.stageSince = 0, nil, nil
        King.gateAll = #King.here()
        King.status = ("picked %d/%d - staging"):format(e.n, e.max)
    end

    if King.waitAlts and not King.skipGate then
        local ok, who, have, all = King.gate()
        if not ok then
            -- not everybody is here yet. reset the stability clock: a squad that
            -- was complete and then lost somebody is not staged any more
            King.stageSince = nil
            if King.gateSince == nil then King.gateSince = os.time() end
            local waited = os.time() - King.gateSince
            if waited < King.gateWait then
                King.status = ("staged %d/%d - waiting for %s (%ds)"):format(
                    have, all, (who ~= "" and who) or "the rest",
                    math.max(0, King.gateWait - waited))
                King.touch(e)
                return
            end
            -- a straggler that never turns up must not hold the round forever.
            -- the clock is the squad's, and going without one is better than
            -- going with none
            King.status = ("squad incomplete after %ds - going without: %s"):format(
                King.gateWait, who)
            King.gateSince, King.stageSince = nil, nil
        elseif all > 0 then
            -- complete. hold it for stageStable so nobody is counted while still
            -- walking out of a load: an alt is "present" the frame it spawns,
            -- and the king's clock would teleport it before its own GUI is up
            if King.stageSince == nil then
                King.stageSince = os.time()
                King.status = ("squad staged %d/%d - holding %ds"):format(have, all, King.stageStable)
                King.touch(e)
                return
            end
            local held = os.time() - King.stageSince
            if held < King.stageStable then
                King.status = ("squad staged %d/%d - holding %ds"):format(
                    have, all, King.stageStable - held)
                King.touch(e)
                return
            end
            King.gateSince, King.stageSince = nil, nil
        else
            King.gateSince, King.stageSince = nil, nil
        end
    end
    King.skipGate = false

    -- THE RECORD APPEARS HERE AND NOWHERE EARLIER. this is the instant the king
    -- commits, and it is the first moment an alt has any business moving
    King.write(e)
    King.status = ("taking %d/%d"):format(e.n, e.max)
    if Anniv.enter(e.model) then
        King.joined = true
        King.joinedAt = os.time()
        King.tries = 0
        -- the alts are waiting on exactly this line. written before anything
        -- else so the window they have left is as wide as possible
        King.write(e, true)
        King.status = ("joined %d/%d - alts released"):format(e.n, e.max)
    else
        -- the king goes first, so the seat should still be his - but a stranger
        -- can take it in the same second. five refusals in a row and the portal
        -- is written off instead of standing there retrying while the round
        -- runs without him
        King.tries = (King.tries or 0) + 1
        if King.tries >= 5 then
            King.status = "portal is full - the alts are in without me"
            King.lock, King.tries = nil, 0
        else
            King.status = "portal did not take - holding"
            King.touch(e)
        end
    end
end

-- who is the king is a property of the MACHINE, not of one client. the name
-- goes into the same shared folder the portal record uses, so turning this on
-- once on the main account is enough: every other client reads the name, sees
-- it is not theirs, and becomes a follower by itself. that is also why the
-- toggle must never be trusted on load - every client loads the same settings
-- file, so a restored "on" would make all of them claim the crown at once
-- WHO IS THE KING IS A FACT ON DISK, AND IT HAS TO STAY ONE.
-- The file used to hold a bare name, and three separate things could make that
-- name change on its own:
--   1. a client that loaded with the toggle reading false (the settings file is
--      restored a moment later) released the crown for everybody, and then
--      whichever alt had "king mode" saved as on claimed it - the random king;
--   2. two clients reaching the claim in the same second both wrote, and the
--      last writer won;
--   3. writefile truncates before it writes, so a client reading mid-write saw
--      an empty file and read that as "no king", then claimed over a live one.
-- Now the file carries a heartbeat, a claim is verified instead of assumed, and
-- only an explicit click gives the crown up.
King.kingStale  = 30         -- seconds without a heartbeat before a crown counts
                             -- as abandoned - the holder crashed or was closed
King.lastBeat   = 0

-- name, heartbeat, state. "missing" means there is genuinely no file and a
-- claim is allowed; "empty" means there IS one but it could not be read, which
-- is a write in flight and must never be mistaken for an empty crown
function King.idEx()
    if not readfile then return nil, nil, "missing" end
    local exists = true
    if isfile then
        local okf, f = pcall(isfile, King.idFile)
        if okf then exists = f == true end
    end
    if not exists then return nil, nil, "missing" end
    for _ = 1, 3 do
        local ok, data = pcall(readfile, King.idFile)
        if ok and type(data) == "string" then
            local name, at = data:match("^([%w_]+)|(%d+)")
            if not name then name = data:match("^([%w_]+)") end
            if name and name ~= "" then
                return name, at and tonumber(at) or nil, "ok"
            end
        end
        task.wait(0.05)
    end
    return nil, nil, "empty"
end

function King.id()
    local name = King.idEx()
    return name
end

-- write, then READ IT BACK. the file only remembers the last writer, so losing
-- the election has to be discovered here and now - not two seconds later, when
-- this client has already started walking the squad into a portal
function King.claim()
    if not writefile then return false end
    King.lastBeat = os.time()
    pcall(writefile, King.idFile, ("%s|%d"):format(LP.Name, King.lastBeat))
    task.wait(0.12)
    local who = King.idEx()
    return who == LP.Name
end

-- the crown is kept alive by the holder, so an alt can tell a king that is
-- standing here from one whose client was closed an hour ago
function King.beat()
    if not writefile then return end
    local now = os.time()
    if now - (King.lastBeat or 0) < 5 then return end
    King.lastBeat = now
    pcall(writefile, King.idFile, ("%s|%d"):format(LP.Name, now))
end

function King.release()
    if delfile then pcall(delfile, King.idFile) end
    King.lastBeat = 0
    return true
end

function King.setToggle(name, want)
    local t = Toggles[name]
    if not t then return end
    local ok, cur = pcall(function() return t.Value end)
    if not ok or cur == want then return end
    King.silent = true
    pcall(function() t:SetValue(want) end)
    King.silent = false
end

function King.start()
    if King._thread then return end
    -- re-read the tick list on every start: it is per account and the crown can
    -- move between accounts, so whatever was loaded at UI build time may belong
    -- to a different one
    King.loadSkip()
    -- the counter outlives the client: a reload must not reset the tally
    King.loadEvents()
    King._thread = task.spawn(function()
        while getgenv().STD_Hub == Hub and King.on do
            pcall(King.step)
            task.wait(King.joined and 4 or 2)
        end
        King._thread = nil
    end)
end

function King.stop()
    King.on = false
    King._thread = nil
    -- no king, no order. leaving the record behind would keep every alt
    -- following a portal nobody is going to walk through.
    -- ONLY FROM THE KING'S OWN CLIENT: the record is one shared file, and the
    -- cleanup that runs when any client reloads the hub calls this too - an alt
    -- that merely reloaded must not wipe the order out from under the others
    if King.mine then
        King.clear()
        -- and the hop order: a squad that has been told to move to a server by
        -- a king who is no longer king would keep chasing it
        King.hopClear()
    end
    King.mine = false
end

--=============================================================
local Follow = {}
Hub.Follow = Follow

Follow.on      = false
Follow.manualOff = false    -- the user turned it off by hand, do not re-arm
Follow.king    = nil        -- the account to follow
Follow.file    = "STD_Hub_king.txt"
Follow.fresh   = 60         -- how long a record stays usable, seconds. it was
                            -- 180, which is longer than a round: an alt that
                            -- loaded late could act on a pick the king had
                            -- already played and enter a portal about to launch
                            -- under it. the king touches the record every 10s
                            -- while he holds, so 60s only expires once he is
                            -- genuinely gone
Follow.kingGrace = 6        -- if the record says the king is still walking in,
                            -- wait this long for his "through" flag and then go
                            -- anyway: his clock is already running and standing
                            -- here politely is how the squad misses the round
Follow.pace    = 0.6        -- how long to sleep between polls. the window is
                            -- 30s from the king's entry, so this is the number
                            -- that decides how much of it the alts waste
Follow.status  = "idle"
Follow.joined  = false
Follow.sig     = nil        -- the portal this client took
Follow.round   = nil        -- the last pick it acted on
Follow._thread = nil
Follow.hopFresh = 180       -- a hop order stays usable this long. after a match
                            -- the game does not put everybody back together, and
                            -- an alt that is slow to load may only reach a lobby
                            -- minutes later - it still has to find the order
                            -- waiting. the king republishes on every move, and
                            -- Follow.hopJob stops the same order being obeyed
                            -- twice, so a long window costs nothing
Follow.hopJob  = nil        -- the job id of the last hop this client obeyed
Follow.hopAt   = nil        -- when it obeyed it, so a teleport that was refused
                            -- can be told apart from one that is in progress
Follow.hopDelay = 0         -- per-account stagger, so six clients do not all
                            -- start loading a new place in the same frame

function Follow.read()
    return King.record()
end

-- nearest portal to the recorded spot, in the XZ plane only. an exact string
-- match would break the moment a portal bobs or spins, and two portals are never
-- four studs apart
function Follow.find(sig)
    return King.find(sig)
end

--=============================================================
-- FOLLOWING A HOP
--=============================================================
-- After a finished event the king leaves for the emptiest server, and this is
-- how the alts go with him: he cannot teleport them, so he writes the job id
-- down and they take it from there.
-- The order outranks the portal - walking into a portal in a lobby the squad is
-- abandoning means loading a match nobody else is in. Three things keep it from
-- misfiring: a job id already obeyed is never obeyed twice, the job this client
-- is ALREADY IN is not a move at all, and an order older than hopFresh is a
-- leftover rather than an instruction
function Follow.hopCheck()
    if game.PlaceId ~= Modes.LOBBY then return false end
    local rec = King.hopRead()
    if not rec or not rec.job then return false end
    if rec.job == Follow.hopJob then
        -- obeyed but never arrived. TeleportToPlaceInstance only queues the
        -- move - it returns success before the server has agreed - so a refusal
        -- (the instance filled up between the list and the call) looks exactly
        -- like a teleport in progress. If the client is still not there twenty
        -- seconds later it was refused, so drop the record and let the code
        -- below send it again: leaving the alt behind in the lobby the squad
        -- just abandoned is the one outcome that has no recovery
        local stuck = game.JobId ~= rec.job and Follow.hopAt
            and (os.time() - Follow.hopAt) > 20
        if not stuck then return false end
        Follow.hopJob = nil
    end
    if game.JobId == rec.job then
        -- already standing in it: the order is fulfilled, remember it so the
        -- same record is not acted on again after the next poll
        Follow.hopJob = rec.job
        return false
    end
    if os.time() - (rec.at or 0) > Follow.hopFresh then return false end
    if rec.place and rec.place ~= game.PlaceId then return false end
    Follow.hopJob = rec.job
    Follow.hopAt = os.time()
    Follow.status = ("hopping to %s"):format(tostring(rec.job):sub(1, 8))
    local job, place, delay = rec.job, rec.place or game.PlaceId, Follow.hopDelay
    task.spawn(function()
        -- SIX CLIENTS MUST NOT LAND ON ONE MACHINE IN ONE FRAME.
        -- The offset comes from the account name, so it is the same on every
        -- run and needs no coordination between the clients - the same trick
        -- the loader uses to keep the autoexec from stampeding
        if delay and delay > 0 then task.wait(delay) end
        -- obj:method() through a plain reference: __namecall is skipped, which
        -- keeps this out of the hub's own no-afk teleport filter
        local ts = game:GetService("TeleportService")
        local call = ts.TeleportToPlaceInstance
        local ok, err = pcall(function() call(ts, place, job, LP) end)
        if not ok then Follow.status = "hop failed: " .. tostring(err) end
    end)
    return true
end

function Follow.step()
    -- A HOP ORDER OUTRANKS THE PORTAL. If the king has moved the squad to
    -- another server, this lobby is the one being abandoned and any portal in
    -- it leads to a match the rest of the squad will not be in
    if Follow.hopCheck() then return end
    if game.PlaceId ~= Modes.LOBBY then
        Follow.joined = false
        Follow.status = "in match"
        return
    end
    if Follow.joined then return end
    local rec = Follow.read()
    if not rec then
        Follow.status = "no king record yet"
        return
    end
    if os.time() - rec.at > Follow.fresh then
        Follow.status = "king record is stale"
        return
    end
    if Follow.king and rec.name ~= Follow.king then
        Follow.status = "record is for " .. rec.name
        return
    end
    -- a record from a round this client already played is not a new order: the
    -- king is still holding the same portal, and walking in again would put the
    -- alt in a match the king already left
    if rec.round and Follow.round and rec.round <= Follow.round then
        Follow.status = "waiting for the king's next pick"
        return
    end
    local e = Follow.find(rec.sig)
    if not e then
        Follow.status = "king's portal is not in this lobby"
        return
    end
    -- STRICT ORDER. the record is written before the king walks in, so an alt
    -- that polls faster than he does would reach the portal first and open the
    -- 30s clock itself - which is the exact thing being fixed here. the king
    -- sets the flag the moment Anniv.enter reports he is through, and until
    -- then the alts hold. the grace fallback covers the one case that would
    -- otherwise waste the round: his client dying between the write and the
    -- enter, leaving the flag at 0 forever
    if rec.inn ~= nil and rec.inn ~= 1 then
        local waited = os.time() - (rec.at or 0)
        if waited < Follow.kingGrace then
            Follow.pace = 0.25
            Follow.status = ("king is walking in - holding %ds"):format(Follow.kingGrace - waited)
            return
        end
        Follow.status = "king's flag never set - going anyway"
    end
    Follow.status = ("following %s into %d/%d"):format(rec.name, e.n, e.max)
    Follow.pace = 0.25
    if Anniv.enter(e.model) then
        Follow.joined = true
        Follow.sig = rec.sig
        Follow.round = rec.round or Follow.round
        Follow.status = "joined " .. rec.name
    else
        Follow.status = "portal did not take"
    end
end

function Follow.start()
    if Follow._thread then return end
    -- 0.25s .. 1.75s, fixed per account. enough to break a six-client
    -- stampede into a queue without losing a visible amount of the round
    local h = 0
    for i = 1, #LP.Name do h = (h * 31 + string.byte(LP.Name, i)) % 1000 end
    Follow.hopDelay = 0.25 + (h / 1000) * 1.5
    Follow._thread = task.spawn(function()
        while getgenv().STD_Hub == Hub and Follow.on do
            Follow.pace = 0.6
            pcall(Follow.step)
            -- the window is 30s and it is already running by the time the record
            -- appears. two seconds of sleep is 7% of it spent on nothing, and the
            -- alts are not the only ones walking through that portal
            task.wait(Follow.joined and 4 or (Follow.pace or 0.6))
        end
        Follow._thread = nil
    end)
end

function Follow.stop()
    Follow.on = false
    Follow._thread = nil
end

-- reads the identity every two seconds and puts this client on the right side
-- of it: same name -> take the emptiest portal, other name -> follow that one
-- one reconcile pass: what this client wants, what the shared file says, and
-- what it should therefore be doing. this is also why the toggle callback no
-- longer writes the crown by itself - the settings file is shared, so a toggle
-- restored on load is indistinguishable from a click, and on an alt that meant
-- "claim the crown too". now a restore only counts as intent, and intent is
-- reconciled against the file: if somebody else already holds it, the toggle
-- drops back down instead of stealing it
function King.tick()
    if King.inTick then return King.current end
    King.inTick = true
    local name, at, state = King.idEx()
    local tk = Toggles.KingMode
    local tf = Toggles.FollowKing
    local wantsKing = tk and tk.Value == true or false
    local wantsFollow = tf and tf.Value == true or false

    -- a file that exists but would not read is a write in flight, not an empty
    -- crown. decide nothing this pass and look again in two seconds
    if state == "empty" then
        King.inTick = false
        return King.current
    end

    -- an old-format file has no heartbeat yet; the holder adds one within a few
    -- seconds, so it is not abandoned until it has had that chance
    if name ~= nil and at == nil then
        at = os.time()
    end
    if name ~= nil and at ~= nil and os.time() - at > King.kingStale then
        King.release()
        name, at = nil, nil
    end

    if wantsKing then
        if name == nil then
            if King.claim() then
                name = LP.Name
            else
                -- lost the election. the other client is the king, so drop the
                -- toggle and let the follow branch below take over
                King.setToggle("KingMode", false)
                wantsKing = false
                name = King.idEx()
            end
        elseif name ~= LP.Name then
            -- taken. do not fight over it, just let go
            King.setToggle("KingMode", false)
            wantsKing = false
        else
            King.beat()
        end
    end

    King.current = name
    King.currentAt = at
    King.mine = (name == LP.Name)

    -- NOTHING HERE RELEASES THE CROWN.
    -- Giving it up is an explicit click (see the KingMode toggle below). Doing
    -- it from the tick meant that every client, for the second or so between
    -- loading and having its settings restored, saw "king mode off" while
    -- holding the crown - and released it. That is the random king: the file was
    -- deleted on every reload and the next alt with the toggle saved as on took
    -- it.

    if name ~= King.lastId then
        King.lastId = name
        Follow.manualOff = false
    end

    -- the server guard and the crown pull in opposite directions: the guard hops
    -- away from my own alts, the crown needs them standing in the same lobby as
    -- the portal. whichever is switched on, the guard is the one that gives way
    if name and Hub.Guard and Hub.Guard.on then
        Hub.Guard.on = false
        King.setToggle("AltHop", false)
    end

    if name == nil then
        if King.on then King.stop() end
        if Follow.on then Follow.stop() end
    elseif name == LP.Name then
        if Follow.on then Follow.stop() end
        if not King.on then
            King.on = true
            King.mine = true
            King.joined = false
            King.start()
        end
    else
        if King.on then King.stop() end
        if not Follow.on and not Follow.manualOff then
            Follow.king = name
            Follow.on = true
            Follow.joined = false
            Follow.start()
        end
    end

    -- keep the two toggles showing the truth, without re-entering the callbacks
    King.setToggle("KingMode", name == LP.Name)
    King.setToggle("FollowKing", name ~= nil and name ~= LP.Name and Follow.on)
    King.inTick = false
    return name
end

function King.sync()
    if King._sync then return end
    King._sync = task.spawn(function()
        while getgenv().STD_Hub == Hub do
            pcall(King.tick)
            task.wait(2)
        end
        King._sync = nil
    end)
end


--=============================================================
-- AUTO WIN  (anniversary event, needs Higuruma)
--=============================================================
-- the event map is a tower defence round like any other, so it is won the same
-- way: put a Justice Sorcerer down and keep its domain running. the domain's
-- minigame is what fills the gauge, 22 points fires the execution, and that is
-- the one-shot. so this does exactly two things - make sure a Higuruma of mine
-- is standing, and make sure the domain farm is running
local AutoWin = {}
Hub.AutoWin = AutoWin

AutoWin.on      = false
AutoWin.status  = "idle"
AutoWin._thread = nil

function AutoWin.inEvent()
    local info = workspace:FindFirstChild("Info")
    local m = info and info:FindFirstChild("Map")
    return m ~= nil and tostring(m.Value) == "Anniversary"
end

-- the equipped slot that is a Justice Sorcerer, matched on the template's own
-- AttackType so an evolved name still counts
function AutoWin.justice()
    for _, e in ipairs(Place.equipped()) do
        local t = Place.template(e.name)
        local cfg = t and t:FindFirstChild("Config")
        local at = cfg and cfg:FindFirstChild("AttackType")
        if at and tostring(at.Value) == "JusticeSorcerer" then return e end
    end
    return nil
end

function AutoWin.mine()
    local wt = workspace:FindFirstChild("Towers")
    if not wt then return nil end
    for _, m in ipairs(wt:GetChildren()) do
        local cfg = m:FindFirstChild("Config")
        local at = cfg and cfg:FindFirstChild("AttackType")
        local ow = cfg and cfg:FindFirstChild("Owner")
        if at and tostring(at.Value) == "JusticeSorcerer"
            and (not ow or ow.Value == LP.Name) then
            return m
        end
    end
    return nil
end

-- the server does not check the build area (measured: SpawnNewTower accepted a
-- CFrame 250 studs off the map), so anywhere near the player is fine. the
-- player's own feet first, then a ring around them
function AutoWin.place()
    local e = AutoWin.justice()
    if not e then return false, "no Higuruma in the loadout" end
    local ch = LP.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "no character" end
    local p = hrp.Position
    local right = hrp.CFrame.RightVector
    local look = hrp.CFrame.LookVector
    local spots = { p, p + right * 6, p - right * 6, p + look * 6, p - look * 6 }
    for i, spot in ipairs(spots) do
        if Place.spawnBestAt(spot, e) then
            return true, ("spot %d"):format(i)
        end
        task.wait(0.15)
    end
    return false, "every spot was refused"
end

function AutoWin.step()
    if not AutoWin.inEvent() then
        AutoWin.status = "not in the event"
        return
    end
    local info = workspace:FindFirstChild("Info")
    local running = info and info:FindFirstChild("GameRunning")
    if not (running and running.Value) then
        AutoWin.status = "waiting for the match"
        return
    end
    if not AutoWin.mine() then
        -- the loadout slots only exist once a match is live, so an empty
        -- equipped list here means "not yet", not "no Higuruma"
        if #Place.equipped() == 0 then
            AutoWin.status = "waiting for the loadout"
            return
        end
        AutoWin.status = "placing Higuruma"
        local ok, why = AutoWin.place()
        AutoWin.status = ok and ("placed, " .. tostring(why)) or ("place: " .. tostring(why))
        if not ok then return end
        task.wait(0.6)
    end
    -- one farm call starts a whole rotation that runs for minutes, so this is
    -- only ever the restart. the pause keeps a domain that refuses to cast from
    -- being hammered every two seconds
    if os.clock() < (AutoWin.nextTry or 0) then return end
    if Hub.points() < CFG.TargetPts then
        -- ensureFarm, not farmQTE. farmQTE is the FARM button's toggle: calling
        -- it while a rotation is running STOPS that rotation. A 2s poller
        -- calling a toggle is why the anniversary farm solved one or two
        -- minigames and then sat there - it kept cancelling its own work
        AutoWin.status = ("farming %.1f/%.0f"):format(Hub.points(), CFG.TargetPts)
        AutoWin.nextTry = os.clock() + 6
        if Hub.ensureFarm then Hub.ensureFarm() end
    else
        AutoWin.status = "gauge full - waiting for the execution"
        AutoWin.nextTry = os.clock() + 4
    end
end

function AutoWin.start()
    if AutoWin._thread then return end
    AutoWin._thread = task.spawn(function()
        while getgenv().STD_Hub == Hub and AutoWin.on do
            pcall(AutoWin.step)
            task.wait(2)
        end
        AutoWin._thread = nil
    end)
end

function AutoWin.stop()
    AutoWin.on = false
    AutoWin._thread = nil
    -- only stop the solver when nothing else owns it. AUTO QTE is a separate
    -- toggle and turning the anniversary farm off must not kill the farm the
    -- user asked for with the other switch - stop=true has no owner, so the
    -- driver would keep starting rotations that abort on their first check
    if Hub.solver and not CFG.AutoSolve then Hub.solver.stop = true end
end

--=============================================================
-- UI
--=============================================================
local annivLeft  = Tabs.Event:AddLeftGroupbox("portals", "clock")
local annivRight = Tabs.Event:AddRightGroupbox("auto join", "door-open")

lbl.counts = annivLeft:AddLabel("counts: -", true)
lbl.best   = annivLeft:AddLabel("best: -", true)
lbl.state  = annivRight:AddLabel("status: idle", true)

Anniv.refresh = function()
    pcall(function() lbl.counts:SetText("counts: " .. Anniv.summary()) end)
    local b = Anniv.best()
    pcall(function()
        lbl.best:SetText(b and ("best: %d/%d"):format(b.n, b.max) or "best: -")
    end)
    pcall(function() lbl.state:SetText("status: " .. tostring(Anniv.status)) end)
end

annivLeft:AddButton({
    Text = "refresh",
    Func = function()
        Anniv.list = Anniv.scan()
        Anniv.refresh()
    end,
})

annivLeft:AddButton({
    Text = "JOIN NOW",
    Func = function()
        Anniv.list = Anniv.scan()
        local b = Anniv.best()
        if not b then
            Anniv.status = "nothing open"
        else
            Anniv.status = ("joining %d/%d"):format(b.n, b.max)
            if Anniv.enter(b.model) then Anniv.status = "joined" end
        end
        Anniv.refresh()
    end,
})

annivLeft:AddDivider()
annivLeft:AddLabel("KING / FOLLOW", true)
lbl.king   = annivLeft:AddLabel("king: idle", true)
lbl.follow = annivLeft:AddLabel("follow: idle", true)
lbl.gate   = annivLeft:AddLabel("alts: -", true)
lbl.squad  = annivLeft:AddLabel("squad: -", true)
lbl.events = annivLeft:AddLabel("events: 0", true)

local function playerValues()
    local out = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LP then out[#out + 1] = pl.Name end
    end
    table.sort(out)
    if #out == 0 then out[1] = "(nobody here)" end
    return out
end

annivLeft:AddDropdown("KingName", {
    Values = playerValues(),
    Multi = false,
    Text = "king",
    Tooltip = "who the alts follow. this MIRRORS the crown: the account that holds it is what every " ..
              "client shows here, so all of them agree on one name. with no crown held, a name picked " ..
              "here stays picked - that is the fallback for following an account that does not run the " ..
              "hub. the list is who is in this server right now, so refresh it after a rejoin",
    Callback = function(v)
        Follow.king = (v and v ~= "(nobody here)") and v or nil
    end,
})

annivLeft:AddButton({
    Text = "refresh players",
    Func = function()
        local v = playerValues()
        pcall(function() Options.KingName:SetValues(v) end)
        -- NOT v[1]. that is the alphabetically first player in the server, and
        -- on six clients it picked a different "king" on each one - which is
        -- exactly the random king this window was showing. the only name worth
        -- selecting is the one the crown says
        local k = King.current
        local found = false
        if k then
            for _, n in ipairs(v) do if n == k then found = true break end end
        end
        pcall(function() Options.KingName:SetValue(found and k or nil) end)
        setStatus(found and ("king: " .. k) or "king: nobody holds the crown", found and "good" or "warn")
    end,
})

annivLeft:AddToggle("KingMode", {
    Text = "i am the king - go in first, alts follow",
    Default = false,
    Tooltip = "claims kingship for this account and saves it to the shared folder, so every other client " ..
              "on this machine sees the name and turns itself into a follower. waits for the squad to be " ..
              "staged, picks the emptiest portal big enough for all of you, walks in first and only then " ..
              "releases the alts. only ONE account can hold it - if two of them try, the loser drops its " ..
              "own toggle instead of fighting. the holder writes a heartbeat every few seconds, so a " ..
              "crown left behind by a closed client is freed after 30 s instead of following a ghost. " ..
              "turning it off HERE is what gives the crown up; nothing does it automatically",
    Callback = function(v)
        -- a restore during load is not a click. every client loads the same
        -- settings file, so without this the last account to load would take
        -- the crown from the real king
        if King.silent then return end
        if v then
            pcall(function() Toggles.AnnivAuto:SetValue(false) end)
            Anniv.auto = false
            Anniv.stop()
        else
            -- AN EXPLICIT CLICK IS THE ONLY THING THAT GIVES THE CROWN UP.
            -- And only if it is actually mine: releasing a crown that belongs to
            -- another account is how an alt ends up deleting the real king's
            -- name, after which the next client that wants it takes it - the
            -- random king again, one click away
            if King.idEx() == LP.Name then King.release() end
        end
        pcall(King.tick)
        setStatus(v and "king: claimed on this account" or "king: released", v and "good" or "warn")
    end,
})

annivLeft:AddToggle("FollowKing", {
    Text = "follow the king",
    Default = false,
    Tooltip = "reads the portal the king took and enters that exact one, never any other. " ..
              "on an alt this turns itself on the moment the main claims the crown - you only set it " ..
              "on the main. the king has to be in this same lobby for the portal to be here",
    Callback = function(v)
        if King.silent then return end
        if v then
            pcall(function() Toggles.AnnivAuto:SetValue(false) end)
            Anniv.auto = false
            Anniv.stop()
            Follow.manualOff = false
        else
            -- a deliberate off stays off until the crown changes hands
            Follow.manualOff = true
        end
        pcall(King.tick)
        setStatus(v and "follow: on" or "follow: off", v and "good" or "warn")
    end,
})

annivLeft:AddToggle("KingWaitAlts", {
    Text = "wait for the ticked alts before entering",
    Default = true,
    Tooltip = "the king goes in FIRST and opens the portal's 30s clock; the alts follow him inside " ..
              "that window. before he moves he waits until every TICKED account is standing in this " ..
              "lobby and has been for 3 s, so nobody is counted while still loading. the portal he picks " ..
              "must have a free seat for the whole squad - a portal too small for it drops the extras " ..
              "with a 256 disconnect. the roster is the one the server guard keeps; if a ticked alt never " ..
              "shows up he gives up after 90 s and goes in alone rather than stalling",
    Callback = function(v)
        King.waitAlts = v == true
        setStatus(v and "king: waits for the alts" or "king: goes in first", v and "good" or "warn")
    end,
})

annivLeft:AddButton({
    Text = "GO NOW - skip the wait",
    Func = function()
        King.skipGate = true
        setStatus("king: walking in now", "warn")
    end,
    Tooltip = "the current gate only. the next portal still waits for the alts",
})

--=============================================================
-- EVENT COUNTER + THE HOP AFTER IT
--=============================================================
annivLeft:AddToggle("KingAutoHop", {
    Text = "after each event: hop to the emptiest server",
    Default = true,
    Tooltip = "counts one event every time the squad comes back from a match, and then moves the " ..
              "whole squad to a server with NOBODY in it - no strangers to take a portal, and room " ..
              "for everybody. roblox does not always publish empty instances, so if there are none " ..
              "the emptiest that exists is taken. the king does NOT wait for the alts here: the game " ..
              "scatters everybody after a match and they often come back to different servers, so " ..
              "waiting would stall for a minute and leave them behind anyway. he waits two seconds " ..
              "for his own lobby to settle, writes the target down, and goes; every alt reads it from " ..
              "wherever it landed and follows, staggered by account name so six clients do not all " ..
              "load at once",
    Callback = function(v)
        King.autoHop = v == true
        setStatus(v and "king: hops to the emptiest server after each event" or "king: stays after an event",
            v and "good" or "warn")
    end,
})

annivLeft:AddButton({
    Text = "HOP TO EMPTIEST NOW",
    Func = function()
        local G = Hub.Guard
        if not (G and G.hopEmptiest) then
            setStatus("hop: no server guard", "bad")
            return
        end
        -- the move belongs to the king: he is the one who waits for the squad,
        -- and an alt pressing this would publish an order it cannot lead - the
        -- king does not read the hop record, so the squad would split
        if King.current and not King.mine then
            setStatus(("hop: %s is the king - press it there"):format(tostring(King.current)), "warn")
            return
        end
        local ok, err = G.hopEmptiest("manual")
        if not ok then setStatus("hop: " .. tostring(err), "warn") end
    end,
    Tooltip = "same move the king makes after an event, on demand: finds the quietest instance of " ..
              "this place, tells the alts where it went, then goes. only on the account that holds " ..
              "the crown - an alt pressing it would split the squad, because the king does not " ..
              "follow the hop record, he writes it. with no crown at all it just moves this client",
})

annivLeft:AddButton({
    Text = "reset the event counter",
    Func = function()
        King.resetEvents()
        setStatus("events: counter reset", nil)
    end,
    Tooltip = "the tally is a file on disk so it survives a reload; this is the only thing that " ..
              "puts it back to zero",
})

-- WHICH ALTS TO WAIT FOR.
-- The roster is every account the launcher files know about, and that is not the
-- same thing as every account that is actually running. One alt stuck on a black
-- screen used to cost the full 90s gate and, with it, whatever portal was open.
-- Unticking it here means the king stops counting it, while everything else
-- about the squad is unchanged: the portal is still sized for the union of the
-- ticked accounts and the ones already standing in the lobby, so an unticked alt
-- that is present still gets its seat and still follows.
King.loadSkip()

annivLeft:AddDropdown("KingSquad", {
    Values = King.names(),
    Default = King.checked(),
    Multi = true,
    Text = "wait for these alts",
    Tooltip = "ticked = the king waits for this account before he walks in. unticked = he does not, " ..
              "even if it is in the launcher's list. an account that is not in this server is the usual " ..
              "reason to untick one. an empty selection means everybody, not nobody - use GO NOW to go " ..
              "in alone on purpose. the list refreshes itself when the guard files change; press the " ..
              "button under it if you launched an alt while this window was open",
    Callback = function(v)
        King.setWait(v)
        setStatus(("king: waits for %d alt(s)"):format(#King.wanted()), nil)
    end,
})

annivLeft:AddButton({
    Text = "refresh the alt list",
    Func = function()
        local all = King.names()
        pcall(function() Options.KingSquad:SetValues(all) end)
        pcall(function() Options.KingSquad:SetValue(King.checked()) end)
        King._squadSig = table.concat(all, "|")
        setStatus(("%d account(s) in the launcher list"):format(#all), #all > 0 and "good" or "warn")
    end,
    Tooltip = "re-reads the guard's launcher files. new accounts arrive ticked, so a fresh alt is " ..
              "waited for without you having to find it in the list",
})

King.sync()

annivRight:AddToggle("AnnivAuto", {
    Text = "auto join 9-8, then 5-7",
    Default = false,
    Tooltip = "tries 9 and 8 first, fullest of them first. only if neither exists does it take 7, 6 or 5. " ..
              "ten is never taken because the seat is gone, and four or fewer is skipped entirely - " ..
              "in that case it keeps waiting instead of joining a dead lobby. if a portal is open but " ..
              "still has nobody in 9-8 or 5-7 after two minutes, it hops servers instead of sitting there",
    Callback = function(v)
        -- the king and the follower are separate loops with their own portal
        -- choice, so letting auto join run as well would have two loops racing
        -- for the same portals and landing in different ones. whichever side you
        -- turn on last wins, and the other toggle visibly drops back down
        if v and (King.on or Follow.on) then
            setStatus("king / follow is on - turn it off first", "warn")
            King.setToggle("AnnivAuto", false)
            Anniv.auto = false
            Anniv.stop()
            Anniv.refresh()
            return
        end
        Anniv.auto = v
        if v then
            Anniv.start()
            setStatus("event: watching portals", nil)
        else
            Anniv.stop()
            Anniv.status = "idle"
            setStatus("event: off", "warn")
        end
        Anniv.refresh()
    end,
})

annivRight:AddDivider()

annivRight:AddLabel("portals open every hour", true)
annivRight:AddLabel("takes 9-8 first, then 7-5, nothing else", true)
annivRight:AddLabel("nobody fills in 2 min -> server hop", true)
annivRight:AddDivider()
annivRight:AddLabel("AUTO WIN  (needs Higuruma)", true)
lbl.win = annivRight:AddLabel("win: idle", true)

annivRight:AddToggle("AnnivWin", {
    Text = "auto win - Higuruma + domain farm",
    Default = false,
    Tooltip = "on the event map: puts a Justice Sorcerer down next to you (the server does not check the " ..
              "build area, so anywhere works) and keeps the domain minigame running. 22 points fires the " ..
              "execution, and that is the one-shot",
    Callback = function(v)
        AutoWin.on = v
        if v then
            AutoWin.start()
        else
            AutoWin.stop()
        end
        setStatus(v and "auto win: on" or "auto win: off", v and "good" or "warn")
    end,
})

annivRight:AddDivider()

annivRight:AddLabel("TOKENS  (the ones on the floor)", true)
lbl.tok = annivRight:AddLabel("tokens: idle", true)

annivRight:AddToggle("TokenPick", {
    Text = "auto pick up tokens",
    Default = false,
    Tooltip = "the pinata drops are collected by the game's OWN client script, which lerps every drop that " ..
              "belongs to you toward your character and flips its Pickupable flag once it is close. that " ..
              "script reads one number, workspace.Info.MagnetRange, every frame - so this raises it and " ..
              "everything on the floor comes to you through the game's own code, with the game's own " ..
              "timing. drops that do not move (stuck behind geometry) are moved onto you after a second " ..
              "and the same loop picks them up",
    Callback = function(v)
        local T = Hub.Tokens
        if not T then return end
        if v then T.start() else T.stop() end
        setStatus(v and "tokens: picking up" or "tokens: off", v and "good" or "warn")
    end,
})

annivRight:AddToggle("TokenTp", {
    Text = "snap them in instantly",
    Default = false,
    Tooltip = "skip the magnet's lerp and move every drop onto you on the next tick. the game's own loop " ..
              "still does the actual pickup, so nothing about the award changes - this only removes the " ..
              "half second the lerp takes",
    Callback = function(v)
        local T = Hub.Tokens
        if T then T.snap = v == true end
        setStatus(v and "loot: instant" or "loot: magnet", nil)
    end,
})

annivRight:AddButton({
    Text = "what is on the floor",
    Func = function()
        -- the name filter is a guess. this prints what is actually around, so a
        -- pickup that is called something else can be added to the list
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then setStatus("no character", "warn") return end
        local here = hrp.Position
        local near = {}
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") then
                local d = (obj.Position - here).Magnitude
                if d < 120 then near[#near + 1] = { d = d, n = obj.Name } end
            end
        end
        table.sort(near, function(a, b) return a.d < b.d end)
        log(("nearby parts (%d within 120 studs, nearest 20):"):format(#near))
        for i = 1, math.min(20, #near) do
            log(("  %5.1f  %s"):format(near[i].d, near[i].n))
        end
        setStatus(("%d parts within 120 studs - see the log"):format(#near), nil)
    end,
    Tooltip = "logs the nearest 20 part names so the pickup filter can be matched to what the game " ..
              "actually calls them",
})

table.insert(Hub.threads, task.spawn(function()
    while getgenv().STD_Hub == Hub do
        pcall(function()
            local id = King.current
            local age = King.currentAt and (os.time() - King.currentAt) or nil
            lbl.king:SetText(("king: %s%s%s"):format(
                id or "nobody",
                id == LP.Name and "  (this account)" or "",
                (id and age) and ("  %ds ago"):format(age) or ""))

            -- THE KING DROPDOWN MIRRORS THE CROWN, AND NOTHING ELSE.
            -- It used to be built with Default = 1, and in Obsidian that means
            -- "the first entry in the list" - the alphabetically first OTHER
            -- player in the server. On six clients that is a different name on
            -- every one of them, which is exactly the random king this section
            -- was showing. Now it starts empty and only ever shows the account
            -- that actually holds the crown - and is cleared when the crown
            -- belongs to somebody who is not in this server
            if Options.KingName then
                local cur = Options.KingName.Value
                local want = (id and id ~= LP.Name) and id or nil
                -- only when there IS a crown. with none, whatever was picked by
                -- hand stays picked - that is the fallback path for following an
                -- account that is not running the hub at all
                if want and want ~= cur then
                    local listed = false
                    for _, n in ipairs(playerValues()) do
                        if n == want then listed = true break end
                    end
                    pcall(function() Options.KingName:SetValue(listed and want or nil) end)
                end
            end
            lbl.follow:SetText(("follow: %s%s"):format(
                tostring(Follow.status),
                Follow.king and ("   -> " .. Follow.king) or ""))
            local here = King.here()
            local txt = "nobody of mine here"
            if #here == 1 then
                txt = here[1]
            elseif #here == 2 then
                txt = here[1] .. ", " .. here[2]
            elseif #here > 2 then
                txt = ("%d here: %s, %s +%d"):format(#here, here[1], here[2], #here - 2)
            end
            lbl.gate:SetText(("alts: %s   %s"):format(txt, tostring(King.status)))

            -- the guard files are read after this window is built, so the tick
            -- list is pushed into the dropdown the first time the roster is
            -- actually non-empty, and again whenever it changes. only then: a
            -- SetValue on every pass would fight whatever the user is clicking
            local all = King.names()
            local sig = table.concat(all, "|")
            if #all > 0 and sig ~= King._squadSig then
                King._squadSig = sig
                pcall(function() Options.KingSquad:SetValues(all) end)
                pcall(function() Options.KingSquad:SetValue(King.checked()) end)
            end
            local wait = King.wanted()
            if #all == 0 then
                lbl.squad:SetText("squad: no launcher list - waits for nobody")
            elseif #wait == #all then
                lbl.squad:SetText(("squad: waiting for all %d alt(s)"):format(#all))
            else
                -- name the skipped ones: a count tells you something is off but
                -- not which account to go and look at
                local skipped = {}
                for _, n in ipairs(all) do
                    if King.skip[tostring(n):lower()] then skipped[#skipped + 1] = n end
                end
                local who = table.concat(skipped, ", ")
                if #who > 44 then who = #skipped .. " of them" end
                lbl.squad:SetText(("squad: wait %d/%d - not waiting for %s"):format(
                    #wait, #all, who))
            end
            lbl.win:SetText("win: " .. tostring(AutoWin.status))
            -- THE TALLY LIVES ON DISK, so an alt shows the same number as the
            -- king without ever counting anything itself. read it every three
            -- seconds rather than every pass - it only changes once a round
            if not King.mine and os.clock() > (King._evRead or 0) then
                King._evRead = os.clock() + 3
                pcall(King.loadEvents)
            end
            lbl.events:SetText(("events: %d   %s"):format(
                King.events or 0,
                King.autoHop and (King.mine and "hop after each" or "hop follows the king")
                             or "no hop"))
            local T = Hub.Tokens
            lbl.tok:SetText(T and ("tokens: %s   cleared: %d"):format(T.status, T.got) or "tokens: idle")
        end)
        task.wait(0.7)
    end
end))


local Units = {}
Hub.Units = Units

Units.thread = nil
Units.applied = 0
Units.spent = 0
Units._label = nil
Units._stat = nil

local function cfgOf(m)
    return m and m:FindFirstChild("Config")
end

function Units.mine()
    local out = {}
    local root = workspace:FindFirstChild("Towers")
    if not root then return out end
    for _, m in ipairs(root:GetChildren()) do
        local cfg = cfgOf(m)
        local own = cfg and cfg:FindFirstChild("Owner")
        if own and own.Value == LP.Name then
            table.insert(out, m)
        end
    end
    table.sort(out, function(a, b) return a.Name < b.Name end)
    return out
end

function Units.level(m)
    local lv = tostring(m.Name):match("(%d+)$")
    return tonumber(lv) or 1
end

function Units.damage(m)
    local cfg = cfgOf(m)
    if not cfg then return nil end
    local v = cfg:FindFirstChild("Damage") or cfg:FindFirstChild("MoneyPerRound")
    return v and v.Value or nil
end

function Units.range(m)
    local cfg = cfgOf(m)
    local v = cfg and cfg:FindFirstChild("Range")
    return v and v.Value or nil
end

function Units.upgradeModel(m)
    local f = RS:FindFirstChild("Functions")
    local up = f and f:FindFirstChild("UpgradeTower")
    if not up or not m or not m.Parent then return false end
    local before = m.Name
    local ok = pcall(function() up:InvokeServer(m) end)
    if not ok then return false end
    task.wait(0.06)
    if m.Parent == nil then return true end
    return m.Name ~= before
end

function Units.upgradeAll(passes)
    passes = passes or 1
    local total = 0
    for _ = 1, passes do
        local moved = 0
        for _, m in ipairs(Units.mine()) do
            if Units.upgradeModel(m) then
                moved = moved + 1
                total = total + 1
                task.wait(0.05)
            end
        end
        if moved == 0 then break end
        task.wait(0.1)
    end
    Units.applied = Units.applied + total
    return total
end

function Units.snapshot()
    local parts = {}
    for _, m in ipairs(Units.mine()) do
        local dmg = Units.damage(m)
        local rng = Units.range(m)
        local d = dmg and (dmg >= 1000 and ("%.1fk"):format(dmg / 1000) or tostring(math.floor(dmg))) or "?"
        local isMoney = cfgOf(m) and cfgOf(m):FindFirstChild("MoneyPerRound") ~= nil
        table.insert(parts, ("%s  %s %s%s"):format(m.Name, isMoney and "money" or "dmg", d,
            rng and ("  rng " .. tostring(rng)) or ""))
    end
    return #parts > 0 and table.concat(parts, "\n") or "no towers placed"
end

function Units.start()
    if Units.thread then return end
    Units.thread = task.spawn(function()
        while getgenv().STD_Hub == Hub do
            task.wait(1.5)
            if Units._label then
                pcall(function() Units._label:SetText(Units.snapshot()) end)
            end
            if Units._stat then
                pcall(function()
                    Units._stat:SetText(("upgrades this session: %d"):format(Units.applied))
                end)
            end
        end
        Units.thread = nil
    end)
end

function Units.stop()
    Units.thread = nil
end

--=============================================================
-- UI
--=============================================================
local unitLeft  = Tabs.Units:AddLeftGroupbox("my towers", "zap")
local unitRight = Tabs.Units:AddRightGroupbox("upgrade", "bot")

Units._label = unitLeft:AddLabel("scanning...", true)
unitLeft:AddButton({
    Text = "refresh",
    Func = function()
        pcall(function() Units._label:SetText(Units.snapshot()) end)
    end,
})

Units._stat = unitRight:AddLabel("upgrades this session: 0", true)

unitRight:AddButton({
    Text = "UPGRADE ALL",
    Func = function()
        local n = Units.upgradeAll(6)
        setStatus(("units: %d upgrade(s)"):format(n), n > 0 and "good" or "warn")
        pcall(function() Units._label:SetText(Units.snapshot()) end)
        pcall(function() Units._stat:SetText(("upgrades this session: %d"):format(Units.applied)) end)
    end,
})

unitRight:AddDivider()
unitRight:AddLabel("only towers owned by you", true)
unitRight:AddLabel("upgrades are recorded into the macro", true)

Units.start()

--=============================================================
--=============================================================
-- MOVEMENT  (this is the whole anti-afk now)
--=============================================================
-- measured on this executor, and it changes everything the old block assumed:
--   VirtualInputManager has no SendKeyDownEvent at all (the method is gone)
--   keypress() reports success and does nothing - IsKeyDown stays false,
--   MoveDirection never moves, and it only ever reaches the focused window,
--   which for eleven background clients is never the right one
--   Humanoid:Move sets MoveDirection but the game holds the character still:
--   grounded, Running, WalkSpeed 32, and the root never moves a stud
-- so there is no key to press. what is left is the shape of the input, which
-- is what was asked for: four camera relative directions, w then a then s then
-- d, each held, each blending into the next. the humanoid is told to walk that
-- way for the animation and the facing, and the root is carried along the same
-- vector, because on this client the root only moves if it is written to
local Move = {}
Hub.Move = Move

Move.on      = true
Move.speed   = 6      -- studs per second carried on top of whatever the humanoid does
Move.hold    = 0.45   -- one direction, seconds
Move.overlap = 0.12   -- the next direction blends in over this, so corners round off
Move.quiet   = 10     -- seconds of hands off the mouse before it starts walking
Move.lastUser = 0
Move.steps   = 0
Move.t0      = os.clock()
Move._drive  = nil
Move._thread = nil
Move._label  = nil
Move._err    = nil

-- the four directions are camera relative, exactly like wasd: w is where you
-- look, a is your left. the phase is read off the clock, not counted per frame,
-- so a lag spike cannot make the loop skip or crawl
function Move.dir()
    local cam = workspace.CurrentCamera
    if not cam then return Vector3.zero end
    local l = cam.CFrame.LookVector
    local r = cam.CFrame.RightVector
    l = Vector3.new(l.X, 0, l.Z)
    r = Vector3.new(r.X, 0, r.Z)
    if l.Magnitude < 0.01 or r.Magnitude < 0.01 then return Vector3.zero end
    l, r = l.Unit, r.Unit

    local t = os.clock() - Move.t0
    local seg = math.floor(t / Move.hold)
    local i = seg % 4 + 1
    local j = i % 4 + 1
    local frac = (t - seg * Move.hold) / Move.hold
    local edge = 1 - math.min(0.9, Move.overlap / Move.hold)
    local blend = 0
    if frac > edge then blend = (frac - edge) / (1 - edge) end

    local a, b
    if i == 1 then a = l elseif i == 2 then a = -r elseif i == 3 then a = -l else a = r end
    if j == 1 then b = l elseif j == 2 then b = -r elseif j == 3 then b = -l else b = r end

    local v = a + b * blend
    if v.Magnitude < 0.001 then return Vector3.zero end
    return v.Unit
end

function Move.drive(dt)
    if not Move.on then return end
    if (os.clock() - Move.lastUser) < Move.quiet then return end
    local okBox, box = pcall(function() return UIS:GetFocusedTextBox() end)
    if okBox and box then return end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and hrp) then return end
    if hum.Health <= 0 or hum.Sit then return end
    -- in the air the humanoid is not listening and a root write would just
    -- fight gravity. wait for the floor instead of flying
    if hum.FloorMaterial == Enum.Material.Air then return end
    local d = Move.dir()
    if d.Magnitude < 0.5 then return end
    hum:Move(d, false)
    hrp.CFrame = hrp.CFrame + d * Move.speed * dt
    Move.steps = Move.steps + 1
end

-- a mouse in your hand means you are at the machine and the client is getting
-- real input anyway, so the walk steps aside instead of dragging you around
-- while you play. only mouse, never keys: injected keys would loop it forever
function Move.arm()
    if Move._conn then return end
    Move._conn = UIS.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            Move.lastUser = os.clock()
        end
    end)
    table.insert(Hub.conns, Move._conn)
    Move._btn = UIS.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2 then
            Move.lastUser = os.clock()
        end
    end)
    table.insert(Hub.conns, Move._btn)
end

function Move.start()
    if Move._drive then return end
    Move.t0 = os.clock()
    Move.arm()
    -- Stepped, not RenderStepped: a background client stops rendering, and a
    -- stopped renderer means RenderStepped never fires. eleven clients of twelve
    -- are background windows, so the walk would run on one account out of twelve
    Move._drive = game:GetService("RunService").Stepped:Connect(function(_, dt)
        local ok, err = pcall(Move.drive, dt)
        if not ok and not Move._err then
            Move._err = true
            log("anti-afk: walk error " .. tostring(err))
        end
    end)
    table.insert(Hub.conns, Move._drive)
    if Move._thread then return end
    Move._thread = task.spawn(function()
        while getgenv().STD_Hub == Hub and Move._drive do
            if Move._label then
                pcall(function()
                    local state = "off"
                    if Move.on then
                        if (os.clock() - Move.lastUser) < Move.quiet then
                            state = "waiting"
                        else
                            state = "wasd"
                        end
                    end
                    Move._label:SetText(("walking: %s   steps: %d"):format(state, Move.steps))
                end)
            end
            task.wait(0.5)
        end
        Move._thread = nil
    end)
end

function Move.set(on)
    Move.on = on == true
    if Move.on then Move.t0 = os.clock() end
    setStatus(Move.on and "anti-afk: walking" or "anti-afk: stopped", Move.on and "good" or "warn")
end

function Move.stop()
    Move.on = false
    if Move._drive then
        pcall(function() Move._drive:Disconnect() end)
        Move._drive = nil
    end
    if Move._conn then
        pcall(function() Move._conn:Disconnect() end)
        Move._conn = nil
    end
    if Move._btn then
        pcall(function() Move._btn:Disconnect() end)
        Move._btn = nil
    end
    Move._thread = nil
end
--=============================================================
-- PINATA LOOT  (the things on the floor)
--=============================================================
-- Decompiled from the game's own LocalScript, not guessed: the drops live in
-- workspace.PiniataLoot as models with Config.Player (whose UserId they belong
-- to), Config.Pickupable (the flag the award hangs off) and RootPart. The game's
-- client script already runs a magnet on Heartbeat - it lerps every drop that is
-- ours toward the character and flips Pickupable itself once the drop is within
-- half a stud.
--
-- So there is nothing to walk to and nothing to click. The whole mechanic reads
-- one number, workspace.Info.MagnetRange, every frame. Raise that and every drop
-- on the map comes to you through the game's own code, with the game's own
-- timing, and the flag is flipped by the game, not by us - nothing about how the
-- award is validated changes.
--
-- The only thing done on top of that is a nudge for drops that do not move: the
-- magnet lerps at 0.2 per frame, so one stuck behind geometry sits there for
-- ever. After a second it is moved onto the character and the same game loop
-- picks it up on the next frame.
local Tokens = {}
Hub.Tokens = Tokens

Tokens.on      = false
Tokens.snap    = false   -- skip the wait, move every drop in on the next tick
Tokens.range   = 400     -- MagnetRange to hold while this is on, in studs
Tokens.status  = "idle"
Tokens.got     = 0
Tokens.list    = {}      -- [model] = when it was first seen
Tokens._thread = nil
Tokens._orig   = nil     -- the range the game shipped, put back on stop
Tokens.gen     = 0

function Tokens.folder()
    -- the game spells it "Piniata". both, in case a later build fixes the typo
    return workspace:FindFirstChild("PiniataLoot") or workspace:FindFirstChild("PinataLoot")
end

function Tokens.magnet()
    local info = workspace:FindFirstChild("Info")
    local v = info and info:FindFirstChild("MagnetRange")
    if v and v:IsA("ValueBase") then return v end
    return nil
end

-- one drop, if it is ours and still there to take
function Tokens.mine(m)
    local cfg = m:FindFirstChild("Config")
    if not cfg then return nil end
    local pl = cfg:FindFirstChild("Player")
    local pk = cfg:FindFirstChild("Pickupable")
    local root = m:FindFirstChild("RootPart")
    if not (pl and pk and root) then return nil end
    if pl.Value ~= LP.UserId then return nil end
    return pk, root
end

function Tokens.step()
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then Tokens.status = "no character" return end

    local mv = Tokens.magnet()
    if mv then
        if Tokens._orig == nil then Tokens._orig = mv.Value end
        -- re-applied every tick on purpose: this is a value the server owns, and
        -- if it puts it back the magnet goes back to its shipped reach
        if mv.Value < Tokens.range then mv.Value = Tokens.range end
    end

    local f = Tokens.folder()
    if not f then
        Tokens.status = "no pinata loot here"
        return
    end

    local now = os.clock()
    local live, moved = 0, 0
    for _, m in ipairs(f:GetChildren()) do
        local pk, root = Tokens.mine(m)
        if pk then
            if pk.Value then
                live = live + 1
                local seen = Tokens.list[m]
                if not seen then Tokens.list[m] = now seen = now end
                local d = (root.Position - hrp.Position).Magnitude
                if Tokens.snap or (d > 3 and (now - seen) > 1.2) then
                    pcall(function()
                        root.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 1, 0))
                    end)
                    moved = moved + 1
                end
            elseif Tokens.list[m] then
                Tokens.list[m] = nil
                Tokens.got = Tokens.got + 1
            end
        end
    end
    for m in pairs(Tokens.list) do
        if not m.Parent then
            Tokens.list[m] = nil
            Tokens.got = Tokens.got + 1
        end
    end

    if live > 0 then
        Tokens.status = ("%d on the floor, %d pulled"):format(live, moved)
    else
        Tokens.status = "nothing on the floor"
    end
end

function Tokens.start()
    if Tokens.on then return end
    Tokens.on = true
    Tokens.gen = (Tokens.gen or 0) + 1
    local gen = Tokens.gen
    Tokens._thread = task.spawn(function()
        while getgenv().STD_Hub == Hub and Tokens.on and Tokens.gen == gen do
            pcall(Tokens.step)
            if Tokens._label then
                pcall(function()
                    Tokens._label:SetText(("loot: %s   taken: %d"):format(Tokens.status, Tokens.got))
                end)
            end
            task.wait(0.2)
        end
        if Tokens.gen == gen then Tokens._thread = nil end
    end)
end

function Tokens.stop()
    Tokens.on = false
    Tokens.gen = (Tokens.gen or 0) + 1
    Tokens.status = "off"
    -- put the magnet back to whatever the game had it at. leaving it at 400 would
    -- change how the next round plays for no reason
    local mv = Tokens.magnet()
    if mv and Tokens._orig then pcall(function() mv.Value = Tokens._orig end) end
    Tokens._orig = nil
    Tokens.list = {}
end

--=============================================================
-- PLAZA ESCAPE
--=============================================================
-- the plaza teleport is issued by the server and it never asks the client, so
-- the walk above is the prevention and this is the cure. the way back is the
-- exact server the client came from, job id and all: the lobby is a different
-- queue, and dropping to it costs you the match you were sitting in. if that
-- job is gone it falls back to the same place, then to the lobby. every attempt
-- is followed by a ten second watch - still in the plaza means the attempt
-- failed, and the next one backs off instead of hammering the same teleport
local Plaza = {}
Hub.Plaza = Plaza

Plaza.PLACE = 17720234441
Plaza.HOME  = 17720162456
Plaza.file  = "STD_Hub_last_server.txt"
Plaza.on    = true
Plaza.delay = 2
Plaza.left  = 0
Plaza.fails = 0
Plaza.cool  = 0
Plaza.dead  = false
Plaza.lastPlace = nil
Plaza.lastJob   = nil
Plaza._thread = nil
Plaza._label  = nil

function Plaza.pid()
    local info = workspace:FindFirstChild("Info")
    local v = info and info:FindFirstChild("AfkID")
    if v then
        local ok, val = pcall(function() return v.Value end)
        if ok and tonumber(val) then return tonumber(val) end
    end
    return Plaza.PLACE
end

function Plaza.here()
    return game.PlaceId == Plaza.PLACE or game.PlaceId == Plaza.pid()
end

-- a method fetched off the instance and called as a plain function: the
-- __namecall hook that refuses teleports is a metamethod, and this path never
-- touches it. the same reason the guard uses it - hooks left behind by an
-- earlier hub instance cannot be trusted to be correct
local function rawCall(inst, name, ...)
    local fn = inst[name]
    if type(fn) ~= "function" then return false, "no " .. tostring(name) end
    local ok, err = pcall(fn, inst, ...)
    return ok, err
end

function Plaza.leave()
    local ts = game:GetService("TeleportService")
    local place, job = Plaza.lastPlace, Plaza.lastJob
    if place and place ~= Plaza.PLACE and place ~= Plaza.pid() then
        if job and job ~= "" then
            local ok = rawCall(ts, "TeleportToPlaceInstance", place, job, LP)
            if ok then return "same server" end
        end
        local ok = rawCall(ts, "Teleport", place, LP)
        if ok then return "same place" end
    end
    local ok = rawCall(ts, "Teleport", Plaza.HOME, LP)
    if ok then return "lobby" end
    return nil
end

-- the server you came from is written to disk, not just kept in the table:
-- a teleport reloads the client, the executor runs autoexec again, and the hub
-- that wakes up in the plaza has an empty table. without this it would always
-- fall back to the lobby and cost you the match server it was sitting in
function Plaza.remember(place, job)
    Plaza.lastPlace = place
    Plaza.lastJob = job
    if not writefile then return end
    local stamp = tostring(place) .. "|" .. tostring(job)
    if Plaza._saved == stamp then return end
    Plaza._saved = stamp
    pcall(writefile, Plaza.file, stamp)
end

function Plaza.recall()
    if Plaza.lastPlace then return end
    if not readfile then return end
    local ok, data = pcall(readfile, Plaza.file)
    if not ok or type(data) ~= "string" then return end
    local p, j = data:match("^(%d+)|([%w%-]+)")
    if p and j then
        Plaza.lastPlace = tonumber(p)
        Plaza.lastJob = j
    end
end

function Plaza.start()
    if Plaza._thread then return end
    Plaza.dead = false
    Plaza.recall()
    Plaza._thread = task.spawn(function()
        while not Plaza.dead and getgenv().STD_Hub == Hub do
            if not Plaza.here() then
                -- remembered every second, so the way back is always the server
                -- that was live a moment before the plaza grabbed you
                if game.PlaceId ~= Plaza.PLACE then
                    Plaza.remember(game.PlaceId, game.JobId)
                end
                if Plaza.fails > 0 and os.clock() > Plaza.cool then Plaza.fails = 0 end
            elseif Plaza.on and os.clock() >= Plaza.cool then
                if Plaza.delay > 0 then task.wait(Plaza.delay) end
                if Plaza.here() and not Plaza.dead then
                    local how = Plaza.leave()
                    if how then
                        Plaza.left = Plaza.left + 1
                        log(("plaza: leaving (%s), %d total"):format(how, Plaza.left))
                        setStatus("plaza: leaving (" .. how .. ")", "good")
                    end
                    local t0 = os.clock()
                    while Plaza.here() and not Plaza.dead and (os.clock() - t0) < 10 do
                        task.wait(0.5)
                    end
                    if Plaza.here() then
                        Plaza.fails = Plaza.fails + 1
                        Plaza.cool = os.clock() + math.min(60, 10 * Plaza.fails)
                        log(("plaza: still here, backing off %ds"):format(math.min(60, 10 * Plaza.fails)))
                        pcall(function()
                            rawCall(game:GetService("TeleportService"), "Teleport", Plaza.HOME, LP)
                        end)
                        task.wait(8)
                    else
                        Plaza.fails = 0
                    end
                end
            end

            if Plaza._label then
                pcall(function()
                    local state
                    if not Plaza.here() then
                        state = "away"
                    elseif Plaza.on and os.clock() < Plaza.cool then
                        state = ("in plaza, retry in %ds"):format(math.ceil(Plaza.cool - os.clock()))
                    elseif Plaza.on then
                        state = "in plaza - leaving"
                    else
                        state = "in plaza - staying"
                    end
                    Plaza._label:SetText(("plaza: %s   escapes: %d"):format(state, Plaza.left))
                end)
            end

            task.wait(1)
        end
        Plaza._thread = nil
    end)
end

function Plaza.stop()
    Plaza.dead = true
    Plaza._thread = nil
end
local afkBox = Tabs.Abil:AddRightGroupbox("Keep alive", "shield")

Move._label = afkBox:AddLabel("walking: wasd   steps: 0", true)

afkBox:AddToggle("AntiAfk", {
    Text = "walk in a circle (wasd)",
    Default = true,
    Tooltip = "w, a, s, d, camera relative, each direction held and blending into the next, so the " ..
              "character walks a loop instead of a square. this executor cannot press a key - " ..
              "VirtualInputManager has no SendKeyDownEvent and keypress does nothing - so the " ..
              "humanoid is told to walk the same vector for the animation and the root is carried " ..
              "along it. stands still while you type in chat or use the mouse",
    Callback = function(v) Move.set(v) end,
})

afkBox:AddDivider()

afkBox:AddSlider("AfkHold", {
    Text = "leg hold (ms)",
    Default = 450,
    Min = 150,
    Max = 1200,
    Rounding = 0,
    Callback = function(v) Move.hold = math.clamp((tonumber(v) or 450) / 1000, 0.15, 1.2) end,
})

afkBox:AddLabel("wasdwasd - never stands still", true)

afkBox:AddDivider()

Plaza._label = afkBox:AddLabel("plaza: away   escapes: 0", true)

afkBox:AddToggle("PlazaLeave", {
    Text = "auto-leave the afk plaza",
    Default = true,
    Tooltip = "if the server does move you there anyway, this takes you back to the exact server you came " ..
              "from, job id and all, then to the same place, then to the lobby. a failed attempt backs " ..
              "off instead of retrying the same teleport in a loop",
    Callback = function(v)
        Plaza.on = v == true
        if v then Plaza.cool = 0 Plaza.fails = 0 end
        setStatus(v and "plaza: leaving on sight" or "plaza: staying put", v and "good" or "warn")
    end,
})

afkBox:AddLabel("back to the same server, lobby as fallback", true)

Move.start()
Plaza.start()

--=============================================================
-- SERVER GUARD
--   every client running this hub drops its own userid into
--       STD_Hub_alts/<userid>.txt
--   that folder lives in the executor workspace, which every instance
--   the executor is attached to shares. so each client knows the full
--   set of accounts you own without talking to anything.
--
--   if one of those accounts turns up in the same server, the guard
--   hops to another instance of the same place. the job you left is
--   remembered and never picked again, so two of your clients cannot
--   bounce into each other in a loop.
--=============================================================
local Guard = {}
Hub.Guard = Guard

local ALT_DIR = "STD_Hub_alts"

Guard.on      = true
Guard.alts    = {}
Guard.names   = {}
Guard.here    = nil
Guard.hops    = 0
Guard.cool    = 0
Guard.left    = {}
Guard.grace   = 25
Guard.watch   = 3
Guard.minPlayers = 9
-- a server this empty is not worth staying in: leave for one with more people
Guard.keep    = true
Guard.keepPlayers = 8
Guard._label  = nil
Guard._thread = nil

local function me()
    return Players.LocalPlayer
end

local function altFile(uid)
    return ALT_DIR .. "/" .. tostring(uid) .. ".txt"
end

function Guard.count()
    local n = 0
    for _ in pairs(Guard.alts) do n = n + 1 end
    for _ in pairs(Guard.names) do n = n + 1 end
    return n
end

-- own account goes down first, before anything is read, so the next
-- client to start finds it
function Guard.register()
    if not writefile then return false end
    pcall(makefolder, ALT_DIR)
    local p = me()
    return (pcall(writefile, altFile(p.UserId), p.Name))
end

function Guard.load()
    Guard.alts = {}
    Guard.names = {}
    if not (listfiles and readfile) then return Guard.alts end
    local ok, files = pcall(listfiles, ALT_DIR)
    if not ok or type(files) ~= "table" then return Guard.alts end
    local self = me().UserId
    for _, f in ipairs(files) do
        local base = tostring(f):gsub("^.*[/\\]", "")
        local uid = tonumber((base:gsub("%.txt$", "")))
        if uid and uid ~= self then
            local name = ""
            pcall(function() name = tostring(readfile(f)) end)
            name = name:gsub("%s+$", "")
            Guard.alts[uid] = (name ~= "" and name) or tostring(uid)
        end
    end
    -- accounts written down by hand, by username. those clients may never run
    -- the hub, so they can never announce their userid - the name is the only
    -- handle on them. Player.Name is the unique username, not the display name
    local nf = ALT_DIR .. "/_names.txt"
    if readfile then
        local ok2, txt = pcall(readfile, nf)
        if ok2 and type(txt) == "string" then
            for line in txt:gmatch("[^\r\n]+") do
                local n = line:gsub("^%s+", ""):gsub("%s+$", "")
                if n ~= "" and n:sub(1, 1) ~= "#" then
                    Guard.names[n:lower()] = n
                end
            end
        end
    end
    return Guard.alts
end

function Guard.found()
    local self = me()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= self and (Guard.alts[p.UserId] or Guard.names[tostring(p.Name):lower()]) then
            return p
        end
    end
    return nil
end

local function httpGet(url)
    local req = (syn and syn.request) or (http and http.request) or http_request or request
    if type(req) == "function" then
        local ok, res = pcall(req, { Url = url, Method = "GET" })
        if ok and type(res) == "table" and type(res.Body) == "string" then return res.Body end
    end
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" and #body > 0 then return body end
    return nil
end

-- `floor`: only servers that hold more people than this many. used when the
-- reason to move is a server that emptied out - taking a server that is just as
-- empty would be a hop for nothing
function Guard.servers(floor)
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true")
        :format(game.PlaceId)
    local body = httpGet(url)
    Guard.lastError = "no body"
    if not body then return nil, "server list unreachable" end
    Guard.lastError = ("%d bytes"):format(#body)
    local ok, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(body)
    end)
    if not ok or type(data) ~= "table" then
        Guard.lastError = "decode failed: " .. tostring(body):sub(1, 120)
        return nil, "server list unreadable"
    end
    if type(data.data) ~= "table" then
        Guard.lastError = "no data: " .. tostring(body):sub(1, 120)
        return nil, "server list empty"
    end
    Guard.lastError = ("%d bytes, %d servers"):format(#body, #data.data)
    local list = {}
    for _, s in ipairs(data.data or {}) do
        local id      = s.id
        local playing = tonumber(s.playing) or 0
        local max     = tonumber(s.maxPlayers) or 0
        if id and id ~= game.JobId and max > 0 and playing < max and not Guard.left[id]
            and (not floor or playing > floor) then
            table.insert(list, { id = id, n = playing, max = max })
        end
    end
    -- only servers that already have people in them: dropping into a one-man
    -- server looks like nothing a normal player would ever land on. if nothing
    -- qualifies, take the fullest there is rather than the emptiest
    local want = {}
    for _, s in ipairs(list) do
        if s.n >= Guard.minPlayers then table.insert(want, s) end
    end
    if #want == 0 then
        -- leaving an empty server: no server at the wanted head count means stay put,
        -- never trade this one for another that is just as empty
        if floor then
            Guard.lastError = ("%d servers, none above %d players"):format(#data.data, floor)
            return {}
        end
        table.sort(list, function(a, b) return a.n > b.n end)
        want = list
    else
        table.sort(want, function(a, b) return a.n < b.n end)
    end
    Guard.lastError = ("%d servers, %d at %d+"):format(#data.data, #want, Guard.minPlayers)
    return want
end

function Guard.hop(reason, floor)
    if os.clock() < Guard.cool then return false, "cooling down" end
    Guard.cool = os.clock() + 20
    local list, err = Guard.servers(floor)
    if not list then
        setStatus("hop: " .. tostring(err), "bad")
        return false, err
    end
    if #list == 0 then
        -- nothing better to move to: keep the seat and check again later
        Guard.cool = os.clock() + 45
        setStatus("hop: " .. (floor and ("no server above " .. floor .. " players") or "no other server found"), "warn")
        return false, "empty"
    end
    -- one of the three emptiest, picked at random: two clients hopping at
    -- the same moment would otherwise both take the same one
    local pick = list[math.random(1, math.min(3, #list))]
    Guard.left[game.JobId] = true
    Guard.hops = Guard.hops + 1
    -- this client is moving itself on purpose. tell the king's watcher, or the
    -- new job looks like a round starting and it would sit in "in match" for
    -- the rest of the session. not published to the alts: a guard hop is one
    -- account escaping, not the squad relocating
    if Hub.King then Hub.King.hopTarget = pick.id end
    setStatus(("hop -> %s  %d/%d  (%s)")
        :format(tostring(pick.id):sub(1, 8), pick.n, pick.max, tostring(reason or "")), "warn")
    task.spawn(function()
        -- obj:method() runs through __namecall, and the hub's own no-afk hook
        -- reads the first argument of every teleport call. through a plain
        -- function reference the metamethod is skipped entirely, so the guard
        -- cannot be eaten by the hub's own filter
        local ts = game:GetService("TeleportService")
        local call = ts.TeleportToPlaceInstance
        local ok, err = pcall(function()
            call(ts, game.PlaceId, pick.id, me())
        end)
        if not ok then
            Guard.cool = os.clock() + 20
            setStatus("hop failed: " .. tostring(err), "bad")
        end
    end)
    return true
end

--=============================================================
-- THE EMPTIEST SERVER
--=============================================================
-- The guard's own search wants a server with PEOPLE in it: its job is to keep
-- the account away from your other alts without parking it in a dead instance.
-- Event farming wants the exact opposite. A quiet instance is one where no
-- stranger can take a portal out from under the squad and where the whole squad
-- fits with room to spare, so this search sorts the other way and never applies
-- the min-players floor at all
function Guard.emptiest()
    -- the exclusion list only has to stop a ping-pong, not remember the whole
    -- session: after a dozen hops it would exclude most of the place and the
    -- search would start coming back empty
    local seenN = 0
    for _ in pairs(Guard.left) do seenN = seenN + 1 end
    if seenN > 40 then Guard.left = {} end
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true")
        :format(game.PlaceId)
    local body = httpGet(url)
    if not body then return nil, "server list unreachable" end
    local ok, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(body)
    end)
    if not ok or type(data) ~= "table" or type(data.data) ~= "table" then
        return nil, "server list unreadable"
    end
    local list = {}
    for _, s in ipairs(data.data) do
        local id      = s.id
        local playing = tonumber(s.playing) or 0
        local max     = tonumber(s.maxPlayers) or 0
        if id and id ~= game.JobId and max > 0 and playing < max and not Guard.left[id] then
            list[#list + 1] = { id = id, n = playing, max = max }
        end
    end
    if #list == 0 then return nil, "no other server" end
    -- THE EMPTIEST ONE, full stop. sorted ascending by head count, so the head
    -- of the list is it; servers already visited are out of the list by then, so
    -- two hops in a row cannot land on the same instance
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n < b.n end
        return a.id < b.id
    end)
    return list[1]
end

-- go to a server that was already chosen. no search, no floor - the decision
-- was made, this only does the move
function Guard.hopTo(server, reason)
    if not server or not server.id then return false, "no server" end
    -- both ends are marked: the one being left so nothing comes back to it, and
    -- the one being entered so a later search does not bounce into it again
    Guard.left[game.JobId] = true
    Guard.left[server.id] = true
    Guard.hops = Guard.hops + 1
    Guard.cool = os.clock() + 25
    -- THIS IS THE ONLY PLACE THAT MARKS THE MOVE AS OURS. The king's job
    -- watcher needs it twice over: so his own move is not mistaken for a round
    -- starting, and so the moment he lands is the moment the squad is told
    -- where he is
    if Hub.King then Hub.King.hopTarget = server.id end
    setStatus(("hop -> %s  %d/%d  (%s)"):format(
        tostring(server.id):sub(1, 8), server.n or 0, server.max or 0, tostring(reason or "")), "warn")
    local place = server.place or game.PlaceId
    task.spawn(function()
        local ts = game:GetService("TeleportService")
        local call = ts.TeleportToPlaceInstance
        local ok, err = pcall(function() call(ts, place, server.id, me()) end)
        if not ok then
            Guard.cool = os.clock() + 20
            setStatus("hop failed: " .. tostring(err), "bad")
        end
    end)
    return true
end

-- the king's exit after a finished event: find the emptiest server, TELL THE
-- SQUAD FIRST, then go. the record has to be on disk before his own teleport is
-- even requested - his call blocks while it is processed, and the alts need to
-- already be moving by the time he lands
function Guard.hopEmptiest(reason)
    if os.clock() < Guard.cool then return false, "cooling down" end
    Guard.cool = os.clock() + 8
    local pick, err = Guard.emptiest()
    if not pick then
        setStatus("hop: " .. tostring(err), "warn")
        return false, err
    end
    -- nothing is published here. the king writes the job id down when he
    -- actually LANDS in it - see King.watchJob - so the squad is never sent to
    -- a server he only meant to go to
    return Guard.hopTo(pick, reason)
end

function Guard.start()
    if Guard._thread then return end
    Guard.register()
    Guard.load()
    local born = os.clock()
    Guard._thread = task.spawn(function()
        while getgenv().STD_Hub == Hub do
            pcall(function()
                Guard.here = Guard.found()
                if Guard._label then
                    Guard._label:SetText(("accounts: %d   here: %s   in server: %d   hops: %d   %d+ target")
                        :format(Guard.count(), Guard.here and Guard.here.Name or "-",
                            #(Players:GetPlayers()), Guard.hops, Guard.minPlayers))
                end
                if Guard.on and (os.clock() - born) > Guard.grace then
                    if Guard.here then
                        Guard.hop("alt " .. Guard.here.Name)
                    elseif Guard.keep then
                        local now = #(Players:GetPlayers())
                        if now < Guard.keepPlayers then
                            -- floor keeps the search above both this server and the wanted
                            -- head count, so a client cannot bounce between two dead servers
                            Guard.hop(("only %d players here"):format(now),
                                math.max(now, Guard.keepPlayers - 1))
                        end
                    end
                end
            end)
            task.wait(Guard.watch)
        end
        Guard._thread = nil
    end)
end

function Guard.stop()
    Guard.on = false
    if Guard._thread then
        pcall(task.cancel, Guard._thread)
        Guard._thread = nil
    end
end

local guardBox = Tabs.Abil:AddRightGroupbox("Server guard", "shield")

Guard._label = guardBox:AddLabel("accounts: 0   here: -   hops: 0", true)

guardBox:AddToggle("AltHop", {
    Text = "hop if my alt is here",
    Default = true,
    Tooltip = "every client running this hub writes its userid into STD_Hub_alts/ in the " ..
              "executor workspace, so each one knows the rest of your accounts. when one of " ..
              "them shows up in the same server this jumps to another instance of the same " ..
              "place, never back to the job it just left",
    Callback = function(v)
        Guard.on = v == true
        setStatus(v and "guard: on" or "guard: off", v and "good" or "warn")
    end,
})

guardBox:AddSlider("AltHopMin", {
    Text = "min players in target",
    Default = 9,
    Min = 0,
    Max = 40,
    Rounding = 0,
    Callback = function(v)
        Guard.minPlayers = v
        if Guard._label then
            pcall(function()
                Guard._label:SetText(("accounts: %d   here: %s   in server: %d   hops: %d   %d+ target")
                    :format(Guard.count(), Guard.here and Guard.here.Name or "-",
                        #(Players:GetPlayers()), Guard.hops, Guard.minPlayers))
            end)
        end
    end,
})

guardBox:AddToggle("AltHopKeep", {
    Text = "leave a server under 8 players",
    Default = true,
    Tooltip = "checks the head count every 3 s. below 8 people this looks for a server of " ..
              "the same place that is above the min-players slider and moves there; if no " ..
              "server is fuller than this one it stays put instead of hopping for nothing",
    Callback = function(v)
        Guard.keep = v == true
        setStatus(v and "guard: keeps 8+ players" or "guard: stays anywhere", v and "good" or "warn")
    end,
})

guardBox:AddButton({
    Text = "HOP NOW",
    Func = function() Guard.hop("manual") end,
    Tooltip = "leaves for another server of the same place right now, alt or not",
})

guardBox:AddButton({
    Text = "RESCAN MY ACCOUNTS",
    Func = function()
        Guard.register()
        Guard.load()
        Guard.here = Guard.found()
        setStatus(("guard: %d account(s) on file"):format(Guard.count()), "good")
    end,
    Tooltip = "re-reads the STD_Hub_alts folder. accounts land there by themselves the " ..
              "moment a client running this hub starts, so this only matters if you " ..
              "added or deleted one by hand",
})

guardBox:AddLabel("waits 25s after load, then hops on sight or under 8 players", true)

Guard.start()

Hub.destroy = function()
    pcall(function() Hub.stopAuto() end)
    pcall(function() Modes.stopAutoStart() end)
    Modes.stopAutoJoin()
    Flow.autoStart = false
    pcall(function() Noclip.stop() end)
    pcall(function() Caster.stop() end)
    Macros.autoSkip = false
    Macros.autoClaim = false
    -- every tab's recorder: stop capture and kill any playback still running
    for _, rec in ipairs(Rec.list or {}) do
        pcall(function() rec:stopPlayback() end)
        pcall(function() if rec.recording then rec:stop(true) end end)
    end
    pcall(function() Place.setClickMode(false) end)
    pcall(function() Place.setAutoHotbar(false) end)
    pcall(function() Place.pending = nil; Place.pendingPlaceholder = nil end)
    pcall(function() if Hub.Boogie then Hub.Boogie.setKey(false) end end)
    pcall(function() if Hub.Persist then Hub.Persist.stop() end end)
    Claim.autoQuests = false
    Claim.autoDaily = false
    Claim.autoChain = false
    pcall(function() if Hub.Pinata then Hub.Pinata.auto = false end end)
    pcall(function() Culling.stopAuto() end)
    pcall(function() Candy.stop() end)
    pcall(function() Anniv.stop() end)
    pcall(function() King.stop() end)
    pcall(function() Follow.stop() end)
    pcall(function() AutoWin.stop() end)
    pcall(function() Units.stop() end)
    pcall(function() AutoExit.stop() end)
    pcall(function() Replay.stop() end)
    pcall(function() Move.stop() end)
    pcall(function() Plaza.stop() end)
    pcall(function() Guard.stop() end)
    for _, c in ipairs(Hub.conns) do pcall(function() c:Disconnect() end) end
    for _, t in ipairs(Hub.threads) do pcall(function() task.cancel(t) end) end
    for _, t in ipairs(Macros.threads) do pcall(function() task.cancel(t) end) end
    pcall(function() Library:Unload() end)
    getgenv().STD_Hub = nil
end

print("[STD] hub v7 loaded - RightShift toggles the window")
