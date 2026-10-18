//! Navigation grid, wall geometry and per-node distance fields.
//!
//! Global route *choice* happens on the node graph (routing.rs); getting from where an agent stands to
//! its next node is done by following a geodesic distance field toward that node, so local paths
//! respect every wall, barrier and closed gate. One field per graph node is shared by all agents
//! heading there (a reverse shortest-path tree), so there is no per-agent path search.

use crate::math::{closest_on_segment, Rect, Vec2};
use std::cmp::Reverse;
use std::collections::BinaryHeap;

pub const INF: f32 = f32::INFINITY;

/// A wall segment with an owner, so dynamic walls (barriers, closed gates) can be removed.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Wall {
    pub a: Vec2,
    pub b: Vec2,
    pub owner: WallOwner,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WallOwner {
    /// Map boundary or a scenario wall.
    Static,
    /// Player barrier with its id.
    Barrier(u32),
    /// A gate line while the gate is closed (gate index).
    Gate(u16),
}

pub struct NavGrid {
    pub cols: usize,
    pub rows: usize,
    pub cell: f32,
    /// Walkable from the scenario geometry alone.
    base: Vec<bool>,
    /// Currently walkable (base minus dynamic walls).
    pub walkable: Vec<bool>,
    pub walls: Vec<Wall>,
    /// Wall buckets for collision queries.
    bucket_size: f32,
    bcols: usize,
    brows: usize,
    bucket_start: Vec<u32>,
    bucket_items: Vec<u32>,
}

impl NavGrid {
    pub fn new(
        size: [f32; 2],
        cell: f32,
        walkable_rects: &[[f32; 4]],
        extra_walls: &[[f32; 4]],
    ) -> NavGrid {
        let cols = (size[0] / cell).ceil() as usize;
        let rows = (size[1] / cell).ceil() as usize;
        let mut base = vec![false; cols * rows];
        for r in walkable_rects {
            let rect = Rect::from_arr(*r);
            for cy in 0..rows {
                for cx in 0..cols {
                    let c = Vec2::new((cx as f32 + 0.5) * cell, (cy as f32 + 0.5) * cell);
                    if rect.contains(c) {
                        base[cy * cols + cx] = true;
                    }
                }
            }
        }
        let mut g = NavGrid {
            cols,
            rows,
            cell,
            walkable: base.clone(),
            base,
            walls: Vec::new(),
            bucket_size: 2.0,
            bcols: 0,
            brows: 0,
            bucket_start: Vec::new(),
            bucket_items: Vec::new(),
        };
        g.walls = g.boundary_walls();
        for w in extra_walls {
            g.walls.push(Wall {
                a: Vec2::new(w[0], w[1]),
                b: Vec2::new(w[2], w[3]),
                owner: WallOwner::Static,
            });
        }
        // Static scenario walls also block the grid permanently.
        for w in extra_walls {
            let (a, b) = (Vec2::new(w[0], w[1]), Vec2::new(w[2], w[3]));
            let cells = g.cells_near_segment(a, b);
            for i in cells {
                g.base[i] = false;
            }
        }
        g.walkable = g.base.clone();
        g.rebuild_buckets();
        g
    }

    #[inline]
    pub fn idx(&self, cx: usize, cy: usize) -> usize {
        cy * self.cols + cx
    }

    #[inline]
    pub fn cell_of(&self, p: Vec2) -> Option<(usize, usize)> {
        if p.x < 0.0 || p.y < 0.0 {
            return None;
        }
        let cx = (p.x / self.cell) as usize;
        let cy = (p.y / self.cell) as usize;
        if cx < self.cols && cy < self.rows {
            Some((cx, cy))
        } else {
            None
        }
    }

    #[inline]
    pub fn center(&self, cx: usize, cy: usize) -> Vec2 {
        Vec2::new((cx as f32 + 0.5) * self.cell, (cy as f32 + 0.5) * self.cell)
    }

    pub fn is_walkable(&self, p: Vec2) -> bool {
        self.cell_of(p)
            .map(|(x, y)| self.walkable[self.idx(x, y)])
            .unwrap_or(false)
    }

    pub fn is_base_walkable(&self, p: Vec2) -> bool {
        self.cell_of(p)
            .map(|(x, y)| self.base[self.idx(x, y)])
            .unwrap_or(false)
    }

    /// Boundary segments between walkable and non-walkable cells, merged into long straight runs.
    fn boundary_walls(&self) -> Vec<Wall> {
        let mut out = Vec::new();
        let w = |cx: isize, cy: isize| -> bool {
            cx >= 0
                && cy >= 0
                && (cx as usize) < self.cols
                && (cy as usize) < self.rows
                && self.base[cy as usize * self.cols + cx as usize]
        };
        let c = self.cell;
        // horizontal edges: between row cy-1 and cy
        for cy in 0..=self.rows as isize {
            let mut run: Option<(isize, bool)> = None; // (start col, walkable side is below)
            for cx in 0..=self.cols as isize {
                let edge = if cx < self.cols as isize {
                    let above = w(cx, cy - 1);
                    let below = w(cx, cy);
                    if above != below {
                        Some(below)
                    } else {
                        None
                    }
                } else {
                    None
                };
                match (run, edge) {
                    (Some((s, side)), Some(e)) if e == side => {
                        let _ = s;
                    }
                    (Some((s, _)), _) => {
                        out.push(Wall {
                            a: Vec2::new(s as f32 * c, cy as f32 * c),
                            b: Vec2::new(cx as f32 * c, cy as f32 * c),
                            owner: WallOwner::Static,
                        });
                        run = edge.map(|e| (cx, e));
                    }
                    (None, Some(e)) => run = Some((cx, e)),
                    (None, None) => {}
                }
            }
        }
        // vertical edges: between col cx-1 and cx
        for cx in 0..=self.cols as isize {
            let mut run: Option<(isize, bool)> = None;
            for cy in 0..=self.rows as isize {
                let edge = if cy < self.rows as isize {
                    let left = w(cx - 1, cy);
                    let right = w(cx, cy);
                    if left != right {
                        Some(right)
                    } else {
                        None
                    }
                } else {
                    None
                };
                match (run, edge) {
                    (Some((_, side)), Some(e)) if e == side => {}
                    (Some((s, _)), _) => {
                        out.push(Wall {
                            a: Vec2::new(cx as f32 * c, s as f32 * c),
                            b: Vec2::new(cx as f32 * c, cy as f32 * c),
                            owner: WallOwner::Static,
                        });
                        run = edge.map(|e| (cy, e));
                    }
                    (None, Some(e)) => run = Some((cy, e)),
                    (None, None) => {}
                }
            }
        }
        out
    }

    /// Cells whose centre lies within ~0.75 cell of the segment (a closed 2-cell-wide line: no
    /// diagonal leaks for the 8-connected field search).
    pub fn cells_near_segment(&self, a: Vec2, b: Vec2) -> Vec<usize> {
        let mut out = Vec::new();
        let pad = self.cell * 0.75;
        let minx = ((a.x.min(b.x) - pad) / self.cell).floor().max(0.0) as usize;
        let maxx =
            (((a.x.max(b.x) + pad) / self.cell).ceil() as usize).min(self.cols.saturating_sub(1));
        let miny = ((a.y.min(b.y) - pad) / self.cell).floor().max(0.0) as usize;
        let maxy =
            (((a.y.max(b.y) + pad) / self.cell).ceil() as usize).min(self.rows.saturating_sub(1));
        for cy in miny..=maxy {
            for cx in minx..=maxx {
                let c = self.center(cx, cy);
                if (closest_on_segment(c, a, b) - c).len() <= pad {
                    out.push(self.idx(cx, cy));
                }
            }
        }
        out
    }

    pub fn add_wall(&mut self, a: Vec2, b: Vec2, owner: WallOwner) {
        self.walls.push(Wall { a, b, owner });
        self.refresh_walkable();
    }

    pub fn remove_walls(&mut self, owner: WallOwner) -> bool {
        let before = self.walls.len();
        self.walls.retain(|w| w.owner != owner);
        let changed = self.walls.len() != before;
        if changed {
            self.refresh_walkable();
        }
        changed
    }

    /// Walkable cells = base cells minus cells covered by dynamic walls. Rebuilds wall buckets.
    fn refresh_walkable(&mut self) {
        self.walkable.copy_from_slice(&self.base);
        let dynamic: Vec<(Vec2, Vec2)> = self
            .walls
            .iter()
            .filter(|w| w.owner != WallOwner::Static)
            .map(|w| (w.a, w.b))
            .collect();
        for (a, b) in dynamic {
            for i in self.cells_near_segment(a, b) {
                self.walkable[i] = false;
            }
        }
        self.rebuild_buckets();
    }

    /// Walkable mask a candidate wall would produce (for placement checks), without applying it.
    pub fn walkable_with(&self, a: Vec2, b: Vec2) -> Vec<bool> {
        let mut m = self.walkable.clone();
        for i in self.cells_near_segment(a, b) {
            m[i] = false;
        }
        m
    }

    fn rebuild_buckets(&mut self) {
        let size = self.cols as f32 * self.cell;
        let hsize = self.rows as f32 * self.cell;
        self.bcols = (size / self.bucket_size).ceil() as usize + 1;
        self.brows = (hsize / self.bucket_size).ceil() as usize + 1;
        let n = self.bcols * self.brows;
        let reach = 1.0; // query radius covered by each bucket entry (m)
        let mut lists: Vec<Vec<u32>> = vec![Vec::new(); n];
        for (wi, w) in self.walls.iter().enumerate() {
            let minx = ((w.a.x.min(w.b.x) - reach) / self.bucket_size)
                .floor()
                .max(0.0) as usize;
            let maxx = (((w.a.x.max(w.b.x) + reach) / self.bucket_size).floor() as usize)
                .min(self.bcols - 1);
            let miny = ((w.a.y.min(w.b.y) - reach) / self.bucket_size)
                .floor()
                .max(0.0) as usize;
            let maxy = (((w.a.y.max(w.b.y) + reach) / self.bucket_size).floor() as usize)
                .min(self.brows - 1);
            for by in miny..=maxy {
                for bx in minx..=maxx {
                    let c = Vec2::new(
                        (bx as f32 + 0.5) * self.bucket_size,
                        (by as f32 + 0.5) * self.bucket_size,
                    );
                    // bucket centre to segment distance <= half diagonal + reach
                    if (closest_on_segment(c, w.a, w.b) - c).len()
                        <= self.bucket_size * 0.7072 + reach
                    {
                        lists[by * self.bcols + bx].push(wi as u32);
                    }
                }
            }
        }
        self.bucket_start.clear();
        self.bucket_items.clear();
        self.bucket_start.push(0);
        for l in lists {
            self.bucket_items.extend_from_slice(&l);
            self.bucket_start.push(self.bucket_items.len() as u32);
        }
    }

    /// Walls that may lie within 1 m of `p`.
    #[inline]
    pub fn walls_near(&self, p: Vec2) -> &[u32] {
        let bx = ((p.x / self.bucket_size).max(0.0) as usize).min(self.bcols - 1);
        let by = ((p.y / self.bucket_size).max(0.0) as usize).min(self.brows - 1);
        let b = by * self.bcols + bx;
        &self.bucket_items[self.bucket_start[b] as usize..self.bucket_start[b + 1] as usize]
    }

    /// Walkable area (m²) of each cell of a coarser grid with `coarse` m cells.
    pub fn coarse_walkable_area(&self, coarse: f32) -> (usize, usize, Vec<f32>) {
        let cc = (self.cols as f32 * self.cell / coarse).ceil() as usize;
        let cr = (self.rows as f32 * self.cell / coarse).ceil() as usize;
        let mut area = vec![0.0f32; cc * cr];
        for cy in 0..self.rows {
            for cx in 0..self.cols {
                if self.base[self.idx(cx, cy)] {
                    let c = self.center(cx, cy);
                    let x = ((c.x / coarse) as usize).min(cc - 1);
                    let y = ((c.y / coarse) as usize).min(cr - 1);
                    area[y * cc + x] += self.cell * self.cell;
                }
            }
        }
        (cc, cr, area)
    }

    /// Walkable area of a rectangle (m²).
    pub fn walkable_area(&self, r: &Rect) -> f32 {
        let mut a = 0.0;
        for cy in 0..self.rows {
            for cx in 0..self.cols {
                if self.base[self.idx(cx, cy)] && r.contains(self.center(cx, cy)) {
                    a += self.cell * self.cell;
                }
            }
        }
        a
    }
}

/// Geodesic distance (m) from every cell to a target disc, plus a smoothed descent direction.
pub struct Field {
    pub dist: Vec<f32>,
    pub dir: Vec<Vec2>,
    pub target: Vec2,
}

impl Field {
    pub fn empty(n: usize, target: Vec2) -> Field {
        Field {
            dist: vec![INF; n],
            dir: vec![Vec2::ZERO; n],
            target,
        }
    }
}

/// 8-connected Dijkstra (no corner cutting) from all walkable cells inside `radius` of `target`.
/// Ties resolve by cell index, so the result is deterministic.
pub fn build_field(grid: &NavGrid, mask: &[bool], target: Vec2, radius: f32) -> Field {
    let n = grid.cols * grid.rows;
    let mut f = Field::empty(n, target);
    let mut heap: BinaryHeap<Reverse<(u32, u32)>> = BinaryHeap::new();
    let c = grid.cell;
    let r = radius.max(c * 0.75);
    let (tx, ty) = (target.x / c, target.y / c);
    let span = (r / c).ceil() as isize + 1;
    for dy in -span..=span {
        for dx in -span..=span {
            let cx = tx as isize + dx;
            let cy = ty as isize + dy;
            if cx < 0 || cy < 0 || cx >= grid.cols as isize || cy >= grid.rows as isize {
                continue;
            }
            let i = grid.idx(cx as usize, cy as usize);
            if !mask[i] {
                continue;
            }
            let d = (grid.center(cx as usize, cy as usize) - target).len();
            if d <= r {
                f.dist[i] = d;
                heap.push(Reverse((d.to_bits(), i as u32)));
            }
        }
    }
    const DIRS: [(isize, isize, f32); 8] = [
        (1, 0, 1.0),
        (-1, 0, 1.0),
        (0, 1, 1.0),
        (0, -1, 1.0),
        (1, 1, std::f32::consts::SQRT_2),
        (1, -1, std::f32::consts::SQRT_2),
        (-1, 1, std::f32::consts::SQRT_2),
        (-1, -1, std::f32::consts::SQRT_2),
    ];
    let cols = grid.cols as isize;
    let rows = grid.rows as isize;
    while let Some(Reverse((dbits, i))) = heap.pop() {
        let d = f32::from_bits(dbits);
        let i = i as usize;
        if d > f.dist[i] {
            continue;
        }
        let cx = (i % grid.cols) as isize;
        let cy = (i / grid.cols) as isize;
        for (dx, dy, w) in DIRS {
            let nx = cx + dx;
            let ny = cy + dy;
            if nx < 0 || ny < 0 || nx >= cols || ny >= rows {
                continue;
            }
            let j = (ny * cols + nx) as usize;
            if !mask[j] {
                continue;
            }
            if dx != 0 && dy != 0 {
                // no corner cutting
                let a = (cy * cols + nx) as usize;
                let b = (ny * cols + cx) as usize;
                if !mask[a] || !mask[b] {
                    continue;
                }
            }
            let nd = d + w * c;
            if nd < f.dist[j] {
                f.dist[j] = nd;
                heap.push(Reverse((nd.to_bits(), j as u32)));
            }
        }
    }
    // Descent directions: weighted sum over finite neighbours of (d_here - d_there) along the offset.
    for cy in 0..rows {
        for cx in 0..cols {
            let i = (cy * cols + cx) as usize;
            let d = f.dist[i];
            if !d.is_finite() {
                continue;
            }
            let mut g = Vec2::ZERO;
            for (dx, dy, w) in DIRS {
                let nx = cx + dx;
                let ny = cy + dy;
                if nx < 0 || ny < 0 || nx >= cols || ny >= rows {
                    continue;
                }
                let j = (ny * cols + nx) as usize;
                let dn = f.dist[j];
                // Blocked neighbours repel slightly (as if one cell farther away).
                let diff = if dn.is_finite() { d - dn } else { -c * 0.5 };
                let off = Vec2::new(dx as f32, dy as f32) * (1.0 / w);
                g += off * (diff / (w * c));
            }
            let dir = g.norm();
            f.dir[i] = if dir == Vec2::ZERO {
                (target - grid.center(cx as usize, cy as usize)).norm()
            } else {
                dir
            };
        }
    }
    f
}

impl Field {
    /// Distance at a position (nearest cell; INF outside / blocked).
    #[inline]
    pub fn dist_at(&self, grid: &NavGrid, p: Vec2) -> f32 {
        match grid.cell_of(p) {
            Some((x, y)) => {
                let d = self.dist[grid.idx(x, y)];
                if d.is_finite() {
                    d
                } else {
                    self.nearby_dist(grid, x, y)
                }
            }
            None => INF,
        }
    }

    /// Agents pushed against a wall can sit in a blocked cell; use the best finite neighbour.
    fn nearby_dist(&self, grid: &NavGrid, x: usize, y: usize) -> f32 {
        let mut best = INF;
        for dy in -1isize..=1 {
            for dx in -1isize..=1 {
                let nx = x as isize + dx;
                let ny = y as isize + dy;
                if nx < 0 || ny < 0 || nx >= grid.cols as isize || ny >= grid.rows as isize {
                    continue;
                }
                let d = self.dist[grid.idx(nx as usize, ny as usize)];
                if d < best {
                    best = d + grid.cell;
                }
            }
        }
        best
    }

    /// Desired walking direction at `p`: the bilinearly blended descent direction of the four
    /// surrounding cells (straight at the target only in its immediate vicinity).
    pub fn direction(&self, grid: &NavGrid, p: Vec2) -> Vec2 {
        let to_target = self.target - p;
        let straight = to_target.len();
        let d = self.dist_at(grid, p);
        if !d.is_finite() {
            return Vec2::ZERO;
        }
        // Very close to the target the straight line is safe and avoids grid artefacts; farther
        // away a straight line could cut through a wall corner, so follow the field.
        if straight < 2.5 && d <= straight + 0.6 {
            return to_target.norm();
        }
        let c = grid.cell;
        let fx = p.x / c - 0.5;
        let fy = p.y / c - 0.5;
        let x0 = fx.floor();
        let y0 = fy.floor();
        let tx = fx - x0;
        let ty = fy - y0;
        let mut acc = Vec2::ZERO;
        for (ox, oy, w) in [
            (0.0, 0.0, (1.0 - tx) * (1.0 - ty)),
            (1.0, 0.0, tx * (1.0 - ty)),
            (0.0, 1.0, (1.0 - tx) * ty),
            (1.0, 1.0, tx * ty),
        ] {
            let cx = x0 + ox;
            let cy = y0 + oy;
            if cx < 0.0 || cy < 0.0 || cx >= grid.cols as f32 || cy >= grid.rows as f32 {
                continue;
            }
            let i = grid.idx(cx as usize, cy as usize);
            if self.dist[i].is_finite() {
                acc += self.dir[i] * w;
            }
        }
        let dir = acc.norm();
        if dir == Vec2::ZERO {
            // Pushed into a cell next to a wall that the field treats as blocked: head for the
            // lowest-distance walkable cell nearby.
            if let Some((x, y)) = grid.cell_of(p) {
                let mut best = (INF, Vec2::ZERO);
                for dy in -2isize..=2 {
                    for dx in -2isize..=2 {
                        let nx = x as isize + dx;
                        let ny = y as isize + dy;
                        if nx < 0 || ny < 0 || nx >= grid.cols as isize || ny >= grid.rows as isize
                        {
                            continue;
                        }
                        let dd = self.dist[grid.idx(nx as usize, ny as usize)];
                        if dd < best.0 {
                            best = (dd, grid.center(nx as usize, ny as usize));
                        }
                    }
                }
                if best.0.is_finite() {
                    return (best.1 - p).norm();
                }
            }
        }
        dir
    }
}

/// Cells reachable from `from` over `mask` (4-connected flood fill).
pub fn reachable(grid: &NavGrid, mask: &[bool], from: Vec2) -> Vec<bool> {
    let mut seen = vec![false; mask.len()];
    let Some((x, y)) = grid.cell_of(from) else {
        return seen;
    };
    let start = grid.idx(x, y);
    if !mask[start] {
        return seen;
    }
    let mut stack = vec![start];
    seen[start] = true;
    while let Some(i) = stack.pop() {
        let cx = i % grid.cols;
        let cy = i / grid.cols;
        let mut push = |nx: usize, ny: usize| {
            let j = ny * grid.cols + nx;
            if mask[j] && !seen[j] {
                seen[j] = true;
                stack.push(j);
            }
        };
        if cx > 0 {
            push(cx - 1, cy);
        }
        if cx + 1 < grid.cols {
            push(cx + 1, cy);
        }
        if cy > 0 {
            push(cx, cy - 1);
        }
        if cy + 1 < grid.rows {
            push(cx, cy + 1);
        }
    }
    seen
}

#[cfg(test)]
mod tests {
    use super::*;

    fn room() -> NavGrid {
        NavGrid::new([20.0, 10.0], 0.5, &[[0.0, 0.0, 20.0, 10.0]], &[])
    }

    #[test]
    fn field_is_euclidean_in_open_space() {
        let g = room();
        let f = build_field(&g, &g.walkable, Vec2::new(18.0, 5.0), 0.5);
        let d = f.dist_at(&g, Vec2::new(2.0, 5.0));
        assert!((d - 16.0).abs() < 0.8, "d={d}");
        let dir = f.direction(&g, Vec2::new(2.0, 5.0));
        assert!(dir.x > 0.99);
    }

    #[test]
    fn wall_forces_detour_and_split_is_detected() {
        let mut g = room();
        // wall with a gap at the bottom
        g.add_wall(
            Vec2::new(10.0, 0.0),
            Vec2::new(10.0, 8.0),
            WallOwner::Barrier(1),
        );
        let f = build_field(&g, &g.walkable, Vec2::new(18.0, 2.0), 0.5);
        let d = f.dist_at(&g, Vec2::new(2.0, 2.0));
        assert!(d > 18.0, "detour expected, d={d}");
        // close the gap: the target side is no longer reachable
        g.add_wall(
            Vec2::new(10.0, 8.0),
            Vec2::new(10.0, 10.0),
            WallOwner::Barrier(2),
        );
        let f = build_field(&g, &g.walkable, Vec2::new(18.0, 2.0), 0.5);
        assert!(!f.dist_at(&g, Vec2::new(2.0, 2.0)).is_finite());
        // removing a barrier restores the route
        g.remove_walls(WallOwner::Barrier(2));
        let f = build_field(&g, &g.walkable, Vec2::new(18.0, 2.0), 0.5);
        assert!(f.dist_at(&g, Vec2::new(2.0, 2.0)).is_finite());
    }

    #[test]
    fn boundary_walls_enclose_walkable_area() {
        let g = NavGrid::new([10.0, 10.0], 0.5, &[[1.0, 1.0, 4.0, 4.0]], &[]);
        // a 4x4 square has 4 boundary runs
        assert_eq!(g.walls.len(), 4);
        let total: f32 = g.walls.iter().map(|w| (w.b - w.a).len()).sum();
        assert!((total - 16.0).abs() < 1e-3);
    }
}
