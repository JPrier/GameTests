//! Uniform-grid neighbour index (counting sort into CSR arrays).
//!
//! Rebuilt every tick in O(n) with no allocation after warm-up: `counts`, `start` and `items` are
//! reused. Cell size equals the interaction radius, so a 3x3 cell query covers every neighbour that
//! can affect an agent.

use crate::math::Vec2;

pub struct SpatialGrid {
    pub cell: f32,
    pub cols: usize,
    pub rows: usize,
    start: Vec<u32>,
    items: Vec<u32>,
    cell_of: Vec<u32>,
    cursor: Vec<u32>,
}

impl SpatialGrid {
    pub fn new(size: [f32; 2], cell: f32) -> SpatialGrid {
        let cols = (size[0] / cell).ceil() as usize + 1;
        let rows = (size[1] / cell).ceil() as usize + 1;
        SpatialGrid {
            cell,
            cols,
            rows,
            start: vec![0; cols * rows + 1],
            items: Vec::new(),
            cell_of: Vec::new(),
            cursor: Vec::new(),
        }
    }

    #[inline]
    fn cell_index(&self, p: Vec2) -> usize {
        let cx = ((p.x / self.cell).max(0.0) as usize).min(self.cols - 1);
        let cy = ((p.y / self.cell).max(0.0) as usize).min(self.rows - 1);
        cy * self.cols + cx
    }

    pub fn rebuild(&mut self, pos: &[Vec2]) {
        let n = pos.len();
        let mut cell_of = std::mem::take(&mut self.cell_of);
        cell_of.clear();
        cell_of.extend(pos.iter().map(|p| self.cell_index(*p) as u32));
        self.cell_of = cell_of;
        for s in self.start.iter_mut() {
            *s = 0;
        }
        for &c in &self.cell_of {
            self.start[c as usize + 1] += 1;
        }
        for i in 1..self.start.len() {
            self.start[i] += self.start[i - 1];
        }
        self.items.clear();
        self.items.resize(n, 0);
        // fill using a running cursor per cell; iterate agents in index order (stable => deterministic)
        self.cursor.clear();
        self.cursor
            .extend_from_slice(&self.start[..self.start.len() - 1]);
        for (i, &c) in self.cell_of.iter().enumerate() {
            let k = &mut self.cursor[c as usize];
            self.items[*k as usize] = i as u32;
            *k += 1;
        }
    }

    /// Calls `f(j)` for every agent in the 3x3 cells around `p` (including the agent itself).
    #[inline]
    pub fn for_each_near(&self, p: Vec2, mut f: impl FnMut(usize)) {
        let cx = ((p.x / self.cell).max(0.0) as isize).min(self.cols as isize - 1);
        let cy = ((p.y / self.cell).max(0.0) as isize).min(self.rows as isize - 1);
        for y in (cy - 1).max(0)..=(cy + 1).min(self.rows as isize - 1) {
            let row = y as usize * self.cols;
            let x0 = (cx - 1).max(0) as usize;
            let x1 = (cx + 1).min(self.cols as isize - 1) as usize;
            let a = self.start[row + x0] as usize;
            let b = self.start[row + x1 + 1] as usize;
            for &j in &self.items[a..b] {
                f(j as usize);
            }
        }
    }

    /// Number of agents within `r` of `p` (r <= cell).
    pub fn count_within(&self, pos: &[Vec2], p: Vec2, r: f32) -> usize {
        let mut n = 0;
        let r2 = r * r;
        self.for_each_near(p, |j| {
            if (pos[j] - p).len_sq() < r2 {
                n += 1;
            }
        });
        n
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_exactly_the_brute_force_neighbours() {
        let mut rng = crate::rng::Rng::new(3);
        let pos: Vec<Vec2> = (0..2000)
            .map(|_| Vec2::new(rng.range(0.0, 50.0), rng.range(0.0, 30.0)))
            .collect();
        let mut g = SpatialGrid::new([50.0, 30.0], 2.0);
        g.rebuild(&pos);
        for i in (0..pos.len()).step_by(37) {
            let mut fast: Vec<usize> = Vec::new();
            g.for_each_near(pos[i], |j| {
                if (pos[j] - pos[i]).len() < 2.0 {
                    fast.push(j)
                }
            });
            fast.sort();
            let brute: Vec<usize> = (0..pos.len())
                .filter(|&j| (pos[j] - pos[i]).len() < 2.0)
                .collect();
            assert_eq!(fast, brute);
        }
    }
}
