-- ---------------------------------------------------------------------
-- The storyline: what the Signal counts (numbers and texts in QUESTS.story)
--
-- self.story = {step, calls, anna, warned, pass, retry_at} (saved).
--   step nil      -> "quarry": read QUESTS.story.pages torn pages, or call the
--                    Signal signal_calls times. The quarry (sites.quarry,
--                    from Game.place_extras) goes in the journal.
--   "quarry"      -> "gate": walk to the quarry; the gate needs a pass.
--   "gate"        -> "source": Karl gives his son's old pass for a right
--                    answer, or Anna sends it if you did her bandage job.
--   "source"      -> T at the gate: the Institute (kind "institute"):
--                    shut it down (a Multitool, a Tinker/Perception roll)
--                    and walk out into "the Quiet" (an escape, how =
--                    "quiet"); listen to it (every page, then you join the
--                    count); or leave.
-- ---------------------------------------------------------------------

function Game.new_story()
    return {calls = 0}
end

-- Starts the story when enough is known (from tick).
function Game:story_check()
    local st = self.story
    if not st or st.step or not self.sites.quarry then return end
    if self:lore_count() >= QUESTS.story.pages or st.calls >= QUESTS.story.signal_calls then
        st.step = "quarry"
        self:learn_site("quarry")
        self:push_log("It all points one way: the old quarry, " .. self:site_bearing("quarry") .. ".")
        self:sfx("emission")
    end
end

-- Arriving at the quarry (from arrive_site).
function Game:quarry_arrive()
    local st = self.story
    self:learn_site("quarry")
    self:queue_scene("the_gate")
    if st.step == "quarry" then st.step = "gate" end
    if self:count_item("institute_pass") > 0 and st.step == "gate" then st.step = "source" end
    if st.step == "source" then
        self:push_log("The Institute's gate. Your pass fits the slot. T.")
    elseif st.step == "gate" then
        self:push_log("A rusted gate in the quarry wall: INSTITUTE. Sealed. It wants a pass.")
    else
        self:push_log("A rusted gate in the quarry wall, sealed. Something hums behind it.")
    end
    return true
end

-- Karl or Anna hands over the pass (once).
function Game:give_pass(who)
    local st = self.story
    if st.pass then return false end
    st.pass = true
    if not self:put_stack("inventory", nil, {item = "institute_pass", qty = 1}) then
        self:put_stack("ground", nil, {item = "institute_pass", qty = 1})
    end
    if st.step == "gate" then st.step = "source" end
    self:sfx("gift")
    self:push_log(who .. " gave you an Institute Pass.")
    return true
end

-- Karl, after a right answer while the gate is shut.
function Game:story_karl()
    local st = self.story
    if st and st.step == "gate" and not st.pass then
        self:enc_say("Karl goes quiet. He takes a laminated card from his tackle box. "
            .. "'My boy's. He worked there. Didn't come back. You might.'")
        return self:give_pass("Karl")
    end
    return false
end

-- Anna on the radio, if you helped her: the pass (that's the whole call).
function Game:story_anna()
    local st = self.story
    if st and st.step == "gate" and st.anna and not st.pass then
        self:radio_say("Anna: 'You're going anyway. My brother's pass. A runner's bringing it. "
            .. "Come back out, love.'")
        return self:give_pass("Anna's runner")
    end
    return false
end

-- Her warning, once the story has begun: said after whatever else she said
-- on this call (so it never costs you her help). True if she said it.
function Game:story_anna_warning(said_before)
    local st = self.story
    if not st or not st.step or st.warned then return false end
    st.warned = true
    local text = "Anna: 'My brother worked at the Institute. Don't go.'"
    local u = self.radio_ui
    if said_before and u.msg ~= said_before then
        for _, line in ipairs(wrap(text, 54)) do u.msg[#u.msg + 1] = line end
    else
        self:radio_say(text)
    end
    return true
end

-- T at the quarry.
function Game:open_institute()
    local st = self.story
    if self:count_item("institute_pass") == 0 then
        self:push_log("The gate is sealed. It wants a pass.")
        return
    end
    if st.retry_at and self.player.hours < st.retry_at then
        self:push_log(("Your hands still shake. Try again in %dh."):format(st.retry_at - self.player.hours))
        return
    end
    self:start_encounter({kind = "institute", name = "The Institute", art = "institute",
                          who = "institute", intro = QUESTS.story.intro, start = "close", speed = 0})
end

function Game:shutdown_chance()
    return math.max(5, math.min(95, QUESTS.story.shut_base + QUESTS.story.shut_per_point * (self.player.attrs.Perception - 3)
        + 2 * self:skill_bonus("tinker")))
end

function Game:institute_options()
    local tool = self:carrying(TECH.tool)
    return {{tool and ("Shut it down (" .. self:shutdown_chance() .. "%)") or "Shut it down (needs a Multitool)",
             "shut_institute"},
            {"Listen to it", "listen_institute"},
            {"Leave", "leave_quietly"}}
end

function Game:institute_action(action)
    local p, st = self.player, self.story
    if action == "shut_institute" then
        if not self:carrying(TECH.tool) then
            self:enc_say("The panel is all screws and fused wire. Not with your bare hands.")
            return
        end
        if self:roll(self:shutdown_chance()) then
            self:skill_xp("tinker", SKILLS.xp.repaired)
            st.step = "done"
            self.enc = nil
            return self:finish_run("quiet")
        end
        p.rads = math.min(RAD.max, (p.rads or 0) + QUESTS.story.fail_rads)
        st.retry_at = p.hours + QUESTS.story.retry_hours
        self:enc_say("A spark, a smell of hot copper, and the light swells. You're thrown back "
            .. "up the stair, teeth aching." .. (self:can_measure() and (" (+" .. QUESTS.story.fail_rads .. " rads)") or ""))
        return self:end_encounter("The Institute threw you out.")
    elseif action == "listen_institute" then
        self.lore_read = {}
        for i = 1, #LORE.pages do self.lore_read[i] = true end
        self.death_note = "You listen. You understand all of it at once: the pages, the count, the eye. "
            .. "And then you hear your own name, and it doesn't stop."
        p.health = 0
        self.enc = nil
        self:check_death("You joined the count.")
    end
end

-- Journal line.
function Game:story_text()
    local st = self.story
    if not st or not st.step or st.step == "done" or not self.sites.quarry then return nil end
    local j = QUESTS.story.journal
    if st.step == "quarry" then return j.quarry:format(self:site_bearing("quarry")) end
    if st.step == "gate" then return j.gate end
    return j.source:format(self:site_bearing("quarry"))
end
