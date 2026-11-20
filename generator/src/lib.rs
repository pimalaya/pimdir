//! # pimdir-generator
//!
//! The pimdir standard's own test tooling: deterministic histories, the
//! stores they leave and what a conforming implementation answers over
//! them. README.md beside this crate is its design note, scenarios.md the
//! catalogue its events are drawn from.
//!
//! The crate depends on no Pimalaya crate. A store is written by the
//! canonical statements under queries/ and migrations/ alone, loaded from
//! the tree above the crate ([`spec`]), so the standard tests itself.
//!
//! - [`rng`]: the PCG32 generator every choice is drawn from.
//! - [`name`]: a body's object name and path (STORAGE §5).
//! - [`spec`]: the canonical statements and migrations, held to
//!   queries/signatures.json.
//! - [`store`]: a store created and written through them.
//! - [`error`]: what each of them fails with.

pub mod error;
pub mod name;
pub mod rng;
pub mod spec;
pub mod store;
