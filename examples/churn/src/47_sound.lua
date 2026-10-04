-- ---------------------------------------------------------------------
-- Sound effects: short melodies through solaros.audio
--
-- Game:sfx(name) plays SFX[name], a list of {Hz, ms} notes (Hz 0 = a rest).
-- tone_async queues them without stopping the game; plain tone (which
-- blocks for its length) is the fallback. M on the map mutes (self.muted,
-- saved). Never raises: a board without audio just stays quiet.
-- ---------------------------------------------------------------------

local SFX = {
    hit      = {{880, 40}, {1320, 50}},
    miss     = {{330, 60}},
    hurt     = {{220, 70}, {150, 90}},
    kill     = {{660, 60}, {880, 60}, {1320, 90}},
    geiger   = {{1800, 12}, {0, 25}, {1800, 12}},
    siren    = {{600, 150}, {900, 150}, {600, 150}, {900, 150}},
    -- (low, but not so low a small speaker can't play it)
    emission = {{196, 160}, {165, 160}, {139, 220}, {0, 60}, {196, 160}, {131, 500}},
    emission_cover = {{165, 200}, {147, 200}, {131, 400}},   -- it howls over your shelter
    emission_end = {{330, 90}, {392, 90}, {523, 160}},
    -- the title: a slow, wrong-sounding tune, once at start-up (begin_intro)
    title    = {{220, 400}, {0, 80}, {262, 300}, {330, 300}, {311, 500}, {0, 120}, {294, 300},
                {262, 300}, {247, 700}, {0, 150}, {220, 250}, {208, 900}},
    chime    = {{1047, 60}, {1568, 90}},
    gift     = {{784, 70}, {988, 70}, {1175, 120}},
    death    = {{392, 200}, {330, 200}, {262, 400}},
    escape   = {{523, 100}, {659, 100}, {784, 100}, {1047, 250}},
    bark     = {{500, 40}, {0, 40}, {450, 60}},
    whine    = {{700, 120}, {500, 200}},
    level    = {{659, 70}, {784, 70}, {988, 70}, {1319, 140}},
    achieve  = {{784, 80}, {1047, 80}, {1319, 80}, {1568, 200}},
}

function Game:sfx(name)
    if self.muted then return end
    local notes = SFX[name]
    local audio = solaros.audio
    if not (notes and audio) then return end
    local play = audio.tone_async or audio.tone
    if not play then return end
    for _, n in ipairs(notes) do
        if n[1] > 0 then
            pcall(play, n[1], n[2], 40)
        elseif audio.tone_async then
            pcall(play, 20, n[2], 0)   -- a silent step keeps the rhythm in the queue
        end
    end
    self.last_sfx = name   -- (for tests)
end

function Game:toggle_mute()
    self.muted = not self.muted or nil
    self:push_log(self.muted and "Sound off. (M)" or "Sound on. (M)")
end
