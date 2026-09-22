## Merge this first

<!-- Please delete the lines that do not apply. -->

- [ ]({{MR_LINK_BASE}}/{id})

## Description

<!--
Summarise the change and say which problem it solves, naming the task id.
Include the motivation and any context a reviewer needs.
-->
...

**Issue:** [DE-00000](https://app.clickup.com/t/2428116/DE-00000)

## Screenshots

<!-- Include every image needed to understand the merge request. -->

## Type of change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would stop existing functionality working as expected)
- [ ] Docs (documentation fix or addition)

## How was it tested?

<!--
Write the steps to verify the change by hand: a reviewer must be able to repeat
them without asking anything. Terminal commands first, then the walk through the
application with the exact routes.
-->

**From the terminal**

```bash
# the commands, in the order they must run
# e.g. npm install && npm run dev
# e.g. npm test -- src/auth/login.spec.ts
```

**In the application**

1. Open `<route>` — e.g. `http://localhost:3000/auth/login`
2. `<what to do: what to type, what to click>`
3. Expected result: `<what must appear>`

**Cases covered**

- [ ] Test A
- [ ] Test B

## Checklist:

- [ ] I have put the task id in the title of this merge request
- [ ] I have brought my branch up to date with `{{BASE_BRANCH}}`
- [ ] I have self-reviewed my code
- [ ] My code follows the {{CODE_CONVENTIONS_LINK}}
- [ ] I have commented my code, in the hard-to-understand parts especially
- [ ] I have made the corresponding changes to the documentation
- [ ] I have formatted and sorted the code
- [ ] I have added tests proving my fix works or my feature is correct
- [ ] New and existing unit tests pass locally with my changes
