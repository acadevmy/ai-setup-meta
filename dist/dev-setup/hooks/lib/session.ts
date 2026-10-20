// session.ts — what this session changed in the repository, as git and the
// file system show it.
//
// The line is the session's own start (`$.session.usage().startedAt`: the
// first launch of a resumed session, the moment of a `/clear`), the same line
// Claude Code's diff panel draws. A commit belongs to the session when it was
// committed after that line; a working-tree change when its file was modified
// after it — or, for a file that is gone, when its folder was. So a change the
// branch already carried when the session began is not shown, and one made by
// a Bash command is, which a list of Edit and Write calls would miss. What the
// view cannot tell apart is another process writing the same checkout at the
// same time: an editor's save, a second session.

/** One entry of `git status --porcelain=v1 -z`: the two-letter code and the path, root-relative. */
export type StatusEntry = { readonly code: string; readonly path: string }

/** The entries of `git status --porcelain=v1 -z`: a rename or a copy carries
 * its source as the next NUL-separated field, which is skipped. */
export function parsePorcelain(output: string): StatusEntry[] {
  const fields = output.split('\0')
  const entries: StatusEntry[] = []
  for (let i = 0; i < fields.length; i++) {
    const field = fields[i] ?? ''
    if (field.length < 4) continue
    const code = field.slice(0, 2)
    entries.push({ code, path: field.slice(3) })
    if (code[0] === 'R' || code[0] === 'C') i++
  }
  return entries
}

/** What a status code means, in a word. */
export function changeLabel(code: string): string {
  const [x = ' ', y = ' '] = code
  if (code === '??') return 'new'
  if (x === 'D' || y === 'D') return 'deleted'
  if (x === 'R') return 'renamed'
  if (x === 'A') return y === ' ' ? 'added' : 'added, edited'
  if (x === 'U' || y === 'U') return 'conflict'
  if (x !== ' ' && y !== ' ') return 'partly staged'
  return x !== ' ' ? 'staged' : 'modified'
}

/** The folder a root-relative path sits in, '' for the root itself. */
export function folderOf(path: string): string {
  const cut = path.replace(/\/$/, '').lastIndexOf('/')
  return cut < 0 ? '' : path.slice(0, cut)
}

export type Commit = { readonly sha: string; readonly subject: string }

/** `git log --format=%h%x09%s`, one commit a line. */
export function parseCommits(output: string): Commit[] {
  return output
    .split(/\r?\n/)
    .filter((line) => line.trim() !== '')
    .map((line) => {
      const tab = line.indexOf('\t')
      return tab < 0 ? { sha: line.trim(), subject: '' } : { sha: line.slice(0, tab), subject: line.slice(tab + 1) }
    })
}

export type SessionChanges = {
  readonly startedAt: number
  readonly commits: readonly Commit[]
  /** Working-tree changes made in this session, in `git status` order. */
  readonly uncommitted: readonly StatusEntry[]
  /** Files the session's commits touched that are clean again. */
  readonly committed: readonly string[]
}

/**
 * The session's share of the repository's state.
 *
 * `mtimeOf` answers a root-relative path's modification time, or null when
 * nothing is there; a file that is gone is judged by its folder.
 */
export function sessionChanges(
  startedAt: number,
  entries: readonly StatusEntry[],
  mtimeOf: (path: string) => number | null,
  commits: readonly Commit[],
  committedFiles: readonly string[],
): SessionChanges {
  const touched = (path: string): boolean => {
    const own = mtimeOf(path)
    if (own !== null) return own >= startedAt
    const folder = mtimeOf(folderOf(path))
    return folder !== null && folder >= startedAt
  }
  const uncommitted = entries.filter((entry) => touched(entry.path))
  const dirty = new Set(entries.map((entry) => entry.path))
  const committed = [...new Set(committedFiles.filter((file) => file.trim() !== '' && !dirty.has(file)))]
  return { startedAt, commits, uncommitted, committed }
}

/** The root-relative paths whose time the view needs: each entry and the folder of each. */
export function pathsToStat(entries: readonly StatusEntry[]): string[] {
  return [...new Set(entries.flatMap((entry) => [entry.path, folderOf(entry.path)]))]
}
