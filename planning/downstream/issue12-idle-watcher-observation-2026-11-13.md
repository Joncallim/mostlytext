# Issue #12: idle external-file watcher observation

## Owner summary

MostlyText should notice external changes without waking repeatedly while a
document is untouched. This test observes the real macOS file watcher and
monitor after a document is bound, then makes one atomic external replacement
to prove the observation counter can see actual work. It changes no production
watcher, polling policy, file authority or document content.

## Baseline and decision

- Baseline: `main` `56ed861213c8b6d0d0695eb45c0b36523c6ef274`.
- `LiveDocumentDirectoryWatcher` uses a file-system dispatch source, not a
  periodic timer. `DocumentFileMonitor` schedules its 150 ms debounce only
  after a watcher signal; parent recovery has a bounded four-attempt retry.
- Existing real-watcher tests prove changes and deletion arrive, and #12 has
  measured live 1 MB/10 MB reconciliation. They do not explicitly observe a
  quiet bound interval.

## Narrow execution contract

Wrap the real watcher and real file probe with counters. A fresh file gets
exactly one initial observation. For four seconds without a file mutation,
require no new watcher signal, disk probe, debounce sleep or observation.
Then atomically replace the file and require all three counters to increase
and the new text to arrive. The positive control prevents an inert wrapper
from making the quiet interval look successful.

The counters use a lock because dispatch-source callbacks are outside the
monitor actor. The test does not read user data, launch the app, alter package
dependencies or infer whole-app energy use from one fixture. A passing run
supports the event-driven idle path; it does not by itself finish #12's exact
Release candidate, full manual matrix, selection/scroll/session or final
release-evidence rows. A separate process-level wakeup comparison would be
needed before claiming an energy or CPU ceiling.
