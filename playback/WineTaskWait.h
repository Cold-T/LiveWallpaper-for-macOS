#pragma once
#import <Foundation/Foundation.h>
#include <signal.h>
#include <time.h>

static NSTimeInterval LWWineMonotonicTime(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return now.tv_sec + now.tv_nsec / 1e9;
}

// Wait only for this application's NSTask, never for every Wine process.
// A late Wine server startup must not turn registry-flush waiting into an
// unbounded wait on the UI thread. Kill only the owned waiter on timeout.
static BOOL LWWaitForWineTask(NSTask *task, NSTimeInterval timeout) {
  if (!task || !task.running) return YES;
  NSTimeInterval deadline = LWWineMonotonicTime() + MAX(0, timeout);
  while (task.running && LWWineMonotonicTime() < deadline)
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
  if (!task.running) return YES;
  @try { [task terminate]; } @catch (NSException *exception) {}
  NSTimeInterval grace = LWWineMonotonicTime() + .15;
  while (task.running && LWWineMonotonicTime() < grace)
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
  if (task.running && task.processIdentifier > 0) kill(task.processIdentifier, SIGKILL);
  return NO;
}
static void LWCancelWineTask(NSTask *task) {
  if (!task.running) return;
  @try { [task terminate]; } @catch (NSException *exception) {}
}
