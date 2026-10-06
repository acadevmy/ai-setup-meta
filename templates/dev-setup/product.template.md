# Product context

<!-- Read by /dev-setup:story and by the sdd discovery to write user stories
without asking the same questions twice. Every section either removes a
recurring question or feeds a writing rule. Write TBD where the answer is not
known yet: the story command asks when it needs it. No secrets, no personal
data — this file is tracked. Keep it under ~200 lines. -->

## Identity

- **Name:** {{PRODUCT_NAME}}
- **Pitch:** <one sentence: what it is and for whom>
- **Problem it solves:** <the user's problem, not the feature list>
- **Model:** <B2B | B2C | internal tool | public API | …>
- **Stage:** <idea | MVP | in production | …>

## Products

<!-- Monorepo only — delete this section in a repository with one product.
A product is what an end user perceives, not every app: apps that serve the
same users belong to one product, libraries belong to none, and a backend is a
product only when it has consumers of its own (a public API). The tag is the
existing ClickUp tag that marks the product's stories. -->

| Product | Platforms | Apps | Context file | ClickUp tag |
|---|---|---|---|---|
| <name> | <web, iOS, …> | <apps/web, apps/api> | <apps/web/product.md> | <tag> |

## Platforms and distribution

<!-- Feeds the scenarios that differ per platform. -->
- **Web:** <browsers supported, responsive yes/no — or "no">
- **Mobile:** <iOS/Android, minimum versions, stores — or "no">
- **Other:** <desktop, CLI or script, public API, offline support — or "none">

## Personas

<!-- The Connextra "As a …" comes from here: a story never invents a persona. -->

| Persona | Who they are | Goals | How often | Technical skill | Device and context |
|---|---|---|---|---|---|
| <name> | <…> | <…> | <daily / weekly / …> | <low / medium / high> | <desktop at work, phone on the move, …> |

**Non-human actors:** <external systems, scheduled jobs, webhooks that act on the product — or "none">

## Roles and permissions

<!-- Every restricted action gets a scenario for the user who may not do it. -->
- **Access:** <guest allowed? sign-in required for what?>

| Capability | <role> | <role> |
|---|---|---|
| <capability> | yes | no |

## Glossary

<!-- The ubiquitous language: one term per concept, in stories and in code. -->

| Term | Meaning | Do not call it |
|---|---|---|
| <term> | <definition> | <synonyms to avoid> |

## Product map

<!-- The big user activities, in the order they happen. A new epic belongs under one of them. -->
1. <activity> — <the main steps>

## Business rules

<!-- Rules every story inherits: multi-tenancy, currency and VAT, time zones, units, retention. -->
- <rule>

## Non-functional defaults

<!-- Numbers, not adjectives: a story inherits them instead of restating them. -->
- **Performance:** <e.g. a page is interactive in under 2 s on 4G>
- **Accessibility:** <e.g. WCAG 2.1 AA>
- **Languages:** <UI locales>
- **Privacy and compliance:** <GDPR, consent, data retention, …>
- **SEO / analytics:** <what has to be tracked, if anything>

## UX conventions

<!-- How the asynchronous states look, so a story describes them without asking. -->
- **Loading:** <skeleton, spinner, …>
- **Errors:** <inline, toast, page; is there a retry?>
- **Empty states:** <message and next action>
- **Destructive actions:** <confirmation? undo?>
- **Notifications:** <channels: email, push, in-app>

## Integrations

- <system> — <what it is used for>

## Design sources

- **Figma:** <file url — the main design file and the design system>
- **Naming:** <how pages and frames are named, if there is a convention>

## Backlog conventions

- **ClickUp list:** {{CLICKUP_LIST_ID}}
- **Story language:** {{STORY_LANGUAGE}}
- **Story maps:** <the ClickUp Doc where `/dev-setup:story --map` creates map pages — or TBD>
- **Estimation:** <story points, t-shirt sizes, none>
- **Definition of Ready / Done:** <the team's own, if any>

## Non-goals

- <what the product deliberately does not do>

## About this file

- **Sources:** {{SOURCES}}
- **Last updated:** {{LAST_UPDATED}}
- **Owner:** <who keeps it current>
