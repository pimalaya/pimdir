//! # Random numbers
//!
//! PCG32 (XSH RR, 64-bit state), pinned by algorithm so a seed gives the
//! same history on every machine and every version of every dependency.
//!
//! Refs: <https://www.pcg-random.org/paper.html>

/// A PCG32 generator: a 64-bit state and an odd increment naming its stream.
#[derive(Clone, Debug)]
pub struct Rng {
    state: u64,
    increment: u64,
}

const MULTIPLIER: u64 = 6_364_136_223_846_793_005;

impl Rng {
    /// Seeds a generator as `pcg32_srandom_r` does, on one of 2^63 streams.
    pub fn new(seed: u64, stream: u64) -> Self {
        let mut rng = Self {
            state: 0,
            increment: (stream << 1) | 1,
        };

        rng.next_u32();
        rng.state = rng.state.wrapping_add(seed);
        rng.next_u32();
        rng
    }

    /// Draws the next 32 bits.
    pub fn next_u32(&mut self) -> u32 {
        let old = self.state;
        self.state = old.wrapping_mul(MULTIPLIER).wrapping_add(self.increment);

        let shifted = (((old >> 18) ^ old) >> 27) as u32;
        let rotation = (old >> 59) as u32;
        shifted.rotate_right(rotation)
    }

    /// Draws a number below `bound` without bias, as `pcg32_boundedrand_r`.
    pub fn below(&mut self, bound: u32) -> u32 {
        let threshold = bound.wrapping_neg() % bound;
        loop {
            let draw = self.next_u32();
            if draw >= threshold {
                return draw % bound;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::rng::Rng;

    #[test]
    fn the_reference_sequence_of_seed_42_stream_54() {
        let mut rng = Rng::new(42, 54);
        let drawn: Vec<u32> = (0..6).map(|_| rng.next_u32()).collect();
        let reference = [
            0xa15c_02b7,
            0x7b47_f409,
            0xba1d_3330,
            0x83d2_f293,
            0xbfa4_784b,
            0xcbed_606e,
        ];
        assert_eq!(drawn, reference);
    }
}
