//! Small 2D vector type and deterministic math.
//!
//! Determinism rule for the whole crate: only IEEE-754 basic operations (+ - * / sqrt) come from the
//! hardware; every transcendental function goes through the pure-Rust `libm` crate so native
//! (x86_64) and wasm32 builds produce bit-identical results. No `mul_add`, no fast-math.

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Vec2 {
    pub x: f32,
    pub y: f32,
}

impl Vec2 {
    pub const ZERO: Vec2 = Vec2 { x: 0.0, y: 0.0 };

    #[inline]
    pub const fn new(x: f32, y: f32) -> Self {
        Vec2 { x, y }
    }
    #[inline]
    pub fn dot(self, o: Vec2) -> f32 {
        self.x * o.x + self.y * o.y
    }
    #[inline]
    pub fn cross(self, o: Vec2) -> f32 {
        self.x * o.y - self.y * o.x
    }
    #[inline]
    pub fn len_sq(self) -> f32 {
        self.dot(self)
    }
    #[inline]
    pub fn len(self) -> f32 {
        self.len_sq().sqrt()
    }
    /// Unit vector, or zero for (near-)zero input.
    #[inline]
    pub fn norm(self) -> Vec2 {
        let l = self.len();
        if l > 1e-6 {
            Vec2::new(self.x / l, self.y / l)
        } else {
            Vec2::ZERO
        }
    }
    #[inline]
    pub fn perp(self) -> Vec2 {
        Vec2::new(-self.y, self.x)
    }
    #[inline]
    pub fn dist(self, o: Vec2) -> f32 {
        (self - o).len()
    }
}

impl std::ops::Add for Vec2 {
    type Output = Vec2;
    #[inline]
    fn add(self, o: Vec2) -> Vec2 {
        Vec2::new(self.x + o.x, self.y + o.y)
    }
}
impl std::ops::Sub for Vec2 {
    type Output = Vec2;
    #[inline]
    fn sub(self, o: Vec2) -> Vec2 {
        Vec2::new(self.x - o.x, self.y - o.y)
    }
}
impl std::ops::Mul<f32> for Vec2 {
    type Output = Vec2;
    #[inline]
    fn mul(self, k: f32) -> Vec2 {
        Vec2::new(self.x * k, self.y * k)
    }
}
impl std::ops::AddAssign for Vec2 {
    #[inline]
    fn add_assign(&mut self, o: Vec2) {
        self.x += o.x;
        self.y += o.y;
    }
}
impl std::ops::Neg for Vec2 {
    type Output = Vec2;
    #[inline]
    fn neg(self) -> Vec2 {
        Vec2::new(-self.x, -self.y)
    }
}

#[inline]
pub fn exp(x: f32) -> f32 {
    libm::expf(x)
}

#[inline]
pub fn sin(x: f32) -> f32 {
    libm::sinf(x)
}

#[inline]
pub fn cos(x: f32) -> f32 {
    libm::cosf(x)
}

#[inline]
pub fn atan2(y: f32, x: f32) -> f32 {
    libm::atan2f(y, x)
}

#[inline]
pub fn clamp(v: f32, lo: f32, hi: f32) -> f32 {
    if v < lo {
        lo
    } else if v > hi {
        hi
    } else {
        v
    }
}

/// Closest point on segment ab to p.
#[inline]
pub fn closest_on_segment(p: Vec2, a: Vec2, b: Vec2) -> Vec2 {
    let ab = b - a;
    let l2 = ab.len_sq();
    if l2 < 1e-12 {
        return a;
    }
    let t = clamp((p - a).dot(ab) / l2, 0.0, 1.0);
    a + ab * t
}

/// Whether segments p1p2 and q1q2 properly intersect (touching endpoints count).
pub fn segments_intersect(p1: Vec2, p2: Vec2, q1: Vec2, q2: Vec2) -> bool {
    let d1 = (q2 - q1).cross(p1 - q1);
    let d2 = (q2 - q1).cross(p2 - q1);
    let d3 = (p2 - p1).cross(q1 - p1);
    let d4 = (p2 - p1).cross(q2 - p1);
    ((d1 > 0.0 && d2 < 0.0) || (d1 < 0.0 && d2 > 0.0))
        && ((d3 > 0.0 && d4 < 0.0) || (d3 < 0.0 && d4 > 0.0))
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
}

impl Rect {
    pub fn from_arr(a: [f32; 4]) -> Rect {
        Rect {
            x: a[0],
            y: a[1],
            w: a[2],
            h: a[3],
        }
    }
    #[inline]
    pub fn contains(&self, p: Vec2) -> bool {
        p.x >= self.x && p.y >= self.y && p.x < self.x + self.w && p.y < self.y + self.h
    }
    pub fn center(&self) -> Vec2 {
        Vec2::new(self.x + self.w * 0.5, self.y + self.h * 0.5)
    }
    pub fn area(&self) -> f32 {
        self.w * self.h
    }
}
