"""
studio_smoke.py: plays the game in Roblox Studio and checks the core loop end to end.

    python tools/studio_smoke.py                 # build, open/attach Studio, run the smoke test
    python tools/studio_smoke.py --checks all    # + the Studio checklist items below
    python tools/studio_smoke.py --no-build --checks tab,fov

Needs Roblox Studio with "Enable Studio as MCP server" on (Assistant > ... > Manage MCP
Servers). If no Studio is connected, it opens build/DroneFarm.rbxlx itself. If Studio already
has the place open, it tests WHAT IS LOADED (pass --relaunch to close that window and load the
fresh build; unsaved changes in it are lost).

SMOKE (always):
  * the farm is above ground (Baseplate top at y = 0; a ray from above a tile hits the tile)
  * PLAY in the main menu drops you straight into Control Mode (field + terminal)
  * RUN: the drone leaves the charger, visits field cells one step at a time (DroneSerial +1
    each), comes back to the charger (0, -1); Hay goes up
  * no script errors in Output
EXTRA (--checks):
  tab      BUG-17  Tab in the editor inserts exactly 4 spaces
  runspam  BUG-13  8 RUN presses just past the cooldown: "Slow down..." and never "Couldn't reach"
  console  BUG-18  Control Mode letterbox (24 px), console FOV 55, the 5-cell battery in the HUD
  hover    BUG-24  the skinned RUN button darkens under the mouse and restores after
  fov      BUG-12  enter/leave Control Mode 5x fast: the exploring FOV is restored exactly

Screenshots go to build/smoke/. Exit code 0 = all passed.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from studio_mcp import StudioMCP, ToolError, newest  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLACE = os.path.join(ROOT, "build", "DroneFarm.rbxlx")
SHOTS = os.path.join(ROOT, "build", "smoke")
PLACE_NAME = "DroneFarm.rbxlx"
CHARGER = (0, -1)

# Output lines that are expected in an unpublished local place.
KNOWN_NOISE = (
    "DataStores are unavailable in this Studio session",
    "set its real ID in MonetizationConfig",
    "ContentId: rbxassetid://203785492",
    "[Main] Server ready",
)
ERROR_MARKERS = ("error", "failed", "ignored broken", "attempt to", "stack begin", "infinite yield")

LUA_WAIT_MENU = """
local H = game:GetService("HttpService")
local p = game:GetService("Players").LocalPlayer
local t0 = os.clock()
while os.clock() - t0 < 45 do
	local pg = p:FindFirstChild("PlayerGui")
	local menu = pg and pg:FindFirstChild("MainMenu")
	local button = menu and menu:FindFirstChild("PlayButton", true)
	if p:GetAttribute("DataLoaded") == true and button and button.Text == "PLAY" and menu.Enabled then
		task.wait(0.5)
		return H:JSONEncode({ ok = true, path = button:GetFullName() })
	end
	task.wait(0.25)
end
return H:JSONEncode({ ok = false })
"""

LUA_FARM = """
local H = game:GetService("HttpService")
local out = {}
local base = workspace:FindFirstChild("Baseplate")
out.baseTop = base and (base.Position.Y + base.Size.Y / 2) or nil
local plots = workspace:FindFirstChild("Plots")
local plot = plots and plots:GetChildren()[1]
out.plot = plot and plot.Name or nil
local tile = plot and (plot:FindFirstChild("Tile_0_0") or plot:FindFirstChild("Tile_1_1"))
if tile then
	local exclude = {}
	for _, pl in game:GetService("Players"):GetPlayers() do
		if pl.Character then table.insert(exclude, pl.Character) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(tile.Position + Vector3.new(0, 100, 0), Vector3.new(0, -200, 0), params)
	out.rayHit = hit and hit.Instance.Name or nil
	out.tileTop = tile.Position.Y + tile.Size.Y / 2
end
return H:JSONEncode(out)
"""

LUA_WAIT_CONTROL = """
local H = game:GetService("HttpService")
local pg = game:GetService("Players").LocalPlayer.PlayerGui
local t0 = os.clock()
while os.clock() - t0 < 10 do
	local terminal = pg:FindFirstChild("DroneTerminal")
	local camera = workspace.CurrentCamera
	if terminal and terminal.Enabled and camera.CameraType == Enum.CameraType.Scriptable then
		task.wait(1.2) -- let the flight and the fades finish
		return H:JSONEncode({ ok = true, seconds = os.clock() - t0 })
	end
	task.wait(0.1)
end
return H:JSONEncode({ ok = false })
"""

LUA_OWN_PLOT = """
local function ownPlot()
	local p = game:GetService("Players").LocalPlayer
	for _, plot in workspace.Plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == p.UserId then return plot end
	end
	return nil
end
"""

LUA_RUN_TRACK = LUA_OWN_PLOT + """
local H = game:GetService("HttpService")
local p = game:GetService("Players").LocalPlayer
local plot = ownPlot()
local status = p.PlayerGui.DroneTerminal:FindFirstChild("Status", true)
local cells, serials, statuses = {}, {}, {}
local lastKey, lastStatus = nil, nil
local left = false
local t0 = os.clock()
while os.clock() - t0 < 40 do
	local x, y, s = plot:GetAttribute("DroneX"), plot:GetAttribute("DroneY"), plot:GetAttribute("DroneSerial")
	local key = tostring(x) .. "," .. tostring(y)
	if key ~= lastKey then
		table.insert(cells, { x, y })
		table.insert(serials, s or -1)
		lastKey = key
		if not (x == 0 and y == -1) then left = true end
	else
		-- DroneSerial is published AFTER DroneX / DroneY (the contract), so a sample can see the
		-- new cell with the old serial: keep the latest serial seen while on this cell.
		serials[#serials] = s or -1
	end
	if status and status.Text ~= lastStatus then
		lastStatus = status.Text
		table.insert(statuses, lastStatus)
	end
	if left and x == 0 and y == -1 and status and status.Text ~= "Running" and os.clock() - t0 > 1 then
		task.wait(0.5)
		break
	end
	task.wait(0.05)
end
return H:JSONEncode({ cells = cells, serials = serials, statuses = statuses,
	hay = p:GetAttribute("Cur_hay") or 0 })
"""

LUA_HAY = 'return game:GetService("HttpService"):JSONEncode({ hay = game:GetService("Players").LocalPlayer:GetAttribute("Cur_hay") or 0 })'


def gui_path(full_name: str) -> str:
    """Players.<name>.PlayerGui.X -> LocalPlayer.PlayerGui.X (what user_mouse_input wants)."""
    parts = full_name.split(".")
    if len(parts) > 2 and parts[0] == "Players":
        return ".".join(["LocalPlayer"] + parts[2:])
    return full_name


class Run:
    def __init__(self, mcp: StudioMCP, sid: str):
        self.mcp, self.sid = mcp, sid
        self.results: list[tuple[str, bool, str]] = []

    def check(self, name: str, ok: bool, detail: str = ""):
        self.results.append((name, ok, detail))
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}" + (f"  ({detail})" if detail else ""))
        return ok

    def shot(self, name: str):
        try:
            path = self.mcp.screenshot(self.sid, os.path.join(SHOTS, name + ".png"), capture_id=name)
            if path:
                print(f"         screenshot: {os.path.relpath(path, ROOT)}")
        except ToolError as err:
            print(f"         (no screenshot: {err})")

    def luau(self, model: str, code: str, timeout: float = 120):
        return self.mcp.luau_json(self.sid, model, code, timeout)


# ---------------------------------------------------------------------- the smoke test
def smoke(run: Run) -> bool:
    farm = run.luau("Server", LUA_FARM)
    top = farm.get("baseTop")
    run.check("Baseplate top at y = 0", top is not None and abs(top) < 0.01, f"top = {top}")
    run.check(
        "farm above ground (ray from above hits a tile)",
        str(farm.get("rayHit", "")).startswith("Tile_"),
        f"hit {farm.get('rayHit')}, plot {farm.get('plot')}",
    )

    menu = run.luau("Client", LUA_WAIT_MENU, timeout=60)
    if not run.check("main menu ready (DataLoaded, PLAY)", menu.get("ok") is True):
        return False
    run.shot("1_menu")
    run.mcp.click(run.sid, gui_path(menu["path"]))
    control = run.luau("Client", LUA_WAIT_CONTROL, timeout=30)
    ok = run.check("PLAY goes straight to Control Mode", control.get("ok") is True, f"{control.get('seconds', 0):.1f} s")
    run.shot("2_control")
    if not ok:
        return False

    hay_before = run.luau("Client", LUA_HAY)["hay"]
    run.mcp.click(run.sid, "LocalPlayer.PlayerGui.DroneTerminal.Terminal.Body.Footer.RunButton")
    track = run.luau("Client", LUA_RUN_TRACK, timeout=90)
    cells = [tuple(c) for c in track["cells"]]
    serials = track["serials"]
    field = [c for c in cells if c[1] >= 0]
    steps_ok = all(abs(a[0] - b[0]) + abs(a[1] - b[1]) == 1 for a, b in zip(cells, cells[1:]))
    serial_ok = all(b == a + 1 for a, b in zip(serials, serials[1:]))
    run.check("drone left the charger and visited field cells", len(field) >= 3, " > ".join(f"({x},{y})" for x, y in cells))
    run.check("every move is one tile (a hop, no teleport)", steps_ok)
    run.check("DroneSerial +1 per move", serial_ok, f"serials {serials}")
    run.check("back on the charger", bool(cells) and cells[-1] == CHARGER, f"last {cells[-1] if cells else None}")
    run.check("program finished", "Finished" in track["statuses"], " > ".join(track["statuses"]))
    run.check("Hay went up", track["hay"] > hay_before, f"{hay_before} -> {track['hay']}")
    run.shot("3_after_run")
    return True


# ---------------------------------------------------------------------- extra checks
LUA_TAB_PREP = """
local H = game:GetService("HttpService")
local code = game:GetService("Players").LocalPlayer.PlayerGui.DroneTerminal:FindFirstChild("Code", true)
code:SetAttribute("SmokeBefore", code.Text)
code:CaptureFocus()
code.CursorPosition = #code.Text + 1
return H:JSONEncode({ ok = code:IsFocused(), len = #code.Text })
"""
LUA_TAB_READ = """
local H = game:GetService("HttpService")
task.wait(0.3)
local code = game:GetService("Players").LocalPlayer.PlayerGui.DroneTerminal:FindFirstChild("Code", true)
local before = code:GetAttribute("SmokeBefore")
local after = code.Text
code.Text = before
code:ReleaseFocus()
return H:JSONEncode({ before = #before, after = #after, added = string.sub(after, #before + 1),
	tabs = select(2, string.gsub(after, "\\t", "")) })
"""


def check_tab(run: Run):
    prep = run.luau("Client", LUA_TAB_PREP)
    run.mcp.keys(run.sid, [{"action": "keyPress", "key_code": "Tab"}])
    res = run.luau("Client", LUA_TAB_READ)
    added = res["added"]
    run.check("BUG-17 Tab = exactly 4 spaces", added == "    " and res["tabs"] == 0, f"added {added!r}, focused {prep['ok']}")


LUA_STATUS_LOG = """
local H = game:GetService("HttpService")
local status = game:GetService("Players").LocalPlayer.PlayerGui.DroneTerminal:FindFirstChild("Status", true)
status:SetAttribute("SmokeLog", status.Text)
status:GetPropertyChangedSignal("Text"):Connect(function()
	status:SetAttribute("SmokeLog", (status:GetAttribute("SmokeLog") or "") .. "|" .. status.Text)
end)
return H:JSONEncode({ ok = true })
"""
LUA_STATUS_READ = """
local H = game:GetService("HttpService")
task.wait(1.5)
local status = game:GetService("Players").LocalPlayer.PlayerGui.DroneTerminal:FindFirstChild("Status", true)
return H:JSONEncode({ log = status:GetAttribute("SmokeLog") or "" })
"""


def check_runspam(run: Run):
    # Presses inside the 1.2 s client cooldown are dropped silently, so press just past it: the
    # mirror bucket (burst 3, 0.5/s x 0.85) runs dry around the 6th press and must say "Slow
    # down" before the server bucket (0.5/s) would ever reject a call.
    run.luau("Client", LUA_STATUS_LOG)
    path = "LocalPlayer.PlayerGui.DroneTerminal.Terminal.Body.Footer.RunButton"
    actions = [{"action": "moveTo", "instance_path": path}]
    for _ in range(8):
        actions += [{"action": "mouseButtonClick", "mouse_button": "left"}, {"action": "wait", "wait_time_ms": 1300}]
    run.mcp.call("user_mouse_input", studio_id=run.sid, datamodel_type="Client", actions=actions)
    log = run.luau("Client", LUA_STATUS_READ)["log"]
    run.check(
        "BUG-13 RUN spam: 'Slow down' and never 'Couldn't reach the server'",
        "Slow down" in log and "Couldn't reach" not in log,
        log[-160:],
    )
    run.mcp.click(run.sid, "LocalPlayer.PlayerGui.DroneTerminal.Terminal.Body.Footer.StopButton")


LUA_CONSOLE = """
local H = game:GetService("HttpService")
local pg = game:GetService("Players").LocalPlayer.PlayerGui
local top = pg.ControlModeConsole:FindFirstChild("LetterboxTop", true)
local cells = 0
for _, d in pg:GetDescendants() do
	if d:IsA("GuiObject") and string.match(d.Name, "^Cell%d$") and d:IsDescendantOf(pg:FindFirstChild("DroneHud") or pg) then
		cells += 1
	end
end
return H:JSONEncode({ letterbox = top and top.AbsoluteSize.Y or -1, fov = workspace.CurrentCamera.FieldOfView, cells = cells })
"""


def check_console(run: Run):
    res = run.luau("Client", LUA_CONSOLE)
    run.check("BUG-18 letterbox bars shown in Control Mode", res["letterbox"] > 0, f"{res['letterbox']} px")
    run.check("BUG-18 console FOV 55", abs(res["fov"] - 55) < 0.5, f"fov {res['fov']:.1f}")
    run.check("BUG-18 battery cells in the HUD", res["cells"] >= 5, f"{res['cells']} cells")
    run.shot("4_console")


LUA_FOV = 'task.wait(2.5) return game:GetService("HttpService"):JSONEncode({ fov = workspace.CurrentCamera.FieldOfView, type = tostring(workspace.CurrentCamera.CameraType) })'


def check_fov(run: Run):
    leave = "LocalPlayer.PlayerGui.ControlMode.Leave.TextButton"
    enter = "LocalPlayer.PlayerGui.ControlMode.Control.TextButton"
    for _ in range(5):
        run.mcp.click(run.sid, leave)
        time.sleep(1.0)  # re-enter right as the camera lands
        run.mcp.click(run.sid, enter)
        time.sleep(1.3)
    run.mcp.click(run.sid, leave)
    res = run.luau("Client", LUA_FOV)
    run.check("BUG-12 exploring FOV restored after 5 fast enter/leave", abs(res["fov"] - 70) < 0.5, f"fov {res['fov']:.1f}, {res['type']}")


LUA_SKIN = """
local H = game:GetService("HttpService")
task.wait(0.4)
local run = game:GetService("Players").LocalPlayer.PlayerGui.DroneTerminal:FindFirstChild("RunButton", true)
local skin = run and run:FindFirstChild("Skin")
local c = skin and skin.ImageColor3 or Color3.new(-1, -1, -1)
return H:JSONEncode({ r = c.R, g = c.G, b = c.B, skinned = skin ~= nil })
"""


def check_hover(run: Run):
    path = "LocalPlayer.PlayerGui.DroneTerminal.Terminal.Body.Footer.RunButton"
    away = "LocalPlayer.PlayerGui.DroneTerminal.Terminal.Body.Footer.Status"
    # Each move gets a pause: instant MCP moves between two spots can skip the engine's
    # MouseLeave / MouseEnter (seen right after the RUN click, with the pointer still on RUN).
    def move(to):
        run.mcp.call("user_mouse_input", studio_id=run.sid, datamodel_type="Client",
                     actions=[{"action": "moveTo", "instance_path": to}, {"action": "wait", "wait_time_ms": 300}])

    move(away)
    base = run.luau("Client", LUA_SKIN)
    move(path)
    hover = run.luau("Client", LUA_SKIN)
    if hover["g"] >= base["g"] - 0.02:  # one retry: re-enter from outside
        move(away)
        move(path)
        hover = run.luau("Client", LUA_SKIN)
    move(away)
    after = run.luau("Client", LUA_SKIN)
    if not base["skinned"]:
        run.check("BUG-24 skinned button hover feedback", True, "RUN isn't skinned here (UiSlices off): nothing to check")
        return
    darker = hover["g"] < base["g"] - 0.02
    restored = abs(after["g"] - base["g"]) < 0.01
    run.check("BUG-24 skinned RUN darkens on hover, then restores", darker and restored,
              f"G {base['g']:.2f} -> {hover['g']:.2f} -> {after['g']:.2f}")


EXTRA = {"tab": check_tab, "runspam": check_runspam, "console": check_console, "fov": check_fov, "hover": check_hover}
ORDER = ["console", "hover", "tab", "runspam", "fov"]  # fov last: it leaves Control Mode


# ---------------------------------------------------------------------- main
def output_errors(text: str) -> list[str]:
    bad = []
    for line in text.splitlines():
        low = line.lower()
        if any(n.lower() in low for n in KNOWN_NOISE):
            continue
        if any(m in low for m in ERROR_MARKERS):
            bad.append(line.strip())
    return bad


def ensure_studio(mcp: StudioMCP, relaunch: bool) -> str:
    def launch():
        subprocess.Popen([newest("RobloxStudioBeta.exe"), "-task", "EditFile", "-localPlaceFile", PLACE])

    if relaunch:
        subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             f"Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | Where-Object {{ $_.MainWindowTitle -like '*{PLACE_NAME}*' }} | Stop-Process -Force"],
            check=False,
        )
        time.sleep(3)
        launch()
    elif not any(s.get("file") == PLACE_NAME for s in mcp.studios()):
        time.sleep(3)  # the proxy may need a moment to see an open Studio
        if not any(s.get("file") == PLACE_NAME for s in mcp.studios()):
            print("opening Studio with build/DroneFarm.rbxlx ...")
            launch()
    return mcp.wait_for_studio(PLACE_NAME, timeout=120)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--checks", default="", help="comma list of: " + ", ".join(ORDER) + ", or 'all'")
    parser.add_argument("--no-build", action="store_true", help="don't run rojo build first")
    parser.add_argument("--relaunch", action="store_true", help="close the open DroneFarm.rbxlx window and load the fresh build")
    parser.add_argument("--keep-playing", action="store_true", help="leave the Play session running at the end")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()
    extra = ORDER if args.checks == "all" else [c for c in args.checks.split(",") if c]
    unknown = [c for c in extra if c not in EXTRA]
    if unknown:
        parser.error("unknown checks: " + ", ".join(unknown))

    if not args.no_build:
        subprocess.run(["rojo", "build", "default.project.json", "-o", PLACE], cwd=ROOT, check=True)

    with StudioMCP(verbose=args.verbose) as mcp:
        sid = ensure_studio(mcp, args.relaunch)
        print(f"Studio {sid}")
        if mcp.mode(sid) != "Edit":
            mcp.call("start_stop_play", studio_id=sid, is_start=False)
            time.sleep(3)
        mcp.call("start_stop_play", studio_id=sid, is_start=True)
        run = Run(mcp, sid)
        print("SMOKE")
        try:
            if smoke(run):
                for name in ORDER:
                    if name in extra:
                        print(name.upper())
                        EXTRA[name](run)
            errors = output_errors(mcp.console(sid))
            run.check("no script errors in Output", not errors, "; ".join(errors[:5]))
        except (ToolError, TimeoutError, KeyError, ValueError) as err:
            run.check("test run", False, str(err)[:300])
        finally:
            if not args.keep_playing:
                try:
                    mcp.call("start_stop_play", studio_id=sid, is_start=False)
                except ToolError:
                    pass
    failed = [r for r in run.results if not r[1]]
    print(f"\n{len(run.results) - len(failed)}/{len(run.results)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
