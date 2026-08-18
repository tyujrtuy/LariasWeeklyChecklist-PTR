# Larias' Weekly Checklist

## [v2.1.60](https://github.com/Devbezos/Larias-Weekly-Checklist/tree/v2.1.60) (2026-08-17)
[Full Changelog](https://github.com/Devbezos/Larias-Weekly-Checklist/compare/v2.1.59...v2.1.60) 

- Release v2.1.60  
- Merge branch 'main' of github.com:Devbezos/Larias-Weekly-Checklist  
- Update README.md  
- Pinned week keeps change-week affordance even once complete (#43)  
    GetPickerSectionId only honored an explicit startAtSectionId pin while  
    that week was still incomplete, so navigating back to a finished week  
    via the picker left the change-week affordance on the (unrelated) real  
    current week instead of following you there.  
    It now just defers to GetCurrentSectionId, whose own stored-start  
    check already returns the pin unconditionally -- matching what  
    HandlePick already does when it sets the pin. Also updates the picker  
    population comment in Header.lua that described the old restriction.  
- Fix/change week not advancing after completion (#42)  
    Auto-advance the checklist to the next incomplete week when the current week is fully checked, moving the change-week header along with it while keeping finished weeks reachable and expandable via change-week; also fixes the crest trade-up tooltip showing without the unlock achievement, the header tooltip only covering the expand button instead of the whole header, Hide Finished Tasks blanking out fully-completed weeks, restores checklist data wiped by a bad Google Sheets fetch, and hardens the release workflow to fail instead of publishing bad data when that fetch errors.  
- Post-release: bump version to 2.1.60  
