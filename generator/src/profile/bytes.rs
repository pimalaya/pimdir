//! # The bytes profile
//!
//! A few hundred messages carrying large attachments, one past 25 MB and
//! one past 100 MB, for the blob store, fetch and append paths (README.md,
//! "Profiles"). Each body is a [`Stream`](crate::body::Stream) rendered
//! from its seed when it is written and never held whole; a copy filed in
//! the archive shares its first filing's body and `seq`.

use std::collections::BTreeMap;

use crate::{
    model::{Kind, Model, Scope, SourceState},
    profile::{Draw, count::declare},
};

/// The messages besides the two largest.
const MESSAGES: usize = 300;

/// The two largest bodies, in bytes: one past 25 MB, one past 100 MB.
const LARGEST: [usize; 2] = [26 * 1024 * 1024, 101 * 1024 * 1024];

/// The bounds the other bodies' sizes are drawn between, log-uniformly.
const SIZES: (f64, f64) = (16.0 * 1024.0, 4.0 * 1024.0 * 1024.0);

impl Draw {
    /// The bytes profile, every size divided by `scale`.
    pub(crate) fn large(mut self, scale: usize) -> Model {
        self.run = format!("bytes-{}", self.rng.next_u32());
        let mut model = Model::new();
        let source = Some(String::from("work-imap"));
        declare(
            &mut model,
            "work/INBOX",
            "work",
            Kind::Mail,
            Some("inbox"),
            source.clone(),
        );
        declare(
            &mut model,
            "work/Archive",
            "work",
            Kind::Mail,
            Some("archive"),
            source,
        );
        declare(&mut model, "work/Local", "work", Kind::Mail, None, None);

        let mut sizes: Vec<usize> = (0..MESSAGES)
            .map(|_| {
                let draw = f64::from(self.rng.next_u32()) / f64::from(u32::MAX);
                (SIZES.0 * (SIZES.1 / SIZES.0).powf(draw)) as usize
            })
            .collect();
        sizes.extend(LARGEST);

        let mut handles: BTreeMap<String, u32> = BTreeMap::new();
        for (index, size) in sizes.into_iter().enumerate() {
            let collection = match index % 10 {
                9 => "work/Local",
                _ => "work/INBOX",
            };
            let lines = (size / scale.max(1) / 78).max(1);
            let message = self.message(false);
            let seed = self.u64();
            let (filed, stream) = message.stream(&format!("payload-{index}.bin"), seed, lines);
            let held = self.rng.below(20) > 0 || size >= LARGEST[0];
            let seq = model.fresh_seq();
            let copied = index % 25 == 0 || size >= LARGEST[0];
            let mut placed = vec![self.put(
                &mut model,
                &mut handles,
                collection,
                seq,
                filed.clone(),
                false,
                false,
            )];
            if copied {
                placed.push(self.put(
                    &mut model,
                    &mut handles,
                    "work/Archive",
                    seq,
                    filed,
                    false,
                    false,
                ));
            }
            if held {
                let name = stream.name();
                for at in placed {
                    model.hold_stream(at, name.clone(), stream.clone());
                }
            }
        }

        for collection in model.collections.values_mut() {
            for sync in collection.sources.values_mut() {
                *sync = SourceState {
                    checkpoint: Some(b"c1".to_vec()),
                    rounds: 1,
                    coverage: Some(Scope::default()),
                    open: None,
                };
            }
        }
        model
    }
}

#[cfg(test)]
mod tests {
    use std::{collections::BTreeMap, env, fs, process};

    use rusqlite::types::Value;

    use crate::{
        body::Stream,
        name::ObjectName,
        oracle,
        profile::{Profile, bytes, count::tests::written},
        spec::Spec,
        store::Store,
        writer,
    };

    #[test]
    fn a_stream_renders_the_bytes_its_size_and_name_state() {
        let model = bytes(3, 1_000);
        let largest = model.streams.values().map(Stream::size).max().unwrap();
        assert!(largest > 101 * 1024 * 1024 / 1_000);

        for (name, stream) in &model.streams {
            let mut rendered = Vec::new();
            stream
                .render(|chunk| {
                    rendered.extend_from_slice(chunk);
                    Ok(())
                })
                .unwrap();
            assert_eq!(rendered.len(), stream.size());
            assert_eq!(&ObjectName::of(&rendered), name);
            assert!(rendered.ends_with(&stream.tail));
        }

        let mut holders: BTreeMap<&ObjectName, usize> = BTreeMap::new();
        for item in &model.items {
            if let Some(name) = &item.object {
                *holders.entry(name).or_default() += 1;
                let size = model.object_size(name) as i64;
                assert_eq!(item.summary.get("size"), Value::Integer(size));
            }
        }
        assert!(
            holders.values().any(|count| *count > 1),
            "a copy shares its body"
        );
    }

    #[test]
    fn a_bytes_store_holds_each_stream_as_rendered() {
        let model = bytes(4, 1_000);
        written(&model, "bytes", oracle::PAGE);

        let spec = Spec::load_default().unwrap();
        let dir = env::temp_dir().join(format!("pimdir-generator-blobs-{}", process::id()));
        let _ = fs::remove_dir_all(&dir);
        let store = Store::create(&spec, &dir).unwrap();
        writer::materialise(&model, &store).unwrap();
        for name in model.streams.keys() {
            let held = fs::read(dir.join(name.path())).unwrap();
            assert_eq!(&ObjectName::of(&held), name);
        }
        drop(store);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    #[ignore = "the profile's own size, past 100 MB on disk"]
    fn a_bytes_store_at_the_profile_size_reads_back_what_its_model_states() {
        let spec = Spec::load_default().unwrap();
        let model = Profile::Bytes.generate(&spec, 1).unwrap();
        written(&model, "bytes-full", oracle::PAGE);
    }
}
