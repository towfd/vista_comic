// A chapter's OCR segments merged with their translation, read from /ocr-data:
// the comic-ocr-data folder, served by the dev server (vite.config.ts) or nginx
// (nginx.conf.template). Keyed by the library folder name and episode number.

/** One tappable box on one page, positioned in percent of that page. */
export interface OverlayRegion {
  segmentId: string
  kind: string
  /** Original text as OCR read it. */
  source: string
  /** Translation, or null when this chapter has none for the segment. */
  text: string | null
  left: number
  top: number
  width: number
  height: number
}

interface OcrFile {
  pages: { file: string; width: number; height: number }[]
  segments: { id: string; text: string; kind: string; regions: { page: string; bbox: [number, number, number, number] }[] }[]
}

interface TranslationFile {
  segments: { id: string; source: string; text: string }[]
}

async function fetchJson<T>(url: string): Promise<T | null> {
  try {
    const response = await fetch(url)
    return response.ok ? ((await response.json()) as T) : null
  } catch {
    return null
  }
}

/**
 * Regions for each page, keyed by the 1-based page index the reader uses.
 * OCR pages are matched by position, the same order the backend serves them in.
 * Empty when the chapter has no OCR data.
 */
export async function loadOverlay(comicId: string, episode: number, lang = 'zh-TW'): Promise<Map<number, OverlayRegion[]>> {
  const base = `/ocr-data/${encodeURIComponent(comicId)}/${episode}`
  const [ocr, translation] = await Promise.all([
    fetchJson<OcrFile>(`${base}.ocr.json`),
    fetchJson<TranslationFile>(`${base}.${lang}.json`),
  ])
  const byPage = new Map<number, OverlayRegion[]>()
  if (!ocr) return byPage

  const translated = new Map(translation?.segments.map((s) => [s.id, s.text]) ?? [])
  const pageIndex = new Map(ocr.pages.map((p, i) => [p.file, { index: i + 1, ...p }]))

  for (const segment of ocr.segments) {
    for (const region of segment.regions) {
      const page = pageIndex.get(region.page)
      if (!page) continue
      const [x1, y1, x2, y2] = region.bbox
      const list = byPage.get(page.index) ?? []
      list.push({
        segmentId: segment.id,
        kind: segment.kind,
        source: segment.text,
        text: translated.get(segment.id) ?? null,
        left: (x1 / page.width) * 100,
        top: (y1 / page.height) * 100,
        width: ((x2 - x1) / page.width) * 100,
        height: ((y2 - y1) / page.height) * 100,
      })
      byPage.set(page.index, list)
    }
  }
  return byPage
}
