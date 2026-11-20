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
//! - [`profile`]: a seed drawn into a [`model::Model`].
//! - [`model`]: the truth a store holds, keyed and numbered as STORAGE §9
//!   says.
//! - [`body`]: the bodies the model renders, with what Annex A derives.
//! - [`writer`]: a model written into a [`store::Store`].
//! - [`oracle`]: what each read answers over it, and the self-check.
//! - [`spec`], [`store`], [`name`], [`time`], [`rng`], [`error`]: the
//!   canonical text, a store, object names, instants, PCG32, failures.

pub mod body;
pub mod error;
pub mod fixture;
pub mod model;
pub mod name;
pub mod oracle;
pub mod profile;
pub mod queue;
pub mod rng;
pub mod spec;
pub mod store;
pub mod time;
pub mod writer;
