import { describe, expect, it } from 'vitest'
import { formatLearningSteps, parseLearningSteps, parseNewCardsPerDay } from './settings'

describe('parseLearningSteps', () => {
  it('reads a list separated by commas, spaces, or both', () => {
    expect(parseLearningSteps('5, 7, 10')).toEqual([5, 7, 10])
    expect(parseLearningSteps('5 7 10')).toEqual([5, 7, 10])
    expect(parseLearningSteps(' 5,7 ,  10 ')).toEqual([5, 7, 10])
    expect(parseLearningSteps('5，7')).toEqual([5, 7])
  })

  it('reads a single step', () => {
    expect(parseLearningSteps('10')).toEqual([10])
  })

  it('refuses an empty list', () => {
    expect(parseLearningSteps('')).toBeNull()
    expect(parseLearningSteps(' , ')).toBeNull()
  })

  it('refuses a step of zero or below', () => {
    expect(parseLearningSteps('5, 0, 10')).toBeNull()
    expect(parseLearningSteps('-5')).toBeNull()
  })

  it('refuses anything that is not a whole number, rather than keeping the rest', () => {
    expect(parseLearningSteps('5, x, 10')).toBeNull()
    expect(parseLearningSteps('5.5')).toBeNull()
    expect(parseLearningSteps('5m')).toBeNull()
    expect(parseLearningSteps('1e3')).toBeNull()
  })
})

describe('formatLearningSteps', () => {
  it('writes a list the way it is read', () => {
    expect(formatLearningSteps([5, 7, 10])).toBe('5, 7, 10')
    expect(parseLearningSteps(formatLearningSteps([1, 20]))).toEqual([1, 20])
  })
})

describe('parseNewCardsPerDay', () => {
  it('reads a whole number, zero included', () => {
    expect(parseNewCardsPerDay('15')).toBe(15)
    expect(parseNewCardsPerDay(' 0 ')).toBe(0)
  })

  it('refuses a negative, a fraction, text and nothing', () => {
    expect(parseNewCardsPerDay('-1')).toBeNull()
    expect(parseNewCardsPerDay('1.5')).toBeNull()
    expect(parseNewCardsPerDay('many')).toBeNull()
    expect(parseNewCardsPerDay('')).toBeNull()
  })
})
