//! Measurement: per-area flow counters, the density grid, and the crowd-risk classification.
//!
//! Risk is a gameplay approximation inspired by Fruin's levels of service and by the "crowd
//! pressure" indicator (density x velocity variance, Helbing et al. 2007). It is NOT a validated
//! crowd-crush predictor; docs/research.md lists the thresholds and their sources.

use crate::math::{Rect, Vec2};

/// Comfortable / crowded / heavily congested / potentially dangerous.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
#[repr(u8)]
pub enum Level {
    Comfortable = 0,
    Crowded = 1,
    Heavy = 2,
    Danger = 3,
}

/// Fruin walkway LOS E begins around 1.1 p/m².
pub const CROWDED_DENSITY: f32 = 1.0;
/// Still: 2 p/m² is the usual event safety assessment level.
pub const HEAVY_DENSITY: f32 = 2.0;
/// Still: ~4 p/m² upper limit for moving queues, 5 for standing areas; we use 4.5.
pub const DANGER_DENSITY: f32 = 4.5;
/// Helbing et al. 2007: crowd turbulence when density * velocity variance exceeds 0.02 1/s².
pub const DANGER_PRESSURE: f32 = 0.02;
pub const PRESSURE_MIN_DENSITY: f32 = 3.0;
/// Smoothing time constant for densities (s).
pub const SMOOTH_TAU: f32 = 1.5;
/// Cells needed before an area counts as heavily congested / dangerous (avoids single-cell noise).
pub const AREA_HEAVY_CELLS: u32 = 3;
pub const AREA_DANGER_CELLS: u32 = 2;

/// Per-second counter ring for "per minute" rates.
#[derive(Clone)]
pub struct RateRing {
    buckets: [u32; 60],
    cur: usize,
    acc: u32,
}

impl Default for RateRing {
    fn default() -> Self {
        RateRing {
            buckets: [0; 60],
            cur: 0,
            acc: 0,
        }
    }
}

impl RateRing {
    pub fn add(&mut self, n: u32) {
        self.acc += n;
    }
    /// Close the current second.
    pub fn roll(&mut self) {
        self.buckets[self.cur] = self.acc;
        self.acc = 0;
        self.cur = (self.cur + 1) % 60;
    }
    /// Events in the last 60 closed seconds.
    pub fn per_minute(&self) -> u32 {
        self.buckets.iter().sum()
    }
}

pub struct AreaStats {
    pub rect: Rect,
    pub walk_area: f32,
    pub speed_factor: f32,
    pub occupancy: u32,
    pub speed_sum: f32,
    /// Smoothed density (p/m²) over the whole area.
    pub density: f32,
    pub mean_speed: f32,
    pub inflow: RateRing,
    pub outflow: RateRing,
    pub level: Level,
    pub heavy_cells: u32,
    pub danger_cells: u32,
    pub heavy_seconds: f32,
    pub danger_seconds: f32,
    pub peak_density: f32,
    /// Person-seconds spent waiting/slowed inside the area.
    pub wait_person_seconds: f32,
}

pub struct DensityGrid {
    pub cell: f32,
    pub cols: usize,
    pub rows: usize,
    pub walk_area: Vec<f32>,
    pub count: Vec<u16>,
    pub vsum: Vec<Vec2>,
    pub v2sum: Vec<f32>,
    /// Smoothed density (p/m²) and pressure.
    pub density: Vec<f32>,
    pub pressure: Vec<f32>,
    pub level: Vec<Level>,
    /// Smoothed mean velocity per cell (for flow arrows).
    pub flow: Vec<Vec2>,
    /// Area each cell belongs to (centre test), u8::MAX = none.
    pub area_of: Vec<u8>,
}

impl DensityGrid {
    pub fn new(
        cell: f32,
        cols: usize,
        rows: usize,
        walk_area: Vec<f32>,
        areas: &[Rect],
    ) -> DensityGrid {
        let n = cols * rows;
        let mut area_of = vec![u8::MAX; n];
        for y in 0..rows {
            for x in 0..cols {
                let c = Vec2::new((x as f32 + 0.5) * cell, (y as f32 + 0.5) * cell);
                for (ai, r) in areas.iter().enumerate() {
                    if r.contains(c) {
                        area_of[y * cols + x] = ai as u8;
                        break;
                    }
                }
            }
        }
        DensityGrid {
            cell,
            cols,
            rows,
            walk_area,
            count: vec![0; n],
            vsum: vec![Vec2::ZERO; n],
            v2sum: vec![0.0; n],
            density: vec![0.0; n],
            pressure: vec![0.0; n],
            level: vec![Level::Comfortable; n],
            flow: vec![Vec2::ZERO; n],
            area_of,
        }
    }

    #[inline]
    pub fn index(&self, p: Vec2) -> usize {
        let x = ((p.x / self.cell).max(0.0) as usize).min(self.cols - 1);
        let y = ((p.y / self.cell).max(0.0) as usize).min(self.rows - 1);
        y * self.cols + x
    }

    /// Accumulate this tick's agents and update smoothed values and levels.
    pub fn update(&mut self, pos: &[Vec2], vel: &[Vec2], dt: f32) {
        for c in self.count.iter_mut() {
            *c = 0;
        }
        for v in self.vsum.iter_mut() {
            *v = Vec2::ZERO;
        }
        for v in self.v2sum.iter_mut() {
            *v = 0.0;
        }
        for (p, v) in pos.iter().zip(vel) {
            let i = self.index(*p);
            self.count[i] = self.count[i].saturating_add(1);
            self.vsum[i] += *v;
            self.v2sum[i] += v.len_sq();
        }
        let k = (dt / SMOOTH_TAU).min(1.0);
        for i in 0..self.count.len() {
            let area = self.walk_area[i].max(1.0);
            let n = self.count[i] as f32;
            let rho = n / area;
            self.density[i] += (rho - self.density[i]) * k;
            let (mean, var) = if n > 0.0 {
                let m = self.vsum[i] * (1.0 / n);
                (m, (self.v2sum[i] / n - m.len_sq()).max(0.0))
            } else {
                (Vec2::ZERO, 0.0)
            };
            self.pressure[i] += (rho * var - self.pressure[i]) * k;
            self.flow[i] = self.flow[i] + (mean - self.flow[i]) * k;
            let d = self.density[i];
            self.level[i] = if d >= DANGER_DENSITY
                || (d >= PRESSURE_MIN_DENSITY && self.pressure[i] >= DANGER_PRESSURE)
            {
                Level::Danger
            } else if d >= HEAVY_DENSITY {
                Level::Heavy
            } else if d >= CROWDED_DENSITY {
                Level::Crowded
            } else {
                Level::Comfortable
            };
        }
    }

    pub fn peak(&self) -> f32 {
        self.density.iter().cloned().fold(0.0, f32::max)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn density_converges_and_classifies() {
        let mut g = DensityGrid::new(2.0, 2, 1, vec![4.0, 4.0], &[]);
        // 20 people standing still in a 4 m² cell = 5 p/m² => dangerous once smoothed
        let pos: Vec<Vec2> = (0..20)
            .map(|i| Vec2::new(0.1 + (i % 5) as f32 * 0.36, 0.1 + (i / 5) as f32 * 0.45))
            .collect();
        let vel = vec![Vec2::ZERO; 20];
        for _ in 0..200 {
            g.update(&pos, &vel, 0.05);
        }
        assert!((g.density[0] - 5.0).abs() < 0.05);
        assert_eq!(g.level[0], Level::Danger);
        assert_eq!(g.level[1], Level::Comfortable);
    }

    #[test]
    fn rate_ring_counts_last_minute() {
        let mut r = RateRing::default();
        for s in 0..120 {
            r.add(if s < 60 { 1 } else { 2 });
            r.roll();
        }
        assert_eq!(r.per_minute(), 120);
    }
}
