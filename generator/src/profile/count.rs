//! # The count profile
//!
//! Many small items in hundreds of collections, a mail tree six deep, for
//! listing, merge and scale tests (README.md, "Profiles"). Every identity
//! is fresh, so each item is placed under its own key and a `seq` drawn for
//! it, and a message copied into an archive shares the `seq` of its first
//! filing (STORAGE §9.1), the model never scanning what it holds per item.

use std::collections::{BTreeMap, BTreeSet};

use crate::{
    body::{Filed, Time},
    model::{Collection, Kind, Model, Placement, Presentation, Scope, SourceState, key},
    profile::Draw,
};

/// The accounts the profile spreads over.
const ACCOUNTS: [&str; 3] = ["work", "home", "club"];

/// The mailboxes each account holds, roots and nested ones together.
const MAILBOXES: usize = 100;

/// The deepest a mailbox nests.
const DEPTH: usize = 6;

/// The mailboxes a client lists first, in this order.
const SPECIAL: [&str; 4] = ["INBOX", "Sent", "Drafts", "Archive"];

impl Draw {
    /// The count profile at `items` items.
    pub(crate) fn count(mut self, items: usize) -> Model {
        self.run = format!("count-{}", self.rng.next_u32());
        let mut model = Model::new();
        let mut kinds: BTreeMap<Kind, Vec<String>> = BTreeMap::new();

        for account in ACCOUNTS {
            for path in self.tree() {
                let source = (path != "Local").then(|| format!("{account}-imap"));
                let role = match path.as_str() {
                    "INBOX" => Some("inbox"),
                    "Archive" => Some("archive"),
                    "Sent" => Some("sent"),
                    _ => None,
                };
                let id = format!("{account}/{path}");
                declare(&mut model, &id, account, Kind::Mail, role, source);
                kinds.entry(Kind::Mail).or_default().push(id);
            }
            for book in ["contacts", "colleagues"] {
                let id = format!("{account}/{book}");
                let source = Some(format!("{account}-carddav"));
                declare(&mut model, &id, account, Kind::Contact, None, source);
                kinds.entry(Kind::Contact).or_default().push(id);
            }
            for calendar in ["calendar", "holidays", "team"] {
                let id = format!("{account}/{calendar}");
                let source = Some(format!("{account}-caldav"));
                declare(&mut model, &id, account, Kind::Calendar, None, source);
                kinds.entry(Kind::Calendar).or_default().push(id);
            }
        }
        for collection in model.collections.values_mut() {
            let (account, path) = collection.id.split_once('/').expect("an account's");
            collection.parent = path
                .rsplit_once('/')
                .map(|(up, _)| format!("{account}/{up}"));
            let sort_order = SPECIAL.iter().position(|special| *special == path);
            let color = (collection.kind == Some(Kind::Calendar))
                .then(|| format!("#{:06x}", self.rng.next_u32() & 0xff_ffff));
            let description = (collection.kind == Some(Kind::Contact))
                .then(|| format!("{} {path}", self.pick(&WORDS)));
            collection.presentation = Presentation {
                color,
                description,
                sort_order: sort_order.map(|at| at as i64),
            };
        }
        for collections in kinds.values_mut() {
            for index in (1..collections.len()).rev() {
                let other = self.rng.below(index as u32 + 1) as usize;
                collections.swap(index, other);
            }
        }

        let mut handles: BTreeMap<String, u32> = BTreeMap::new();
        for _ in 0..items {
            let kind = match self.rng.below(10) {
                0 => Kind::Contact,
                1 => Kind::Calendar,
                _ => Kind::Mail,
            };
            let collections = &kinds[&kind];
            let skew = f64::from(self.rng.next_u32()) / f64::from(u32::MAX);
            let at = ((collections.len() as f64) * skew.powi(3)) as usize;
            let id = collections[at.min(collections.len() - 1)].clone();
            let (filed, mutable) = match kind {
                Kind::Mail => (self.message(false).file(), false),
                Kind::Contact => (self.card().file(), true),
                _ => {
                    let start = Time::Utc(self.instant());
                    (self.event(start).file(), true)
                }
            };
            let held = mutable || self.rng.below(10) > 0;
            let seq = model.fresh_seq();
            self.put(
                &mut model,
                &mut handles,
                &id,
                seq,
                filed.clone(),
                held,
                mutable,
            );

            let account = &id[..id.find('/').unwrap_or(0)];
            let archive = format!("{account}/Archive");
            if kind == Kind::Mail && id != archive && self.rng.below(100) == 0 {
                self.put(&mut model, &mut handles, &archive, seq, filed, held, false);
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

    /// The mailbox paths of one account: its roots, then a chain `DEPTH`
    /// deep, then mailboxes nested under a drawn parent up to that depth.
    fn tree(&mut self) -> Vec<String> {
        let mut paths: Vec<String> = ["INBOX", "Archive", "Sent", "Drafts", "Lists", "Local"]
            .map(String::from)
            .to_vec();
        let mut chain = String::from("Projects");
        paths.push(chain.clone());
        for _ in 1..DEPTH {
            chain = format!("{chain}/{}{}", self.pick(&WORDS), self.next());
            paths.push(chain.clone());
        }
        while paths.len() < MAILBOXES {
            let parent = paths[self.rng.below(paths.len() as u32) as usize].clone();
            if parent == "Local" || parent.matches('/').count() + 1 >= DEPTH {
                continue;
            }
            paths.push(format!("{parent}/{}{}", self.pick(&WORDS), self.next()));
        }
        paths
    }

    /// Places one item under its own key and `seq`, bound by the
    /// collection's source under the next handle there, stamped by its
    /// first round.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn put(
        &mut self,
        model: &mut Model,
        handles: &mut BTreeMap<String, u32>,
        collection: &str,
        seq: i64,
        filed: Filed,
        held: bool,
        mutable: bool,
    ) -> usize {
        let next = handles.entry(String::from(collection)).or_insert(0);
        *next += 1;
        let handle = match mutable {
            true => format!("r{next}.ics"),
            false => next.to_string(),
        };
        let mut flags = BTreeSet::new();
        if !mutable {
            if self.rng.below(10) < 7 {
                flags.insert(String::from("\\Seen"));
            }
            if self.rng.below(20) == 0 {
                flags.insert(String::from("\\Flagged"));
            }
        }
        let placement = Placement {
            flags: Some(flags),
            held,
            handle: Some(handle.clone()),
            revision: mutable.then(|| format!("\"{next}\"")),
            source: None,
        };
        let link_id = key(&filed);
        let index = model.place(collection, link_id, seq, handle, filed, placement);
        for binding in &mut model.items[index].bindings {
            binding.round = Some(1);
        }
        index
    }
}

/// Declares one collection of the profile, synced by `source` or local.
pub(crate) fn declare(
    model: &mut Model,
    id: &str,
    account: &str,
    kind: Kind,
    role: Option<&str>,
    source: Option<String>,
) {
    let name = id.rsplit('/').next().unwrap_or(id);
    model.declare(Collection {
        id: String::from(id),
        account: Some(String::from(account)),
        kind: Some(kind),
        name: String::from(name),
        role: role.map(String::from),
        sources: source
            .into_iter()
            .map(|source| (source, SourceState::default()))
            .collect(),
        conflict: String::from("manual"),
        generation: 1,
        parent: None,
        presentation: Presentation::default(),
    });
}

/// The words nested mailboxes are named from.
const WORDS: [&str; 8] = [
    "clients", "invoices", "travel", "reports", "family", "music", "school", "archive",
];

#[cfg(test)]
pub(crate) mod tests {
    use std::{
        collections::{BTreeMap, BTreeSet},
        env, fs, process,
    };

    use crate::{
        model::{Kind, Model},
        oracle,
        profile::{Profile, count},
        spec::Spec,
        store::Store,
        writer,
    };

    /// Writes `model` into a fresh store and checks every read against it,
    /// as it is stated, pages `page` rows long.
    pub(crate) fn written(model: &Model, name: &str, page: i64) {
        let spec = Spec::load_default().unwrap();
        let dir = env::temp_dir().join(format!("pimdir-generator-{name}-{}", process::id()));
        let _ = fs::remove_dir_all(&dir);
        let store = Store::create(&spec, &dir).unwrap();
        writer::materialise(model, &store).unwrap();
        let disagreements = oracle::check_model(&store, model, &spec, page).unwrap();
        assert!(disagreements.is_empty(), "{name}: {disagreements:#?}");
        let faults = oracle::feed::order(&store).unwrap();
        assert!(faults.is_empty(), "{name}: {faults:#?}");
        drop(store);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn the_count_profile_spreads_its_items_over_a_deep_tree_of_collections() {
        let model = count(5, 3_000);

        assert!(model.collections.len() >= 300);
        let deepest = model
            .collections
            .keys()
            .map(|id| id.matches('/').count())
            .max()
            .unwrap();
        assert!(deepest >= 6, "a mailbox six levels under its account");
        let depth = |id: &String| {
            let mut depth = 0;
            let mut at = model.collections[id].parent.clone();
            while let Some(parent) = at {
                let up = &model.collections[&parent];
                assert_eq!(
                    up.account, model.collections[id].account,
                    "a forest per account"
                );
                depth += 1;
                at = up.parent.clone();
            }
            depth
        };
        assert!(
            model.collections.keys().map(depth).max().unwrap() >= 5,
            "a hierarchy by parent"
        );
        assert!(
            model
                .collections
                .values()
                .any(|collection| collection.presentation.color.is_some())
        );
        assert!(
            model
                .collections
                .values()
                .any(|collection| collection.presentation.sort_order.is_some())
        );
        for kind in [Kind::Mail, Kind::Contact, Kind::Calendar] {
            let holding = model
                .items
                .iter()
                .filter(|item| model.collections[&item.collection].kind == Some(kind))
                .count();
            assert!(holding > 100, "{kind:?}");
        }
        assert!(model.items.len() > 3_000, "copies into an archive");

        let mut placed = BTreeSet::new();
        let mut keys: BTreeMap<i64, BTreeSet<&String>> = BTreeMap::new();
        for item in &model.items {
            assert!(placed.insert((&item.collection, item.seq)));
            keys.entry(item.seq).or_default().insert(&item.link_id);
        }
        assert!(
            keys.values().all(|links| links.len() == 1),
            "a seq is one identity"
        );
        assert!(keys.len() < model.items.len(), "a copy shares its seq");

        let again = count(5, 3_000);
        let same = |model: &Model| -> Vec<(String, i64)> {
            let items = model.items.iter();
            items.map(|item| (item.link_id.clone(), item.seq)).collect()
        };
        assert_eq!(same(&model), same(&again));
    }

    #[test]
    fn a_count_store_reads_back_what_its_model_states() {
        written(&count(7, 2_000), "count", oracle::PAGE);
    }

    #[test]
    #[ignore = "the profile's own size, minutes in a debug build"]
    fn a_count_store_at_the_profile_size_reads_back_what_its_model_states() {
        let spec = Spec::load_default().unwrap();
        let model = Profile::Count.generate(&spec, 1).unwrap();
        assert!(model.items.len() >= 100_000);
        written(&model, "count-full", 1_000);
    }
}
