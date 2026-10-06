---
id: EPIC-01
title: Trash bin
type: EPIC
products: [academy]
---

**Introduction**
As a content manager, I want deleted paths and units to go to a trash bin, so that a deletion can be undone until someone decides it is final.

The trash bin replaces immediate deletion with archiving, and gives each role a place to restore or permanently delete what it is responsible for.

**Product requirement**
- Archiving a path or a unit removes it from the catalogue and from every selection list
- A trash bin page lists what the current role is responsible for
- Archived items can be restored, or deleted for good, according to the role

**Technical requirement**
- Archiving is reversible: no data is removed until a permanent deletion
- The history of what users did on an item is kept after archiving

**Design requirement**
- The trash bin is reachable from the profile menu for the roles that can use it

**Scope**
- In: paths and units
- Out: unit chapters, which have no trash bin

**Risks**
- Path–unit relations could lose integrity across archive and restore
