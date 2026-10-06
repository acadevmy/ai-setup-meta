# Worked examples

Three runs taken from real cases, in the draft format of `templates.md`. The
story language is English in all three; the ids are provisional and valid
inside one example only. Read the one closest to your run before the first
draft.

## Index

- [Example 1 — a structured brief becomes an epic](#example-1--a-structured-brief-becomes-an-epic)
- [Example 2 — an architectural request: ask first](#example-2--an-architectural-request-ask-first)
- [Example 3 — seven scenarios, kept whole](#example-3--seven-scenarios-kept-whole)

## Example 1 — a structured brief becomes an epic

**What it teaches:** splitting a whole lifecycle with Operations and
Variations in Data, isolating the view from the actions, and keeping the
business rules of each role in scenarios rather than in stories per role.

**The request.** A brief for a learning platform: paths and units that are
deleted should go to a trash bin, from which they can be restored or deleted
for good. Editors may archive and restore their own units; managers their own
paths and units, including what their editors archived; administrators
anything. Only managers and administrators may archive an item with active
enrolments, after a warning. On restore, a unit gets its path relation back.
`product.md` names the three roles and has a permission matrix.

**The shape.** One user activity (cleaning up content) but a whole lifecycle —
archive, browse, restore, delete for good — on two entities with different
permissions: an Epic with seven stories. Archiving a path and archiving a unit
are separate stories (Variations in Data: different roles may do each);
browsing the trash bin is its own story (read vs write); restoring and
deleting for good follow archiving.

```markdown
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
```

```markdown
---
id: US-01
title: Archive a path
type: US
products: [academy]
relations:
  "EPIC-01":
    title: "Trash bin"
    type: EPIC
    relationType: PARENT
    reason: "the epic this story belongs to"
---

**User Story**
As a manager, I want to move a path to the trash bin, so that it leaves the catalogue without losing its history or risking an accidental deletion.

**Outcome**
An archived path disappears from the catalogue and from every form that lets you pick a path, and can still be recovered.

**Acceptance Criteria**
**Scenarios**

**Scenario:** archiving a path
**Given** a manager editing a path they are responsible for
**When** they archive it
**Then** they are told the path was archived
**And** the path no longer appears in the catalogue, in its units or in any path selection

**Scenario:** a role that may not archive
**Given** an editor viewing a path
**When** they look for a way to delete it
**Then** archiving is not available to them

**Scenario:** archiving in progress
**Given** a manager who asked to archive a path
**When** the archiving is still running
**Then** they see that it is in progress
**And** they cannot edit the path meanwhile

**Scenario:** archiving fails
**Given** a manager who asked to archive a path
**When** the archiving fails
**Then** they are told it failed
**And** they can edit the path again

**Additional Notes**
- Paths with active enrolments are a separate story: archiving them needs a warning first
```

The other five, listed in release order with the pattern that produced each:

- `US [US-02] Archive a unit` — Variations in Data: editors may archive units, not paths.
- `US [US-03] Archive a path with active enrolments` — Business Rule Variations: the warning and its refusal, for managers and administrators only; blocked by "Archive a path".
- `US [US-04] Browse the trash bin` — Operations, the read side: the list filtered by role, with its empty, loading and error states.
- `US [US-05] Restore an archived item` — Operations: restoring brings a unit's path relation back; blocked by "Browse the trash bin".
- `US [US-06] Delete an archived item for good` — Operations: an irreversibility warning first; blocked by "Browse the trash bin".

## Example 2 — an architectural request: ask first

**What it teaches:** a purely architectural request is a horizontal slice.
The run stops, asks for the value and the persona, and only then writes a
vertical slice — with the technical constraints kept as notes, never as a
technical story.

**The request.**

```text
The newsletter library must follow the provider/adapter pattern, with no
vendor logic in its core: a NewsletterProvider interface every adapter
implements, a NewsletterService that injects the provider. Write a concrete
adapter (Mailchimp). API key and list id come from the environment.
```

**Step 4 — the questions, one per turn.** Nothing in the request says who
gets what from it, and `product.md` has two personas. First question, header
`Value`: "What does a user get from this library?" with the options "Sign up
to the newsletter from the site", "Receive transactional emails", and room for
another answer. The developer: "there's a homepage section to sign up". Second
question, header `Persona`: "Who signs up?" — "Visitor (signed in or not)",
"Signed-in customer only". The developer: "anyone".

**The draft.**

```markdown
---
id: US-01
title: Sign up to the newsletter from the homepage
type: US
products: [site]
---

**User Story**
As a visitor, I want to sign up to the newsletter from the homepage, so that I hear about new offers without having to look for them.

**Outcome**
Any visitor, signed in or not, can leave their email in the homepage section and is added to the newsletter audience.

**Acceptance Criteria**
**Scenarios**

**Scenario:** signing up
**Given** a visitor on the homepage
**When** they sign up with a valid email
**Then** they are told the sign-up succeeded

**Scenario:** an invalid email
**Given** a visitor on the homepage
**When** they sign up with an email that is not valid
**Then** they are told the email is not valid
**And** nothing is sent

**Scenario:** sign-up in progress
**Given** a visitor who submitted their email
**When** the sign-up is still running
**Then** they see that it is in progress and cannot submit it twice

**Scenario:** sign-up fails
**Given** a visitor who submitted their email
**When** the sign-up fails
**Then** they are told it failed and can try again

**Additional Notes**
- The integration follows a provider/adapter design: no vendor logic in the core, one adapter per provider, Mailchimp first
- The provider's credentials come from the environment
```

The architecture survives — as constraints on how the story is built, which
is where `sdd` will read them.

## Example 3 — seven scenarios, kept whole

**What it teaches:** the atomicity exception. Seven scenarios, and no split,
because every cut tried produces a piece that does not run. The technical
specifications the developer gave stay, as observable behaviour in the
scenarios and as constraints in the notes.

**The request.** Refine the "Notify me" story on product pages that are sold
out or coming soon: integrate with Mailchimp (audience "Newsletter"); do not
create a new record for an existing email, add a product tag instead; send
the product id, title, image URL, short description, destination, status and
URL as merge tags; the price as a plain number; a mandatory privacy checkbox;
on success, a thank-you message replaces the form.

**The judgement.** Workflow Steps (the form, then the sync) and Business Rule
Variations (deduplication apart) were both tried: a form that does not send,
or a send that does not record the interest, is a piece of engine. The story
stays whole, and the approval says so in one sentence.

```markdown
---
id: US-01
title: Notify me when an unavailable product comes back
type: US
products: [shop]
---

**User Story**
As an interested visitor, I want to sign up for updates on a product that is not available, so that I am contacted with a tailored offer when it can be booked.

**Outcome**
A visitor on a sold-out or coming-soon product page becomes a profiled lead in the marketing audience.

**Acceptance Criteria**
**Scenarios**

**Scenario:** the sign-up box appears only when the product is unavailable
**Given** a visitor on a product page
**When** the product is sold out or coming soon
**Then** they see the box to sign up for updates, with name, email and privacy consent

**Scenario:** privacy consent is required
**Given** a visitor who filled in the box
**When** they submit it without accepting the privacy policy
**Then** the submission is refused and they are told why

**Scenario:** submission in progress
**Given** a visitor with valid data
**When** they submit the box
**Then** they see it is in progress and cannot edit the fields

**Scenario:** the product reaches the marketing audience
**Given** a submission in progress
**When** the interest is recorded
**Then** the marketing audience holds the email with the product's tag and its id, title, image, short description, destination, status and page link

**Scenario:** the price is a plain number
**Given** a recorded interest
**When** the marketing team reads its price
**Then** the price is a number with no currency symbol

**Scenario:** an email already in the audience
**Given** an email already in the marketing audience
**When** it signs up for another product
**Then** the existing contact gains the new product's tag and keeps the previous ones

**Scenario:** success
**Given** a submission
**When** the sign-up is confirmed
**Then** the box is replaced by a thank-you message

**Additional Notes**
- Provider: Mailchimp, audience "Newsletter"; the product data travels as merge tags
- Check the merge-tag mapping on the Mailchimp side before development
```
