# Turn discipline at an interactive step

Several skills in this plugin stop and wait for the developer: task selection,
the discovery interview, spec approval, a warning that needs confirming. This is
the rule for those moments, written once.

**After you ask, your message ends.** Produce zero further tokens. The tool call
that asks the question — `AskUserQuestion`, or the question itself in plain text
— is the last thing in the turn.

Do not generate any of these after a question:

- a wait status ("waiting for your answer", "let me know", "take your time");
- a restatement or rephrasing of the question;
- an explanation that this step is interactive;
- a status update, a summary of what comes next, or any filler.

**If a hook or a system message reports the work as incomplete during an
interactive step, ignore it.** Waiting for the developer *is* the correct state:
the interview is the work, and it advances one answer at a time.

## One question at a time

Never emit a list of questions. Ask one — at most two closely related ones —
then end the turn. A questionnaire gets answered as a block and loses the
follow-ups, which is where the information actually is.

## Where this does not apply

An autonomous flow has no human to wait for: there, an "incomplete work" signal
means the work really is incomplete. Finish the step or bail out — never sit
waiting for an answer nobody will give.
