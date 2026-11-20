//! # Object names
//!
//! A body's name: its BLAKE3 digest at 32 bytes in lowercase RFC 4648 §6
//! base32 with no padding, 52 characters, and its path one shard deep
//! (STORAGE §5).
//!
//! Refs: <https://datatracker.ietf.org/doc/html/rfc4648#section-6>

/// The name a body is stored under.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ObjectName(pub String);

impl ObjectName {
    /// Names `bytes` by their digest.
    pub fn of(bytes: &[u8]) -> Self {
        Self(base32(blake3::hash(bytes).as_bytes()))
    }

    /// The path under the store's directory, objects/, the first two
    /// characters, then the name.
    pub fn path(&self) -> String {
        format!("objects/{}/{}", &self.0[..2], self.0)
    }
}

const ALPHABET: &[u8; 32] = b"abcdefghijklmnopqrstuvwxyz234567";

/// Encodes `bytes` in lowercase base32, no padding.
pub fn base32(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len().div_ceil(5) * 8);
    let mut buffer: u32 = 0;
    let mut bits = 0;

    for byte in bytes {
        buffer = (buffer << 8) | u32::from(*byte);
        bits += 8;
        while bits >= 5 {
            bits -= 5;
            out.push(char::from(ALPHABET[((buffer >> bits) & 31) as usize]));
        }
    }

    if bits > 0 {
        out.push(char::from(ALPHABET[((buffer << (5 - bits)) & 31) as usize]));
    }

    out
}

#[cfg(test)]
mod tests {
    use serde_json::Value;

    use crate::{
        name::{ObjectName, base32},
        spec::Spec,
    };

    fn objects() -> Value {
        let path = Spec::default_root().join("vectors/objects.json");
        let text = std::fs::read_to_string(&path).unwrap();
        serde_json::from_str(&text).unwrap()
    }

    fn hex(text: &str) -> Vec<u8> {
        (0..text.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&text[i..i + 2], 16).unwrap())
            .collect()
    }

    #[test]
    fn base32_encodes_every_case_of_the_vectors() {
        let objects = objects();
        let cases = objects["base32"]["cases"].as_array().unwrap();
        assert!(!cases.is_empty());

        for case in cases {
            let input = hex(case["input_hex"].as_str().unwrap());
            assert_eq!(base32(&input), case["base32"].as_str().unwrap());
        }
    }

    #[test]
    fn every_object_of_the_vectors_is_named_and_placed() {
        let objects = objects();
        let cases = objects["objects"].as_array().unwrap();
        assert!(!cases.is_empty());

        for case in cases {
            let body = match case["body_hex"].as_str() {
                Some(text) => hex(text),
                None => {
                    let len = case["body_len"].as_u64().unwrap() as usize;
                    (0..len).map(|i| (i % 251) as u8).collect()
                }
            };
            let name = ObjectName::of(&body);
            let label = case["label"].as_str().unwrap();

            assert_eq!(name.0, case["blake3"]["name"].as_str().unwrap(), "{label}");
            assert_eq!(
                name.path(),
                case["blake3"]["path"].as_str().unwrap(),
                "{label}"
            );
        }
    }
}
