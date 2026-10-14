-- Runs the OTA upgrade, the same operation as the shell's `ota upgrade`.
--
-- Requires a firmware binding, solaros.ota.upgrade(), that does not exist yet.
-- On firmware without it, this script reports that and exits without changing
-- anything.

if solaros == nil or solaros.ota == nil or solaros.ota.upgrade == nil then
    print("ota upgrade: solaros.ota.upgrade is not available in this firmware")
    return
end

print("ota: resolving artifact")
local ok, err = pcall(solaros.ota.upgrade)
if not ok then
    print("ota upgrade failed: " .. tostring(err))
    return
end
print("ota: upgrade complete; rebooting")
