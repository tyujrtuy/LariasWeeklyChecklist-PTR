# Larias' Weekly Checklist

## [v2.1.63](https://github.com/Devbezos/Larias-Weekly-Checklist/tree/v2.1.63) (2026-08-20)
[Full Changelog](https://github.com/Devbezos/Larias-Weekly-Checklist/compare/v2.1.62...v2.1.63) 

- Feature/20260820 (#44)  
    Alt Summary gets a new Stats section with two rows: Keys This Week and Keys This Season, each showing completed Mythic+ run counts with a tooltip. Both pull from C\_MythicPlus.GetRunHistory(true, false, true) — completed runs only, current season only — so aborted/failed keys don't inflate the counts.  
    Crest, catalyst, sparks, coffer-key, and misc currency cells now share one ColorForXY/ColorForXYRGB progress rule (green at cap, yellow from 50%, red below) instead of several near-duplicate inline calculations. Crest cells now color by crests earned this week against the weekly cap rather than total wallet balance, so a bank carried over from a prior week no longer misreads as "done."  
    Adds the matching enUS + all-locale translations for the new UI strings.  
- Post-release: bump version to 2.1.63  
