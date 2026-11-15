# Kids Edition changelog

## Bug fixes
- Last-jump bug: running the tank to 0 on the jump to the final stop counted as "out of fuel" because the ship was
  not moved yet. The ship now moves first, so reaching the destination always counts.
- Soft-lock: with fuel below the cost of one jump (but above 0) the player could be stuck forever. A tow-truck
  care package now helps, or the mission ends gently if none are left.
- Double-click on the map could start two jumps at once. Travel is now guarded while a jump plays.
- After a jump cutscene the game kept going even if the mission had ended or you went back to the menu. It now checks first.
- Starting a new mission now resets leftover pending-call, travel and quiz state.
- Winning/losing sound: the supplied win/lose files had a `.mpeg` ending Godot cannot load. They are now
  `assets/generated/audio/win.mp3` and `lose.mp3`, which the game already looks for.
- Removed the unused duplicate `Main.gd` (a second copy of old logic) and the dev-tool addons (godot_ai, ziva_agent) with
  their native binaries; the project opens cleanly without them.

## Kids-friendly changes
- No fighting: "Hostile Contact" battles became **Puzzle Gates** (a friendly critter asks a science question;
  wrong answers still teach and never hurt).
- Weapons became the **Tractor Beam** (free hints). Ordnance became **Hint Crystals**.
- Lifelines: 3 Mission Control care packages replace instant game-over.
- Junior band: supplies drain slower, bad events hurt less (x0.6).
- Rewrote the gross-out and spooky wording (recycler, "mutiny", defeat messages). Replaced the real-celebrity rapper
  call with Astronaut Hala.
- Brighter, rounder cosmic-candy colors, a mascot (Mishmish the space cat), silly planet names on the map.

## New
- Explorer level picker (Junior / Middle School), 32-question quiz bank, tests/ folder with a balance simulation
  and an automatic playthrough.
