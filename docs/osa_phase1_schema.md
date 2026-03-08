# OSA Phase 1 Data Model

## 1) Violation case workflow

Collection: `violation_cases/{caseId}`

Core workflow fields:
- `status`: `Submitted | Under Review | Action Set | Resolved`
- `workflowStep`: `review | monitoring | resolved`
- `workflowAction`: `no_meeting | meeting_required | null`

Original reported snapshot (teacher input):
- `reportedConcern`
- `reportedCategoryId`
- `reportedCategoryNameSnapshot`
- `reportedTypeId`
- `reportedTypeNameSnapshot`
- `reportedDescription`

Current editable values (OSA can correct):
- `concern`
- `categoryId`
- `categoryNameSnapshot`
- `typeId`
- `typeNameSnapshot`
- `description`

Correction metadata:
- `wasCorrectedByOsa` (bool)
- `correction.wasCorrected` (bool)
- `correction.count` (number)
- `correction.latestByUid` (string | null)
- `correction.latestAt` (timestamp | null)
- `correction.latestReason` (string | null)

Assessment / meeting fields:
- `finalSeverity`
- `actionSelected`
- `meetingRequired`
- `meetingStatus` (`pending | scheduled | completed | missed`)
- `meetingWindow`
- `meetingDueBy`
- `scheduledAt`
- `meetingLocation`
- `officialRemarks`
- `internalNotes`

### Correction history
Subcollection: `violation_cases/{caseId}/correction_history/{historyId}`

Fields:
- `caseId`
- `from` (map of old violation fields)
- `to` (map of corrected violation fields)
- `reason`
- `correctedByUid`
- `createdAt`

## 2) OSA meeting schedule

Collection: `osa_schedule_templates/{schoolYearId::termId}`

Fields:
- `schoolYearId`
- `termId`
- `slotMinutes` (default `60`)
- `timezone` (default `Asia/Manila`)
- `weeklyWindows` (map)
  - example:
    - `mon: [{start: "08:00", end: "12:00"}, {start: "13:00", end: "17:00"}]`
- `blockedDates` (list of `YYYY-MM-DD`)
- `createdAt`, `updatedAt`

Collection: `osa_meeting_slots/{slotId}`

Fields:
- `slotId`
- `schoolYearId`
- `termId`
- `dateKey` (`YYYY-MM-DD`)
- `weekday` (`mon..sun`)
- `startAt`
- `endAt`
- `durationMinutes` (60)
- `status` (`open | booked | completed | missed | cancelled`)
- `caseId` (nullable)
- `studentUid` (nullable)
- `bookedByUid` (nullable)
- `bookedAt` (nullable)
- `createdAt`, `updatedAt`

## 3) Required indexes

Create these Firestore composite indexes:

1. `notification_queue` (collection group)
   - `toType` Asc
   - `toUid` Asc
   - `createdAt` Desc

2. `violation_cases`
   - `status` Asc
   - `createdAt` Desc

3. `osa_meeting_slots`
   - `schoolYearId` Asc
   - `termId` Asc
   - `status` Asc
   - `startAt` Asc

4. `osa_meeting_slots`
   - `caseId` Asc
   - `status` Asc
   - `startAt` Desc

