export type Interval = { start: Date; end: Date };

export function generateStepSlots(day: Date, stepMin: number, workStartMin: number, workEndMin: number): Interval[] {
  const base = Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), 0, 0, 0);
  const arr: Interval[] = [];
  for (let m = workStartMin; m + stepMin <= workEndMin; m += stepMin) {
    const start = new Date(base + m * 60000);
    const end = new Date(base + (m + stepMin) * 60000);
    arr.push({ start, end });
  }
  return arr;
}

export function subtractIntervals(free: Interval[], busy: Interval[]): Interval[] {
  return free.filter(s => !busy.some(b => s.start < b.end && b.start < s.end));
}

export function glueContinuous(free: Interval[]): Interval[] {
  if (!free.length) return [];
  const out: Interval[] = [ { ...free[0] } ];
  for (let i=1;i<free.length;i++) {
    const prev = out[out.length-1];
    const curr = free[i];
    if (prev.end.getTime() === curr.start.getTime()) {
      prev.end = curr.end;
    } else {
      out.push({ ...curr });
    }
  }
  return out;
}

export function findStartsForDuration(free: Interval[], durationMin: number, stepMin: number): Date[] {
  const starts: Date[] = [];
  const durMs = durationMin * 60000;
  for (const interval of free) {
    for (let t = interval.start.getTime(); t + durMs <= interval.end.getTime(); t += stepMin * 60000) {
      starts.push(new Date(t));
    }
  }
  return starts;
}
