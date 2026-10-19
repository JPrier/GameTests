//! Explicitly seeded PRNG with independent streams.
//!
//! Each gameplay concern draws from its own stream so that, for example, adding a presentation-only
//! random effect can never shift the arrival or incident sequence.

/// SplitMix64: tiny, fast, and fully specified (identical on every platform).
#[derive(Clone, Debug)]
pub struct Rng {
    state: u64,
}

impl Rng {
    pub fn new(seed: u64) -> Rng {
        Rng { state: seed }
    }

    /// Derive an independent stream from a master seed and a stream id.
    pub fn stream(seed: u64, stream: Stream) -> Rng {
        let mut r = Rng::new(seed ^ (stream as u64).wrapping_mul(0xA076_1D64_78BD_642F));
        // decorrelate nearby seeds
        r.next_u64();
        r.next_u64();
        r
    }

    #[inline]
    pub fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// Uniform in [0, 1) with 24 bits of precision (exact in f32).
    #[inline]
    pub fn f32(&mut self) -> f32 {
        ((self.next_u64() >> 40) as f32) * (1.0 / 16_777_216.0)
    }

    #[inline]
    pub fn range(&mut self, lo: f32, hi: f32) -> f32 {
        lo + (hi - lo) * self.f32()
    }

    /// Uniform integer in [lo, hi] inclusive.
    #[inline]
    pub fn int(&mut self, lo: i64, hi: i64) -> i64 {
        if hi <= lo {
            return lo;
        }
        let span = (hi - lo + 1) as u64;
        lo + (self.next_u64() % span) as i64
    }

    /// Pick an index with probability proportional to `weights` (all >= 0).
    pub fn weighted(&mut self, weights: &[f32]) -> usize {
        let total: f32 = weights.iter().sum();
        if total <= 0.0 {
            return 0;
        }
        let mut t = self.f32() * total;
        for (i, w) in weights.iter().enumerate() {
            if t < *w {
                return i;
            }
            t -= *w;
        }
        weights.len() - 1
    }
}

/// Independent random streams. Values are part of the replay format: never renumber.
#[derive(Clone, Copy, Debug)]
#[repr(u64)]
pub enum Stream {
    Arrivals = 1,
    Traits = 2,
    Incidents = 3,
    Modifiers = 4,
    Decisions = 5,
    /// Presentation only (never read by the simulation).
    Presentation = 6,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn same_seed_same_sequence() {
        let mut a = Rng::stream(42, Stream::Arrivals);
        let mut b = Rng::stream(42, Stream::Arrivals);
        for _ in 0..1000 {
            assert_eq!(a.next_u64(), b.next_u64());
        }
    }

    #[test]
    fn streams_are_independent() {
        let mut a = Rng::stream(42, Stream::Arrivals);
        let mut b = Rng::stream(42, Stream::Traits);
        let same = (0..100).filter(|_| a.next_u64() == b.next_u64()).count();
        assert_eq!(same, 0);
    }

    #[test]
    fn known_values_are_stable() {
        // Pinned so a change in the generator (which would break every replay) fails loudly.
        let mut r = Rng::new(0);
        assert_eq!(r.next_u64(), 0xE220_A839_7B1D_CDAF);
    }

    #[test]
    fn f32_in_unit_interval() {
        let mut r = Rng::new(7);
        for _ in 0..10_000 {
            let v = r.f32();
            assert!((0.0..1.0).contains(&v));
        }
    }
}
