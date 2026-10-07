// merge-request.ts — "a merge request was just opened", decided the way
// hooks/scripts/post-merge-request.sh decides it.
//
// The bash hook is the authority: it is what puts the closure in front of the
// model. This is the developer's copy of the same signal, so it has to agree
// with the hook on every case — same scan, same proof, same task choice. The
// hook's sed and grep work a line at a time, so every pattern here stops at a
// newline too. Change one, change both.

/** The command with every quoted string emptied, line by line: a PR body that
 * explains how to run `gh pr create` must not read as one. */
function stripQuoted(command: string): string {
  return command.replace(/'[^'\n]*'/g, "''").replace(/"[^"\n]*"/g, '""')
}

const CREATE =
  /(^|[;&|])[ \t]*(env[ \t]+[^;&|\n]*)?([A-Za-z_][A-Za-z0-9_]*=[^ \t\n]*[ \t]+)*(gh[ \t]+pr|glab[ \t]+mr)([ \t]+-[^ \t\n]+)*[ \t]+create([ \t]|$)/m

export function isMergeRequestCreate(command: string): boolean {
  return CREATE.test(stripQuoted(command))
}

/** The URL the command printed — the proof that it created something. */
export function mergeRequestUrl(output: string): string | null {
  const match = /https:\/\/[^\s"'\\]+\/(pull|merge_requests)\/[0-9]+/.exec(output)
  return match ? match[0] : null
}

/** A Bash tool result as text, whatever shape the client returns it in —
 * the `tool.call` envelope (`{ result }`) included. */
export function toolOutputText(result: unknown): string {
  if (typeof result === 'string') return result
  if (result && typeof result === 'object') {
    if ('result' in result) return toolOutputText((result as { result?: unknown }).result)
    const { stdout, stderr } = result as { stdout?: unknown; stderr?: unknown }
    if (typeof stdout === 'string' || typeof stderr === 'string') {
      return [stdout, stderr].filter((part) => typeof part === 'string').join('\n')
    }
    return JSON.stringify(result)
  }
  return ''
}

function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&')
}

/**
 * Which open task the merge request closes: the one the branch or the command
 * names, matched between delimiters (DE-81 must not match DE-811); else the
 * only open one; else none — several open and none named means the developer
 * picks, never a guess.
 */
export function closureTask(openTasks: readonly string[], branch: string, command: string): string | null {
  const haystack = `${branch} ${command}`
  for (const task of openTasks) {
    if (new RegExp(`(^|[^A-Za-z0-9])${escapeRegExp(task)}([^A-Za-z0-9]|$)`).test(haystack)) return task
  }
  return openTasks.length === 1 ? openTasks[0] : null
}

/** The prompt the closure button fills — the two calls the hook asks for,
 * citing the contract that owns them rather than restating it. */
export function closurePrompt(task: string, url: string, pluginRoot: string): string {
  return (
    `The merge request ${url} is open and ${task} is still IN PROGRESS. Close it as the ` +
    `work clock section of ${pluginRoot}/reference/clickup-contract.md says: ` +
    `bash "${pluginRoot}/scripts/task-clock.sh" --task ${task} --stop --json, then move ${task} ` +
    `to CODE REVIEW (IN REVIEW where the list has none) with COMMENT as the comment, verbatim. ` +
    `Never write a duration yourself.`
  )
}
