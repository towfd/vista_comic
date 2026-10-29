import { describe, expect, it } from 'vitest'
import { namesInLine, type NameEntry } from './names'

const table: NameEntry[] = [
  { source: 'Kang Ji Won', aliases: ['강지원', 'Ji Won'], target: '姜智媛' },
  { source: 'Park Min Hwan', aliases: [], target: '朴敏煥' },
  { source: 'An', aliases: [], target: '安' },
]

describe('namesInLine', () => {
  it('keeps only the names that appear in the line', () => {
    expect(namesInLine(table, 'Park Min Hwan, anh đi đâu vậy?')).toEqual([{ source: 'Park Min Hwan', target: '朴敏煥' }])
  })

  it('matches an alias, sending the name it belongs to', () => {
    expect(namesInLine(table, 'JI WON À, EM ỔN CHỨ?')).toEqual([{ source: 'Kang Ji Won', target: '姜智媛' }])
  })

  it('ignores case', () => {
    expect(namesInLine(table, 'PARK MIN HWAN!')).toHaveLength(1)
  })

  it('does not match a name inside a longer word', () => {
    expect(namesInLine(table, 'Anh ơi, Annie đâu?')).toEqual([])
    expect(namesInLine(table, 'An ơi!')).toEqual([{ source: 'An', target: '安' }])
  })

  it('is empty for a line with no names or an empty table', () => {
    expect(namesInLine(table, 'Cảm ơn.')).toEqual([])
    expect(namesInLine([], 'Park Min Hwan')).toEqual([])
  })
})
