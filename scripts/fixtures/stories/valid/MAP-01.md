---
id: MAP-01
title: Trash bin story map
type: MAP
products: [academy]
---

**Introduction**
As a content manager, I want deletions to be reversible until someone decides they are final, so that no content is lost by mistake.

**Outcome**
Archived paths and units leave the catalogue but stay recoverable; each role restores or permanently deletes what it is responsible for.

**Backbone**
| Activity | 1. EPIC [EPIC-01] Trash bin |
|---|---|
| User tasks | archive an item<br>restore it<br>delete it for good |

**Walking Skeleton**
- SPIKE [SPIKE-01] Can a restore keep the active enrolments?: the data risk behind restoring

**Release lanes**
*Release 1 — MVP.* Objective: no deletion is final by accident. Metrics: no support ticket for lost content.
- EPIC [EPIC-01] Trash bin: US [US-01] Archive a path; US [US-02] Ripristinare un elemento archiviato

**DoR Check**
- Narrative — archive, then restore: the order a manager lives it in
- Vertical — the single lane crosses the single epic end to end
- Gravity — archiving comes before restoring, which needs something archived
- Functional — every step is something a manager does, none is a layer
- Walking skeleton vs MVP — the spike tests the data risk; the MVP is the two stories
- Elevator pitch — "deleted content waits in a trash bin until someone decides" fits in one breath
