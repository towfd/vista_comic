// A work's name table, read from /ocr-data/<folder>/bible.json beside the OCR
// files (see overlay.ts), and the part of it a line needs: a line analysis
// sends Claude only the names that appear in the line it explains.

/** One name: how it is written in the Vietnamese lines, and its official name. */
export interface NameEntry {
  source: string
  aliases: string[]
  target: string
}

interface BibleFile {
  names?: { source_name?: string; aliases?: string[]; fixed_names?: Record<string, string> }[]
}

/** The work's names with an official name in `lang`; empty when there is no table. */
export async function loadNameTable(folder: string, lang = 'zh-TW'): Promise<NameEntry[]> {
  let bible: BibleFile
  try {
    const response = await fetch(`/ocr-data/${encodeURIComponent(folder)}/bible.json`)
    if (!response.ok) return []
    bible = (await response.json()) as BibleFile
  } catch {
    return []
  }
  const entries: NameEntry[] = []
  for (const name of bible.names ?? []) {
    const target = name.fixed_names?.[lang]
    if (!name.source_name || !target) continue
    entries.push({ source: name.source_name, aliases: name.aliases ?? [], target })
  }
  return entries
}

const escape = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

/** Whether `name` stands in `line` as a whole word, ignoring case: `An` is not in `Anh`. */
function appears(name: string, line: string): boolean {
  if (!name.trim()) return false
  return new RegExp(`(?<![\\p{L}\\p{N}])${escape(name)}(?![\\p{L}\\p{N}])`, 'iu').test(line)
}

/** The entries whose name or an alias appears in the line, as the request sends them. */
export function namesInLine(table: readonly NameEntry[], line: string): { source: string; target: string }[] {
  return table
    .filter((entry) => [entry.source, ...entry.aliases].some((name) => appears(name, line)))
    .map(({ source, target }) => ({ source, target }))
}
