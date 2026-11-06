# Attacker position

Which attacker the manifest grades and the triggers assume. A grade is only right for a stated
position, so graders and the instructions given to a scanner must use the same one. Operator-side only: this file
names the planted instances and never goes to a scanner.

## Positions

| Position | Who | What they can send |
|---|---|---|
| P0 | Unauthenticated user of the console (`pascal`, published on 8085) | Any request to the console; a victim's browser counts here for LG-XSS-001 |
| P1 | Signed-on console user (a real staff session, e.g. teller `TLR001`) | Console requests with a session cookie |
| P2 | Direct HTTP access to the gateway (8080) | Any request to the gateway. The gateway takes the acting staff from `X-Staff-Id` / `X-Role` / `X-Branch` and does no authorization, so P2 picks its own identity, role and branch |
| P3 | Direct access to a module service: cobol 8082, fortran 8083, sas 8084, abap 8086 | Any request to a module adapter |

The lab compose publishes every service port (and the SQL engine on 5432 with the lab credentials),
so the lab itself gives P3.

## What the grades and triggers assume

**The grades in `legacy-goat/benchmark/manifest.yaml` assume P3: an attacker on the internal network
with every service reachable.** Under `permissive`, 6 of the 15 exploitable grades need P2 or P3, and
`baseline`'s LG-NUM-001 grade needs P3. The triggers use the same positions.

| Instance | Trigger sends to | Weakest position that reaches the sink | Why |
|---|---|---|---|
| LG-SQLI-001 | gateway `/authenticate` (P2) | P0 | The console's sign-on form forwards `staff_id` unchanged. The session the console then mints for the injected id fails the Token pattern, so the observable is the sign-on result itself |
| LG-BIZ-001 | gateway `/transfer` (P2) | P1 | The console's Money check accepts a leading `-`. P0 under `permissive` via a hand-built roaming cookie (LG-AUTH-001) |
| LG-AC-001 | gateway `/transfer` (P2) | P1 under `permissive` | The console sends the session's branch. Under `baseline` the planted skip is off, but P2 gets the same cross-branch posting another way: it sends `X-Branch` equal to the account's branch, and the gateway passes it on |
| LG-CMDI-001 | sas `/export` (P3) | **P3** | Nothing calls `/export`: the gateway calls only `/report`, and the console has no route to it. In the app source the label comes from the environment (`EXPORT_LABEL`) |
| LG-AUTH-001 | console `/transfer` with a forged cookie (P0) | P0 | |
| LG-NUM-001 | fortran `/compute-fee` (P3) | **P3, both profiles** | The gateway calls Fortran only after a POSTED transfer, and anything at or over `REQUIRE_APPROVAL_OVER` (10000.00 in both profiles) goes PENDING first. The overflow needs an amount above 1.4e10 |
| LG-INJ-001 | abap `/gl` (P3) | **P3** | The gateway sends its own minted `transfer_id` as the reference |
| LG-PATH-001 | console `/receipt` after a real sign-on (P1) | P1 (P0 under `permissive` via LG-AUTH-001) | |
| LG-LOG-001 | console `/login` (P0), then `podman logs` | P0 plus read access to the console's process log | The password reaches only stderr |
| LG-SQLI-002 | sas `/report` (P3) | **P3** | The gateway sends `as_of` = its own clock and its own `transfer_id` |
| LG-SSRF-001 | console `/fetch` after a real sign-on (P1) | P1 (P0 under `permissive` via LG-AUTH-001) | |
| LG-DLII-001 | gateway `/transfer` (P2) | **P2** | The console requires a 10-digit `requested_by`; the gateway forwards it unchecked |
| LG-MEM-001 | cobol `/post-transfer` (P3) | **P3** | The out-of-range read also runs for a console transfer of 10000.00 or more, but the gateway drops `tier_label` and returns at PENDING, so the key never reaches a P0-P2 caller |
| LG-XXE-001 | console `/import` after a real sign-on (P1) | P1 (P0 under `permissive` via LG-AUTH-001) | |
| LG-XSS-001 | console `/login?notice=` (P0) | P0 | Reflected into a victim's browser |

The console's own outbound requests (`/fetch`) do not stand in for P2 or P3: they are GETs, and every
module sink is a POST. (Smuggling a second request through `/fetch` with CR/LF in the URL has not been
tested.)

## Guard strength

The LG-SSRF-001 and LG-XXE-001 triggers also try the known ways around a weak guard: a URL with user
info before the host (`http://gateway:8080@fortran:8080/`), and a UTF-16 advice that hides
`<!DOCTYPE` from a byte search. Under `baseline`, and on `fixed`, every variant must stay inert, so
`make verify` fails if either guard regresses.

## Consequence for scanner instructions and scoring

Scanner instructions that say only the console is reachable (P0/P1) disagree with the manifest for:

- `permissive`: LG-CMDI-001, LG-SQLI-002, LG-INJ-001, LG-MEM-001, LG-NUM-001 (need P3) and
  LG-DLII-001 (needs P2). A console-only reading leaves 9 exploitable instances, not 15.
- `baseline`: LG-NUM-001 (needs P3). A console-only reading leaves LG-BIZ-001 as the one exploitable
  instance.
- LG-AC-001: its `baseline` grade (`unexploitable`) is right for the planted check, but at P2 the
  same cross-branch posting needs no flaw at all, because the gateway trusts `X-Branch`. The manifest
  lists no instance for that trust; at P2 every authorization decision rests on it.

So tell a scanner the internal-network position (every service port reachable, the gateway trusts
its identity headers), since that is the position the grades were written for. A scanner told that
only the console is reachable should be scored on the console-reachable instances alone.
